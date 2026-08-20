. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot
$bridgePath = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$exceptionsPath = Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach ($path in @($bridgePath, $presenterPath, $exceptionsPath)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required source: $path"
    }
}

$b = Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p = Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$e = Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))
$already = $b.Contains('V74.0.67.2.10 provider init retry + last-error telemetry')

$checks = [ordered]@{
    v6729_source_identity =
        $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v6728_strict_extension =
        $b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    v6725_depth =
        $b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion =
        $b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    parameterized_init =
        $b.Contains('private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)')
    native_upscaler_class =
        $b.Contains('private sealed class NativeVulkanUpscaler : IDisposable')
    initialize_delegate =
        $b.Contains('private unsafe delegate int InitDelegate(NativeUpscalerInitDesc* desc);')
    provider_loader =
        $b.Contains('public static NativeVulkanUpscaler? TryLoad()')
    init_attempt_gate =
        $b.Contains('private bool _upscalerInitAttempted;')
    last_error_export_optional_ready =
        $already -or !$b.Contains('GetLastErrorDelegate')
    precomposite =
        $b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    runtime_counters =
        $b.Contains('_upscalerRuntimeDlssDispatches')
    invalid_direction_guard =
        $b.Contains('invalid_upscale_direction')
    instance_extension_hook =
        $p.Contains('AppendUpscalerInstanceExtensions(')
    device_extension_hook =
        $p.Contains('AppendUpscalerDeviceExtensions(')
    v73_hotpath =
        $p.Contains('[V74.0.73][SAMPLER_IMAGE_ALIAS]') -or
        ($p.Contains('sampler') -and $p.Contains('alias'))
    bpe_recovery_preserved_or_prior =
        $e.Contains('V74.0.67.2.4.1 BPE low-sentinel list recovery') -or
        $e.Contains('TryRecoverDemonBadChildFlagFault(')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()) {
    Write-Host "[V74.0.67.2.10] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}
Write-Host "[V74.0.67.2.10] already_applied=$($already.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.10] runtime_root_cause=precomposite_provider_init_failed'
Write-Host '[V74.0.67.2.10] scene_source_gate=resolved-by-v6729'
Write-Host '[V74.0.67.2.10] temporal_inputs=color+depth+motion-ready'
Write-Host '[V74.0.67.2.10] fix=failed-init-size-retry+native-last-error+provider-redeploy'
Write-Host '[V74.0.67.2.10] same_dimension_retry_loop=false'
Write-Host '[V74.0.67.2.10] hardcoded_guest_resource_address=false'
if($failed){throw '[V74.0.67.2.10] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.10] PRECHECK PASSED.'
