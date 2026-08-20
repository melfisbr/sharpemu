. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot
$patches = Get-PatchesRoot

$bridgePath = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

$b = Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p = Normalize-Lf ([IO.File]::ReadAllText($presenterPath))

$checks = [ordered]@{
    source_identity_marker =
        $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    group_by_source_address =
        $b.Contains('.GroupBy(static item => item.Source.Address)')
    representative_content_generation =
        $b.Contains('.OrderByDescending(static item =>') -and
        $b.Contains('item.Source.ContentGeneration')
    representative_binding_serial =
        $b.Contains('.ThenByDescending(static item => item.Binding.Serial)')
    distinct_source_array =
        $b.Contains('var distinctLargest = rawLargest')
    raw_candidate_telemetry =
        $b.Contains('raw_candidates={bestCount}')
    distinct_source_telemetry =
        $b.Contains('distinct_sources={largest.Length}')
    same_source_runner_invariant =
        $b.Contains('source identity de-dup invariant failed')
    v6727_preserved =
        $b.Contains('V74.0.67.2.7 stable temporal source disambiguation')
    v6725_depth_preserved =
        $b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion_preserved =
        $b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    v6728_strict_extension_preserved =
        $b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    precomposite_preserved =
        $b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    runtime_counters_preserved =
        $b.Contains('_upscalerRuntimeDlssDispatches')
    invalid_direction_guard_preserved =
        $b.Contains('invalid_upscale_direction')
    v73_hotpath_preserved =
        $p.Contains('[V74.0.73][SAMPLER_IMAGE_ALIAS]') -or
        ($p.Contains('sampler') -and $p.Contains('alias'))
}

$failed = $false
$resultLines = New-Object System.Collections.Generic.List[string]
foreach ($entry in $checks.GetEnumerator()) {
    $line =
        "[V74.0.67.2.9] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $resultLines.Add($line)
    if (!$entry.Value) { $failed = $true }
}

$releaseHost = Find-ReleaseHost -Repo $repo
if ($null -eq $releaseHost) {
    $failed = $true
}
else {
    $resultLines.Add("[V74.0.67.2.9] Host=$($releaseHost.FullName)")
}

$resultLines.Add('[V74.0.67.2.9] EXPECTED_RUNTIME=raw_candidates=5 distinct_sources=1 -> state=selected')
$resultLines.Add('[V74.0.67.2.9] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')

if ($failed) {
    throw '[V74.0.67.2.9] STRUCTURAL DIAGNOSTIC FAILED.'
}

Write-Host '[V74.0.67.2.9] DIAGNOSTIC PASSED.'
$resultLines.Add('[V74.0.67.2.9] DIAGNOSTIC PASSED.')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultTxt = Join-Path $patches "SharpEmu_V74_0_67_2_9_DLSS_SOURCE_DEDUP_RESULT_$stamp.txt"
$resultZip = Join-Path $patches "SharpEmu_V74_0_67_2_9_DLSS_SOURCE_DEDUP_RESULT_$stamp.zip"

[IO.File]::WriteAllLines(
    $resultTxt,
    $resultLines,
    [Text.UTF8Encoding]::new($false))

Compress-Archive `
    -LiteralPath $resultTxt `
    -DestinationPath $resultZip `
    -Force

Write-Host "[V74.0.67.2.9] ResultZip=$resultZip"
