. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

if($b.Contains('V74.0.67.2.10 provider init retry + last-error telemetry')) {
    Write-Host '[V74.0.67.2.10.1] Source already patched.'
    return
}

function Replace-One {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $count=Count-Ordinal -Text $Text -Needle $Old
    if($count -ne 1){throw "[V74.0.67.2.10.1] Anchor '$Label' count=$count expected=1"}
    return $Text.Replace($Old,$New)
}

# 1) Presenter failure state.
#
# V74.0.67.2.10.1 anchor fix:
# V74.0.67 runtime telemetry inserted proof counters immediately after
# _upscalerInitHeight. Do not require MaxNativeUpscalerExtensions to be
# adjacent to this field.
$fieldAnchor='        private uint _upscalerInitHeight;'
$fieldInsert=@'

        // V74.0.67.2.10 provider init retry + last-error telemetry
        // V74.0.67.2.10.1 field-anchor fix
        private uint _upscalerInitFailedWidth;
        private uint _upscalerInitFailedHeight;
        private string _upscalerInitFailureReason = string.Empty;
'@
$b=Replace-One $b $fieldAnchor ($fieldAnchor+$fieldInsert) 'provider init failure field insertion point'

# 2) Optional native last-error ABI. Backward compatible with older providers.
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
            private readonly GetLastErrorDelegate? _getLastError;
            private bool _initialized;

            public int LastInitializeResult { get; private set; }
'@
$b=Replace-One $b $oldClassFields $newClassFields 'native class fields'

$oldCtor=@'
                DispatchDelegate dispatch,
                CapabilitiesDelegate capabilities,
                ShutdownDelegate shutdown)
            {
                _library = library;
                _instanceExtensions = instanceExtensions;
                _deviceExtensions = deviceExtensions;
                _initialize = initialize;
                _dispatch = dispatch;
                _capabilities = capabilities;
                _shutdown = shutdown;
            }

            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();
'@
$newCtor=@'
                DispatchDelegate dispatch,
                CapabilitiesDelegate capabilities,
                ShutdownDelegate shutdown,
                GetLastErrorDelegate? getLastError)
            {
                _library = library;
                _instanceExtensions = instanceExtensions;
                _deviceExtensions = deviceExtensions;
                _initialize = initialize;
                _dispatch = dispatch;
                _capabilities = capabilities;
                _shutdown = shutdown;
                _getLastError = getLastError;
            }

            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();

            public string LastError
            {
                get
                {
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
'@
$b=Replace-One $b $oldCtor $newCtor 'constructor + LastError property'

$oldLoad=@'
                foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!File.Exists(candidate) || !NativeLibrary.TryLoad(candidate, out var library))
                    {
                        continue;
                    }

                    try
                    {
                        if (!TryGet(library, "sharpemu_vk_upscaler_initialize", out InitDelegate? initialize) ||
                            !TryGet(library, "sharpemu_vk_upscaler_dispatch", out DispatchDelegate? dispatch) ||
                            !TryGet(library, "sharpemu_vk_upscaler_get_capabilities", out CapabilitiesDelegate? capabilities) ||
                            !TryGet(library, "sharpemu_vk_upscaler_shutdown", out ShutdownDelegate? shutdown))
                        {
                            NativeLibrary.Free(library);
                            continue;
                        }

                        _ = TryGet(library, "sharpemu_vk_upscaler_get_instance_extensions", out GetExtensionListDelegate? instanceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_device_extensions", out GetExtensionListDelegate? deviceExtensions);
                        Console.Error.WriteLine($"[V74.0.64][UPSCALER] native provider loaded: {candidate}");
                        return new NativeVulkanUpscaler(
                            library,
                            instanceExtensions,
                            deviceExtensions,
                            initialize!,
                            dispatch!,
                            capabilities!,
                            shutdown!);
                    }
'@
$newLoad=@'
                foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!File.Exists(candidate))
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.2.10][UPSCALER][PROVIDER_LOAD] state=missing path={candidate}");
                        continue;
                    }
                    if (!NativeLibrary.TryLoad(candidate, out var library))
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.2.10][UPSCALER][PROVIDER_LOAD] state=load_failed path={candidate}");
                        continue;
                    }

                    try
                    {
                        if (!TryGet(library, "sharpemu_vk_upscaler_initialize", out InitDelegate? initialize) ||
                            !TryGet(library, "sharpemu_vk_upscaler_dispatch", out DispatchDelegate? dispatch) ||
                            !TryGet(library, "sharpemu_vk_upscaler_get_capabilities", out CapabilitiesDelegate? capabilities) ||
                            !TryGet(library, "sharpemu_vk_upscaler_shutdown", out ShutdownDelegate? shutdown))
                        {
                            Console.Error.WriteLine(
                                $"[V74.0.67.2.10][UPSCALER][PROVIDER_LOAD] state=mandatory_export_missing path={candidate}");
                            NativeLibrary.Free(library);
                            continue;
                        }

                        _ = TryGet(library, "sharpemu_vk_upscaler_get_instance_extensions", out GetExtensionListDelegate? instanceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_device_extensions", out GetExtensionListDelegate? deviceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_last_error", out GetLastErrorDelegate? getLastError);
                        Console.Error.WriteLine(
                            $"[V74.0.67.2.10][UPSCALER][PROVIDER_LOAD] state=loaded path={candidate} last_error_export={(getLastError is null ? 0 : 1)}");
                        return new NativeVulkanUpscaler(
                            library,
                            instanceExtensions,
                            deviceExtensions,
                            initialize!,
                            dispatch!,
                            capabilities!,
                            shutdown!,
                            getLastError);
                    }
'@
$b=Replace-One $b $oldLoad $newLoad 'provider loader diagnostics'

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
$b=Replace-One $b $oldInitialize $newInitialize 'native init result capture'

# 3) Retry a failed initialization only when the requested OUTPUT SIZE changes.
# Same-size failure remains latched, preventing a per-frame retry loop.
$initSignature='        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)'
$initStart=$b.IndexOf($initSignature,[StringComparison]::Ordinal)
$initEnd=$b.IndexOf('        private bool TryEnsureUpscalerOutput(', $initStart,[StringComparison]::Ordinal)
if($initStart -lt 0 -or $initEnd -lt 0){throw '[V74.0.67.2.10.1] Cannot isolate TryInitializeUpscaler region.'}
$init=$b.Substring($initStart,$initEnd-$initStart)

$oldHead=@'
        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;
            if (_upscalerInitAttempted &&
'@
$newHead=@'
        private void RecordUpscalerInitFailure(uint outputWidth, uint outputHeight, string reason)
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
                    $"[V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=retry_size_change " +
                    $"previous={_upscalerInitFailedWidth}x{_upscalerInitFailedHeight} " +
                    $"requested={outputWidth}x{outputHeight} " +
                    $"previous_reason={_upscalerInitFailureReason}");
                _upscalerInitAttempted = false;
                _upscalerInitFailureReason = string.Empty;
                _upscalerOutputReset = true;
            }

            if (_upscalerInitAttempted &&
'@
if((Count-Ordinal -Text $init -Needle $oldHead)-ne 1){throw '[V74.0.67.2.10.1] Init header anchor mismatch.'}
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
                RecordUpscalerInitFailure(outputWidth, outputHeight, "required_vulkan_extension_negotiation_failed");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=failed result=managed " +
                    $"output={outputWidth}x{outputHeight} last_error=required_vulkan_extension_negotiation_failed");
                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldExt)-ne 1){throw '[V74.0.67.2.10.1] Extension-failure anchor mismatch.'}
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
                RecordUpscalerInitFailure(outputWidth, outputHeight, "provider_dll_not_loaded");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=failed result=managed " +
                    $"output={outputWidth}x{outputHeight} last_error=provider_dll_not_loaded");
                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldNull)-ne 1){throw '[V74.0.67.2.10.1] Provider-null anchor mismatch.'}
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
                    nativeError = "native_provider_returned_failure_without_error_text";
                }
                RecordUpscalerInitFailure(outputWidth, outputHeight, nativeError);
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result={provider.LastInitializeResult} " +
                    $"output={outputWidth}x{outputHeight} last_error={nativeError}");
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
                $"[V74.0.67.2.10][UPSCALER][PROVIDER_INIT] state=active result=0 " +
                $"output={outputWidth}x{outputHeight} caps=0x{(uint)provider.Capabilities:X}");
'@
if((Count-Ordinal -Text $init -Needle $oldFail)-ne 1){throw '[V74.0.67.2.10.1] Provider-init-failure anchor mismatch.'}
$init=$init.Replace($oldFail,$newFail)

$b=$b.Substring(0,$initStart)+$init+$b.Substring($initEnd)

[IO.File]::WriteAllText($bridgePath,(Restore-Newlines $b),[Text.UTF8Encoding]::new($false))
Write-Host '[V74.0.67.2.10.1] PROVIDER INIT RETRY + LAST-ERROR PATCH APPLIED.'
