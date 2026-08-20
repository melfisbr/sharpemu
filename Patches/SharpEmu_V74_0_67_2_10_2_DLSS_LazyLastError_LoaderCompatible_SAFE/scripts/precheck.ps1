. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach($path in @($bridgePath,$presenterPath,$exceptionsPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$already=$b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')

$checks=[ordered]@{
    v6729_source_identity=
        $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v6728_strict_extension=
        $b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    v6725_depth=
        $b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion=
        $b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    v671_loader_diagnostics=
        $b.Contains('[V74.0.67.1][UPSCALER][LOAD]') -or
        $b.Contains('V74.0.67.1 provider bootstrap/load diagnostics')
    parameterized_init=
        $b.Contains('private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)')
    native_upscaler_class=
        $b.Contains('private sealed class NativeVulkanUpscaler : IDisposable')
    provider_loader=
        $b.Contains('public static NativeVulkanUpscaler? TryLoad()')
    init_attempt_gate=
        $b.Contains('private bool _upscalerInitAttempted;')
    precomposite=
        $b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    runtime_counters=
        $b.Contains('_upscalerRuntimeDlssDispatches')
    invalid_direction_guard=
        $b.Contains('invalid_upscale_direction')
    instance_extension_hook=
        $p.Contains('AppendUpscalerInstanceExtensions(')
    device_extension_hook=
        $p.Contains('AppendUpscalerDeviceExtensions(')
    v73_hotpath=
        $p.Contains('[V74.0.73][SAMPLER_IMAGE_ALIAS]') -or
        ($p.Contains('sampler') -and $p.Contains('alias'))
    bpe_recovery_preserved_or_prior=
        $e.Contains('V74.0.67.2.4.1 BPE low-sentinel list recovery') -or
        $e.Contains('TryRecoverDemonBadChildFlagFault(')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.10.2] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host "[V74.0.67.2.10.2] already_applied=$($already.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.10.2] root_cause=v2101-loader-anchor-conflicted-with-v671'
Write-Host '[V74.0.67.2.10.2] loader_strategy=preserve-v671-loader-and-resolve-last-error-lazily'
Write-Host '[V74.0.67.2.10.2] provider_rebuild_required=false-when-v210-cache-valid'
Write-Host '[V74.0.67.2.10.2] same_dimension_retry_loop=false'
Write-Host '[V74.0.67.2.10.2] hardcoded_guest_resource_address=false'

if(!$already){
    $fieldAnchor='        private uint _upscalerInitHeight;'
    $delegateAnchor=@'
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ShutdownDelegate();
'@
    $classFieldsAnchor=@'
            private readonly CapabilitiesDelegate _capabilities;
            private readonly ShutdownDelegate _shutdown;
            private bool _initialized;
'@
    $capabilitiesAnchor=@'
            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();
'@
    $initializeAnchor=@'
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

    $fieldCount=Count-Ordinal -Text $b -Needle $fieldAnchor
    $delegateCount=Count-Ordinal -Text $b -Needle $delegateAnchor
    $classFieldsCount=Count-Ordinal -Text $b -Needle $classFieldsAnchor
    $capabilitiesCount=Count-Ordinal -Text $b -Needle $capabilitiesAnchor
    $initializeCount=Count-Ordinal -Text $b -Needle $initializeAnchor

    $initSignature=
        '        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)'
    $ensureSignature=
        '        private bool TryEnsureUpscalerOutput('
    $initStart=$b.IndexOf($initSignature,[StringComparison]::Ordinal)
    $initEnd=if($initStart-ge 0){
        $b.IndexOf($ensureSignature,$initStart,[StringComparison]::Ordinal)
    }else{-1}
    $initRegionValid=$initStart-ge 0 -and $initEnd-gt $initStart

    $headAnchor=@'
        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;
            if (_upscalerInitAttempted &&
'@
    $extensionAnchor=@'
            if (_upscalerRequiredExtensionMissing)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] required Vulkan extension negotiation failed; using normal Vulkan presentation.");
                return false;
            }
'@
    $providerNullAnchor=@'
            if (provider is null)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER] provider DLL not present; Vulkan presenter fallback remains active.");
                return false;
            }
'@
    $providerInitAnchor=@'
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

    $headCount=0;$extensionCount=0;$providerNullCount=0;$providerInitCount=0
    if($initRegionValid){
        $region=$b.Substring($initStart,$initEnd-$initStart)
        $headCount=Count-Ordinal -Text $region -Needle $headAnchor
        $extensionCount=Count-Ordinal -Text $region -Needle $extensionAnchor
        $providerNullCount=Count-Ordinal -Text $region -Needle $providerNullAnchor
        $providerInitCount=Count-Ordinal -Text $region -Needle $providerInitAnchor
    }

    Write-Host "[V74.0.67.2.10.2] anchor_init_height=$fieldCount"
    Write-Host "[V74.0.67.2.10.2] anchor_shutdown_delegate=$delegateCount"
    Write-Host "[V74.0.67.2.10.2] anchor_native_class_fields=$classFieldsCount"
    Write-Host "[V74.0.67.2.10.2] anchor_capabilities_property=$capabilitiesCount"
    Write-Host "[V74.0.67.2.10.2] anchor_native_initialize=$initializeCount"
    Write-Host "[V74.0.67.2.10.2] anchor_init_region_valid=$($initRegionValid.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.10.2] anchor_init_head=$headCount"
    Write-Host "[V74.0.67.2.10.2] anchor_extension_failure=$extensionCount"
    Write-Host "[V74.0.67.2.10.2] anchor_provider_null=$providerNullCount"
    Write-Host "[V74.0.67.2.10.2] anchor_provider_initialize_failure=$providerInitCount"
    Write-Host '[V74.0.67.2.10.2] provider_loader_body_anchor_required=false'

    if($fieldCount-ne 1 -or
       $delegateCount-ne 1 -or
       $classFieldsCount-ne 1 -or
       $capabilitiesCount-ne 1 -or
       $initializeCount-ne 1 -or
       !$initRegionValid -or
       $headCount-ne 1 -or
       $extensionCount-ne 1 -or
       $providerNullCount-ne 1 -or
       $providerInitCount-ne 1){
        $failed=$true
    }
}

if($failed){
    throw '[V74.0.67.2.10.2] PRECHECK FAILED.'
}
Write-Host '[V74.0.67.2.10.2] PRECHECK PASSED.'
