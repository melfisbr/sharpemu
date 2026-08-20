. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

if($b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')){
    Write-Host '[V74.0.67.2.10.2] Source already patched.'
    return
}

function Replace-One {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $count=Count-Ordinal -Text $Text -Needle $Old
    if($count-ne 1){
        throw "[V74.0.67.2.10.2] Anchor '$Label' count=$count expected=1"
    }
    return $Text.Replace($Old,$New)
}

# 1) Failure/retry state. Anchor only to its owning field; V74.0.67 runtime
# counters are allowed to follow it.
$fieldAnchor='        private uint _upscalerInitHeight;'
$fieldInsert=@'

        // V74.0.67.2.10.2 lazy last-error + init-size retry
        private uint _upscalerInitFailedWidth;
        private uint _upscalerInitFailedHeight;
        private string _upscalerInitFailureReason = string.Empty;
'@
$b=Replace-One `
    -Text $b `
    -Old $fieldAnchor `
    -New ($fieldAnchor+$fieldInsert) `
    -Label 'init failure fields'

# 2) Optional last-error ABI.
# Do NOT rewrite TryLoad: V74.0.67.1 already owns provider-load diagnostics.
# Resolve the optional export lazily from the NativeLibrary handle instead,
# making this compatible with the accumulated V74.0.67.1 loader shape.
$oldDelegate=@'
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ShutdownDelegate();
'@
$newDelegate=@'
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ShutdownDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate nint GetLastErrorDelegate();
'@
$b=Replace-One $b $oldDelegate $newDelegate 'last-error delegate'

$oldClassFields=@'
            private readonly CapabilitiesDelegate _capabilities;
            private readonly ShutdownDelegate _shutdown;
            private bool _initialized;
'@
$newClassFields=@'
            private readonly CapabilitiesDelegate _capabilities;
            private readonly ShutdownDelegate _shutdown;
            private GetLastErrorDelegate? _getLastError;
            private bool _lastErrorExportResolved;
            private bool _initialized;

            public int LastInitializeResult { get; private set; }
'@
$b=Replace-One $b $oldClassFields $newClassFields 'native class fields'

$capabilitiesAnchor=@'
            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();
'@
$capabilitiesWithLastError=@'
            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();

            public bool HasLastErrorExport
            {
                get
                {
                    EnsureLastErrorExport();
                    return _getLastError is not null;
                }
            }

            public string LastError
            {
                get
                {
                    EnsureLastErrorExport();
                    if (_getLastError is null)
                    {
                        return string.Empty;
                    }

                    var pointer = _getLastError();
                    if (pointer == 0)
                    {
                        return string.Empty;
                    }

                    return (Marshal.PtrToStringUTF8(pointer) ?? string.Empty)
                        .Replace('\r', ' ')
                        .Replace('\n', ' ')
                        .Trim();
                }
            }

            private void EnsureLastErrorExport()
            {
                if (_lastErrorExportResolved)
                {
                    return;
                }

                _lastErrorExportResolved = true;
                if (NativeLibrary.TryGetExport(
                        _library,
                        "sharpemu_vk_upscaler_get_last_error",
                        out var symbol))
                {
                    _getLastError =
                        Marshal.GetDelegateForFunctionPointer<GetLastErrorDelegate>(
                            symbol);
                }
            }
'@
$b=Replace-One `
    -Text $b `
    -Old $capabilitiesAnchor `
    -New $capabilitiesWithLastError `
    -Label 'capabilities + lazy last-error property'

$oldInitialize=@'
            public unsafe bool Initialize(NativeUpscalerInitDesc desc)
            {
                if (_initialized)
                {
                    return true;
                }

                var result = _initialize(&desc);
                _initialized = result == 0;
                return _initialized;
            }
'@
$newInitialize=@'
            public unsafe bool Initialize(NativeUpscalerInitDesc desc)
            {
                if (_initialized)
                {
                    LastInitializeResult = 0;
                    return true;
                }

                var result = _initialize(&desc);
                LastInitializeResult = result;
                _initialized = result == 0;
                return _initialized;
            }
'@
$b=Replace-One $b $oldInitialize $newInitialize 'native initialize result capture'

# 3) Bound edits strictly to TryInitializeUpscaler.
$initSignature=
    '        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)'
$ensureSignature=
    '        private bool TryEnsureUpscalerOutput('

$initStart=$b.IndexOf($initSignature,[StringComparison]::Ordinal)
$initEnd=if($initStart-ge 0){
    $b.IndexOf($ensureSignature,$initStart,[StringComparison]::Ordinal)
}else{-1}

if($initStart-lt 0 -or $initEnd-le $initStart){
    throw '[V74.0.67.2.10.2] Cannot isolate TryInitializeUpscaler region.'
}
$init=$b.Substring($initStart,$initEnd-$initStart)

$oldHead=@'
        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;
            if (_upscalerInitAttempted &&
'@
$newHead=@'
        private void RecordUpscalerInitFailure(
            uint outputWidth,
            uint outputHeight,
            string reason)
        {
            _upscalerInitFailedWidth = outputWidth;
            _upscalerInitFailedHeight = outputHeight;
            _upscalerInitFailureReason = string.IsNullOrWhiteSpace(reason)
                ? "unspecified"
                : reason;
        }

        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;

            if (_upscalerInitAttempted &&
                _nativeUpscaler is null &&
                (_upscalerInitFailedWidth != outputWidth ||
                 _upscalerInitFailedHeight != outputHeight))
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=retry_size_change " +
                    $"previous={_upscalerInitFailedWidth}x{_upscalerInitFailedHeight} " +
                    $"requested={outputWidth}x{outputHeight} " +
                    $"previous_reason={_upscalerInitFailureReason}");
                _upscalerInitAttempted = false;
                _upscalerInitFailureReason = string.Empty;
                _upscalerOutputReset = true;
            }

            if (_upscalerInitAttempted &&
'@
if((Count-Ordinal -Text $init -Needle $oldHead)-ne 1){
    throw '[V74.0.67.2.10.2] Init-header anchor mismatch.'
}
$init=$init.Replace($oldHead,$newHead)

$oldExt=@'
            if (_upscalerRequiredExtensionMissing)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] required Vulkan extension negotiation failed; using normal Vulkan presentation.");
                return false;
            }
'@
$newExt=@'
            if (_upscalerRequiredExtensionMissing)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "required_vulkan_extension_negotiation_failed");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result=managed output={outputWidth}x{outputHeight} " +
                    $"last_error=required_vulkan_extension_negotiation_failed");
                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldExt)-ne 1){
    throw '[V74.0.67.2.10.2] Extension-failure anchor mismatch.'
}
$init=$init.Replace($oldExt,$newExt)

$oldNull=@'
            if (provider is null)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER] provider DLL not present; Vulkan presenter fallback remains active.");
                return false;
            }
'@
$newNull=@'
            if (provider is null)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "provider_dll_not_loaded");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result=managed output={outputWidth}x{outputHeight} " +
                    $"last_error=provider_dll_not_loaded");
                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldNull)-ne 1){
    throw '[V74.0.67.2.10.2] Provider-null anchor mismatch.'
}
$init=$init.Replace($oldNull,$newNull)

$oldFail=@'
            if (!provider.Initialize(desc))
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider initialization failed; using normal Vulkan presentation.");
                provider.Dispose();
                _nativeUpscaler = null;
                return false;
            }

            _upscalerInitWidth = outputWidth;
            _upscalerInitHeight = outputHeight;
'@
$newFail=@'
            if (!provider.Initialize(desc))
            {
                var nativeError = provider.LastError;
                if (string.IsNullOrWhiteSpace(nativeError))
                {
                    nativeError =
                        "native_provider_returned_failure_without_error_text";
                }

                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    nativeError);

                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result={provider.LastInitializeResult} " +
                    $"output={outputWidth}x{outputHeight} " +
                    $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)} " +
                    $"last_error={nativeError}");

                provider.Dispose();
                _nativeUpscaler = null;
                return false;
            }

            _upscalerInitWidth = outputWidth;
            _upscalerInitHeight = outputHeight;
            _upscalerInitFailedWidth = 0;
            _upscalerInitFailedHeight = 0;
            _upscalerInitFailureReason = string.Empty;

            Console.Error.WriteLine(
                $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=active " +
                $"result=0 output={outputWidth}x{outputHeight} " +
                $"caps=0x{(uint)provider.Capabilities:X} " +
                $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)}");
'@
if((Count-Ordinal -Text $init -Needle $oldFail)-ne 1){
    throw '[V74.0.67.2.10.2] Provider-init-failure anchor mismatch.'
}
$init=$init.Replace($oldFail,$newFail)

$b=$b.Substring(0,$initStart)+$init+$b.Substring($initEnd)

[IO.File]::WriteAllText(
    $bridgePath,
    (Restore-Newlines $b),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.10.2] LAZY LAST-ERROR + PROVIDER INIT RETRY PATCH APPLIED.'
