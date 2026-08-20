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

$already =
    $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')

$oldV27Marker =
    $b.Contains('V74.0.67.2.7 stable temporal source disambiguation')

$oldDuplicateRanking = @'
                var largest = ordered
                    .Where(item =>
                        (ulong)item.Source.Width * item.Source.Height == bestArea)
                    .Select(item =>
'@

$checks = [ordered]@{
    v6727_source_disambiguation =
        $oldV27Marker
    v6725_depth =
        $b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion =
        $b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    v6728_strict_extension_negotiation =
        $b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    duplicate_ranking_anchor_or_applied =
        $already -or ((Count-Ordinal -Text $b -Needle $oldDuplicateRanking) -eq 1)
    depth_state_dictionary =
        $b.Contains('_upscalerDepthStableBySourceV7406725')
    motion_state_dictionary =
        $b.Contains('_upscalerGlobalMotionStateV7406726')
    source_binding_serial =
        $b.Contains('item.Candidate.Binding.Serial') -or
        $b.Contains('item.Binding.Serial')
    precomposite =
        $b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    runtime_counters =
        $b.Contains('_upscalerRuntimeDlssDispatches')
    invalid_direction_guard =
        $b.Contains('invalid_upscale_direction')
    v73_hotpath =
        $p.Contains('[V74.0.73][SAMPLER_IMAGE_ALIAS]') -or
        ($p.Contains('sampler') -and $p.Contains('alias'))
    bpe_recovery_preserved_or_prior =
        $e.Contains('V74.0.67.2.4.1 BPE low-sentinel list recovery') -or
        $e.Contains('TryRecoverDemonBadChildFlagFault(')
}

$failed = $false
foreach ($entry in $checks.GetEnumerator()) {
    Write-Host "[V74.0.67.2.9] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if (!$entry.Value) { $failed = $true }
}

Write-Host "[V74.0.67.2.9] already_applied=$($already.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.9] root_cause=duplicate-bindings-for-same-source-address'
Write-Host '[V74.0.67.2.9] identity_key=Source.Address'
Write-Host '[V74.0.67.2.9] representative_binding=newest-ContentGeneration-then-Binding.Serial'
Write-Host '[V74.0.67.2.9] source_ranking=distinct-source-only'
Write-Host '[V74.0.67.2.9] minimum_temporal_confidence=3'
Write-Host '[V74.0.67.2.9] hardcoded_guest_address=false'
Write-Host '[V74.0.67.2.9] native_provider_rebuild_required=false'

if ($failed) {
    throw '[V74.0.67.2.9] PRECHECK FAILED.'
}

Write-Host '[V74.0.67.2.9] PRECHECK PASSED.'
