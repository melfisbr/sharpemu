param(
    [string]$RepoRoot='',
    [string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
$script:PackageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$repo = Resolve-SharpEmuRepo $RepoRoot
Assert-PatchedStructure $repo
if (-not (Test-Path -LiteralPath $EbootPath)) { throw "$script:Tag Eboot nao encontrado: $EbootPath" }
$eboot = (Resolve-Path -LiteralPath $EbootPath).Path
$patches = Join-Path $repo 'Patches'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runtimeLog = Join-Path $patches ("SharpEmu_V74_0_75_PROCESSING_FLOW_RUNTIME_{0}.log" -f $stamp)
$report = Join-Path $patches ("SharpEmu_V74_0_75_PROCESSING_FLOW_DIAGNOSTIC_{0}.log" -f $stamp)
$exeCandidates = @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\SharpEmu.exe'),
    (Join-Path $repo 'src\SharpEmu.CLI\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $repo 'src\SharpEmu.CLI\bin\Debug\net10.0\SharpEmu.exe')
)
$exe = $null
foreach ($candidate in $exeCandidates) { if (Test-Path -LiteralPath $candidate) { $exe = $candidate; break } }
if ($null -eq $exe) {
    $found = Get-ChildItem -LiteralPath (Join-Path $repo 'artifacts\bin\Debug') -Filter 'SharpEmu.exe' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $found) { $exe = $found.FullName }
}
if ($null -eq $exe) { throw "$script:Tag SharpEmu.exe Debug nao encontrado apos o build." }

$oldAlias = $env:SHARPEMU_PRE_SNAPSHOT_SAMPLER_ALIAS
$oldDrain = $env:SHARPEMU_DEDICATED_WAIT_DRAIN
$oldGate = $env:SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN
$oldDirect = $env:SHARPEMU_UPSTREAM003_DIRECT_DRAIN
$env:SHARPEMU_PRE_SNAPSHOT_SAMPLER_ALIAS = '1'
$env:SHARPEMU_DEDICATED_WAIT_DRAIN = '1'
$env:SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN = '1'
$env:SHARPEMU_UPSTREAM003_DIRECT_DRAIN = '1'
Write-Host "$script:Tag TEST eboot=$eboot"
Write-Host "$script:Tag TEST executable=$exe"
Write-Host "$script:Tag TEST runtime_log=$runtimeLog"
Write-Host "$script:Tag pre_snapshot_alias=1 dedicated_drain=1 gate_owner_drain=1 direct_drain=1"
$runExit = 0
try {
    Push-Location (Split-Path -Parent $exe)
    try {
        & $exe ("--log-file={0}" -f $runtimeLog) $eboot
        $runExit = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    foreach ($entry in @(
        @{Name='SHARPEMU_PRE_SNAPSHOT_SAMPLER_ALIAS'; Value=$oldAlias},
        @{Name='SHARPEMU_DEDICATED_WAIT_DRAIN'; Value=$oldDrain},
        @{Name='SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN'; Value=$oldGate},
        @{Name='SHARPEMU_UPSTREAM003_DIRECT_DRAIN'; Value=$oldDirect})) {
        if ($null -eq $entry.Value) { Remove-Item ("Env:" + $entry.Name) -ErrorAction SilentlyContinue }
        else { Set-Item ("Env:" + $entry.Name) -Value $entry.Value }
    }
}

function Get-MetricStats($Lines, [string]$Pattern) {
    $values = @()
    foreach ($lineMatch in $Lines) {
        if ($lineMatch.Line -match $Pattern) {
            $raw = $matches[1].Replace(',', '.')
            try {
                $values += [double]::Parse(
                    $raw,
                    [System.Globalization.CultureInfo]::InvariantCulture)
            } catch {
            }
        }
    }
    if ($values.Count -eq 0) {
        return [pscustomobject]@{ Count=0; Average=0.0; Maximum=0.0 }
    }
    $sum = 0.0
    $max = [double]::MinValue
    foreach ($value in $values) {
        $sum += $value
        if ($value -gt $max) { $max = $value }
    }
    return [pscustomobject]@{
        Count = $values.Count
        Average = $sum / $values.Count
        Maximum = $max
    }
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("$script:Tag process_exit=$runExit")
$summary.Add("$script:Tag runtime_log=$runtimeLog")
if (Test-Path -LiteralPath $runtimeLog) {
    $pre75 = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[V74.0.75][PRE_SNAPSHOT_SAMPLER_ALIAS]')
    $pre33 = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[V74.0.56.33.2][PRE_SNAPSHOT_SAMPLER_ALIAS]')
    $wake = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[V74.0.75][PRODUCER_WAKE_DRAIN]')
    $post = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[V74.0.73][SAMPLER_IMAGE_ALIAS]')
    $draw = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[DRAW_RESOURCE_PHASES]')
    $compute = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[COMPUTE_RESOURCE_PHASES]')
    $slowWait = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[SLOW_WAIT_PRODUCER]')
    $gate = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[DEDICATED_WAIT_DRAIN]')
    $back = @(Select-String -LiteralPath $runtimeLog -SimpleMatch -Pattern '[BACKPRESSURE_WAIT]')
    $sourceZero = @($post | Where-Object { $_.Line -match 'source_kb=0(?:\s|$)' })
    $summary.Add("$script:Tag pre_snapshot_alias_v75=$($pre75.Count)")
    $summary.Add("$script:Tag pre_snapshot_alias_v33_2=$($pre33.Count)")
    $summary.Add("$script:Tag producer_wake_drain=$($wake.Count)")
    $summary.Add("$script:Tag sampler_alias_source_kb_zero=$($sourceZero.Count)")
    $summary.Add("$script:Tag draw_resource_phase_traces=$($draw.Count)")
    $summary.Add("$script:Tag compute_resource_phase_traces=$($compute.Count)")
    $summary.Add("$script:Tag slow_wait_producer_traces=$($slowWait.Count)")
    $summary.Add("$script:Tag dedicated_wait_drain_traces=$($gate.Count)")
    $summary.Add("$script:Tag backpressure_wait_traces=$($back.Count)")
    $drawTextureStats = Get-MetricStats $draw 'texture_ms=([0-9]+(?:[\.,][0-9]+)?)'
    $computeTextureStats = Get-MetricStats $compute 'texture_ms=([0-9]+(?:[\.,][0-9]+)?)'
    $slowWaitStats = Get-MetricStats $slowWait 'waited_ms=([0-9]+(?:[\.,][0-9]+)?)'
    $gateWaitStats = Get-MetricStats $gate 'gate_wait_ms=([0-9]+(?:[\.,][0-9]+)?)'
    $backWaitStats = Get-MetricStats $back 'ms=([0-9]+(?:[\.,][0-9]+)?)'
    $summary.Add(("$script:Tag draw_texture_ms_avg={0:F3} max={1:F3}" -f $drawTextureStats.Average, $drawTextureStats.Maximum))
    $summary.Add(("$script:Tag compute_texture_ms_avg={0:F3} max={1:F3}" -f $computeTextureStats.Average, $computeTextureStats.Maximum))
    $summary.Add(("$script:Tag slow_wait_ms_avg={0:F3} max={1:F3}" -f $slowWaitStats.Average, $slowWaitStats.Maximum))
    $summary.Add(("$script:Tag gate_wait_ms_avg={0:F3} max={1:F3}" -f $gateWaitStats.Average, $gateWaitStats.Maximum))
    $summary.Add(("$script:Tag backpressure_ms_avg={0:F3} max={1:F3}" -f $backWaitStats.Average, $backWaitStats.Maximum))
    if ($draw.Count -gt 0) { $summary.Add("$script:Tag last_draw=$($draw[-1].Line)") }
    if ($compute.Count -gt 0) { $summary.Add("$script:Tag last_compute=$($compute[-1].Line)") }
    if ($slowWait.Count -gt 0) { $summary.Add("$script:Tag last_slow_wait=$($slowWait[-1].Line)") }
    if ($gate.Count -gt 0) { $summary.Add("$script:Tag last_gate_wait=$($gate[-1].Line)") }
    if ($back.Count -gt 0) { $summary.Add("$script:Tag last_backpressure=$($back[-1].Line)") }
}
$summary | Set-Content -LiteralPath $report -Encoding UTF8
$summary | ForEach-Object { Write-Host $_ }
$resultZip = Join-Path $patches ("SharpEmu_V74_0_75_PROCESSING_FLOW_RESULT_{0}.zip" -f $stamp)
$stage = Join-Path $env:TEMP ("SharpEmu_V74_0_75_result_{0}" -f $stamp)
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath $report -Destination $stage
if (Test-Path -LiteralPath $runtimeLog) { Copy-Item -LiteralPath $runtimeLog -Destination $stage }
@(
    "$(Get-Sha256 (Join-Path $repo $script:PresenterRel)) *$script:PresenterRel",
    "$(Get-Sha256 (Join-Path $repo $script:AgcRel)) *$script:AgcRel"
) | Set-Content -LiteralPath (Join-Path $stage 'APPLIED_SHA256.txt') -Encoding ASCII
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $resultZip -Force
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "$script:Tag DIAGNOSTIC PASSED."
Write-Host "$script:Tag report=$report"
Write-Host "$script:Tag result_zip=$resultZip"
