param(
    [string]$RepositoryRoot,
    [string]$EbootPath = "F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
if (-not (Test-Path -LiteralPath $EbootPath)) {
    throw "eboot.bin nao encontrado: $EbootPath"
}

$exeCandidates = @(
    (Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"),
    (Join-Path $root "artifacts\bin\Debug\net10.0\SharpEmu.exe")
)
$exe = $null
foreach ($candidate in $exeCandidates) {
    if (Test-Path -LiteralPath $candidate) { $exe = $candidate; break }
}
if ($null -eq $exe) {
    $found = Get-ChildItem -Path (Join-Path $root "artifacts") -Filter "SharpEmu.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $found) { $exe = $found.FullName }
}
if ($null -eq $exe) { throw "SharpEmu.exe nao encontrado em artifacts. Execute RUN_APPLY_BUILD_V61_22_0.cmd primeiro." }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $root "SharpEmu_V61_22_0_DEMONS_RESULT_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout = Join-Path $outDir "stdout.log"
$stderr = Join-Path $outDir "stderr.log"
$focus = Join-Path $outDir "FOCUS.txt"
$summary = Join-Path $outDir "SUMMARY.txt"

$oldAgc = $env:SHARPEMU_LOG_AGC
$env:SHARPEMU_LOG_AGC = "1"

Write-Host "[V61.22.0] Executable: $exe"
Write-Host "[V61.22.0] Game:       $EbootPath"
Write-Host "[V61.22.0] Close the SharpEmu window when the observation is complete."
try {
    & $exe $EbootPath 1> $stdout 2> $stderr
    $exitCode = $LASTEXITCODE
} finally {
    $env:SHARPEMU_LOG_AGC = $oldAgc
}

$patterns = @(
    "agc.write_data_wait_latched",
    "agc.wait_suspended",
    "agc.wait_stale",
    "agc.wait_producer_",
    "agc.deadlock_break",
    "agc.queue_resumed",
    "agc.rt_sampled",
    "agc.dispatch_noop",
    "vk.ordered_action_fence_wait",
    "bink2.direct_boot_completed",
    "Starting main loop",
    "deviceLost=",
    "audio_out2.port-zero-pcm",
    "ajm."
)

$all = @()
foreach ($path in @($stdout, $stderr)) {
    if (Test-Path -LiteralPath $path) {
        foreach ($match in Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue) {
            $all += ("{0}:{1}: {2}" -f (Split-Path $path -Leaf), $match.LineNumber, $match.Line)
        }
    }
}
$all | Set-Content -LiteralPath $focus -Encoding UTF8

function Count-Matches([string]$Pattern) {
    $count = 0
    foreach ($path in @($stdout, $stderr)) {
        if (Test-Path -LiteralPath $path) {
            $m = Select-String -LiteralPath $path -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue
            if ($null -ne $m) { $count += @($m).Count }
        }
    }
    return $count
}

$summaryLines = @(
    "SharpEmu V61.22.0 WRITE_DATA active-wait latch diagnostic",
    "timestamp=$stamp",
    "exit_code=$exitCode",
    "write_data_wait_latched=$(Count-Matches 'agc.write_data_wait_latched')",
    "wait_suspended=$(Count-Matches 'agc.wait_suspended')",
    "wait_stale=$(Count-Matches 'agc.wait_stale')",
    "deadlock_break=$(Count-Matches 'agc.deadlock_break')",
    "queue_resumed=$(Count-Matches 'agc.queue_resumed')",
    "wait_producer_scheduled=$(Count-Matches 'agc.wait_producer_scheduled')",
    "wait_producer_completed=$(Count-Matches 'agc.wait_producer_completed')",
    "rt_sampled=$(Count-Matches 'agc.rt_sampled')",
    "dispatch_noop=$(Count-Matches 'agc.dispatch_noop')",
    "ordered_action_fence_wait=$(Count-Matches 'vk.ordered_action_fence_wait')",
    "bink_direct_boot_completed=$(Count-Matches 'bink2.direct_boot_completed')",
    "device_lost_true=$(Count-Matches 'deviceLost=True')",
    "audio_zero_pcm=$(Count-Matches 'audio_out2.port-zero-pcm')",
    "ajm_lines=$(Count-Matches 'ajm.')"
)
$summaryLines | Set-Content -LiteralPath $summary -Encoding UTF8

$zip = Join-Path $root "SharpEmu_V61_22_0_DEMONS_RESULT_$stamp.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip -CompressionLevel Optimal

Write-Host "[V61.22.0] Diagnostic complete." -ForegroundColor Green
Write-Host "[V61.22.0] Result ZIP: $zip"
Write-Host "[V61.22.0] Send this ZIP in the next message."
