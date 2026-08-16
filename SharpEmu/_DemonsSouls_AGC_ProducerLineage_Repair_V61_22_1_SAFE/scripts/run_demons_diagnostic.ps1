param(
    [string]$RepositoryRoot,
    [string]$EbootPath = "F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
if (-not (Test-Path -LiteralPath $EbootPath)) { throw "eboot.bin nao encontrado: $EbootPath" }

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
if ($null -eq $exe) { throw "SharpEmu.exe nao encontrado em artifacts. Execute RUN_APPLY_BUILD_V61_22_1.cmd primeiro." }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $root "SharpEmu_V61_22_1_DEMONS_PRODUCER_LINEAGE_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout = Join-Path $outDir "stdout.log"
$stderr = Join-Path $outDir "stderr.log"
$focus = Join-Path $outDir "FOCUS.txt"
$contextFile = Join-Path $outDir "WAIT_CONTEXT.txt"
$sourceEvidence = Join-Path $outDir "AGC_SOURCE_EVIDENCE.txt"
$summary = Join-Path $outDir "SUMMARY.txt"

$agc = Get-AgcTarget $root
$registry = Get-WaitRegistryTarget $root
$agcText = Normalize-Lf (Read-Utf8Text $agc)
$regText = Normalize-Lf (Read-Utf8Text $registry)

$evidence = New-Object System.Collections.Generic.List[string]
$evidence.Add("SharpEmu V61.22.1 static producer coverage evidence")
$evidence.Add("AgcExports_SHA256=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)")
$evidence.Add("GpuWaitRegistry_SHA256=$((Get-FileHash -LiteralPath $registry -Algorithm SHA256).Hash)")
$evidence.Add("WRITE_DATA_RecordProduced=$($agcText.Contains('GpuWaitRegistry.RecordProduced('))")
$writeSlice = Get-MethodSlice -Text $agcText -MethodName "ApplySubmittedWriteData" -MaxChars 12000
if ($null -ne $writeSlice) {
    $evidence.Add("WRITE_DATA_direct_record=$($writeSlice.Contains('GpuWaitRegistry.RecordProduced('))")
    $evidence.Add("WRITE_DATA_range_record=$($writeSlice.Contains('RecordProducedLabelsInRange('))")
}
$evidence.Add("RangeHelper_present=$($agcText.Contains('SnapshotWatchedLabelsInRange('))")
$evidence.Add("DMA_completion_action_present=$($agcText.Contains('producerCompletionAction'))")
$evidence.Add("RELEASE_MEM_producedValue_present=$($agcText.Contains('producedValue'))")
$evidence.Add("Registry_RecordProduced_present=$($regText.Contains('public static bool RecordProduced('))")
$evidence.Add("")
$evidence.Add("Relevant source lines:")
foreach ($spec in @(
    @{Path=$agc; Pattern='ApplySubmittedWriteData'},
    @{Path=$agc; Pattern='RecordProducedLabelsInRange'},
    @{Path=$agc; Pattern='producerCompletionAction'},
    @{Path=$agc; Pattern='producedValue'},
    @{Path=$registry; Pattern='RecordProduced('},
    @{Path=$registry; Pattern='SnapshotWatchedLabelsInRange'}
)) {
    $lines = Get-Content -LiteralPath $spec.Path
    $matches = Select-String -LiteralPath $spec.Path -Pattern $spec.Pattern -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 8
    foreach ($m in $matches) {
        $from = [Math]::Max(1, $m.LineNumber - 3)
        $to = [Math]::Min($lines.Count, $m.LineNumber + 8)
        $evidence.Add("--- $([System.IO.Path]::GetFileName($spec.Path)) pattern='$($spec.Pattern)' line=$($m.LineNumber) ---")
        for ($n = $from; $n -le $to; $n++) {
            $evidence.Add(("{0,6}: {1}" -f $n, $lines[$n - 1]))
        }
    }
}
$evidence | Set-Content -LiteralPath $sourceEvidence -Encoding UTF8

$oldAgc = $env:SHARPEMU_LOG_AGC
$oldAgcShader = $env:SHARPEMU_LOG_AGC_SHADER
$oldVkResources = $env:SHARPEMU_LOG_VK_RESOURCES
$env:SHARPEMU_LOG_AGC = "1"
$env:SHARPEMU_LOG_AGC_SHADER = "1"
$env:SHARPEMU_LOG_VK_RESOURCES = "1"

$exitCode = 0
Write-Host "[V61.22.1] Executable: $exe"
Write-Host "[V61.22.1] Game:       $EbootPath"
Write-Host "[V61.22.1] AGC + shader + Vulkan resource tracing enabled."
Write-Host "[V61.22.1] Close the SharpEmu window when the observation is complete."
try {
    # Do not use $LASTEXITCODE here.  Native GUI invocation does not guarantee
    # that PowerShell creates it under StrictMode. Start-Process gives us a
    # concrete Process object and a stable ExitCode after -Wait.
    $quotedEboot = '"' + $EbootPath.Replace('"', '\"') + '"'
    $process = Start-Process -FilePath $exe -ArgumentList @($quotedEboot) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -PassThru -Wait
    $exitCode = [int]$process.ExitCode
} finally {
    $env:SHARPEMU_LOG_AGC = $oldAgc
    $env:SHARPEMU_LOG_AGC_SHADER = $oldAgcShader
    $env:SHARPEMU_LOG_VK_RESOURCES = $oldVkResources
}

$patterns = @(
    "456CFF580",
    "456CFF4C0",
    "agc.wait_suspended",
    "agc.wait_stale",
    "agc.wait_producer_",
    "agc.deadlock_break",
    "agc.queue_resumed",
    "agc.dcb.wait_reg_mem",
    "agc.dcb.write_data",
    "agc.dcb.release_mem",
    "agc.dcb.dma",
    "agc.acb",
    "event_write",
    "vk.ordered_action_fence_wait",
    "vk.storage",
    "gpu_resident=",
    "dispatch_noop",
    "compute cs=",
    "deviceLost=",
    "Starting main loop",
    "bink2.direct_boot_completed",
    "audio_out2.port-zero-pcm",
    "ajm."
)

$all = New-Object System.Collections.Generic.List[string]
foreach ($path in @($stdout, $stderr)) {
    if (Test-Path -LiteralPath $path) {
        foreach ($match in Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue) {
            $all.Add(("{0}:{1}: {2}" -f (Split-Path $path -Leaf), $match.LineNumber, $match.Line))
        }
    }
}
$all | Set-Content -LiteralPath $focus -Encoding UTF8

$context = New-Object System.Collections.Generic.List[string]
foreach ($path in @($stdout, $stderr)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $lines = Get-Content -LiteralPath $path
    $matches = Select-String -LiteralPath $path -Pattern @("agc.wait_suspended", "456CFF580", "456CFF4C0") -SimpleMatch -ErrorAction SilentlyContinue
    $seen = @{}
    foreach ($m in $matches) {
        $from = [Math]::Max(1, $m.LineNumber - 45)
        $to = [Math]::Min($lines.Count, $m.LineNumber + 90)
        $key = "$from-$to"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $context.Add("===== $(Split-Path $path -Leaf) lines $from-$to around match line $($m.LineNumber) =====")
        for ($n = $from; $n -le $to; $n++) {
            $context.Add(("{0,7}: {1}" -f $n, $lines[$n - 1]))
        }
    }
}
$context | Set-Content -LiteralPath $contextFile -Encoding UTF8

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
    "SharpEmu V61.22.1 AGC producer-lineage diagnostic",
    "timestamp=$stamp",
    "exit_code=$exitCode",
    "main_loop=$(Count-Matches 'Starting main loop')",
    "bink_direct_boot_completed=$(Count-Matches 'bink2.direct_boot_completed')",
    "wait_suspended=$(Count-Matches 'agc.wait_suspended')",
    "wait_label_456CFF580=$(Count-Matches '456CFF580')",
    "wait_label_456CFF4C0=$(Count-Matches '456CFF4C0')",
    "wait_producer_scheduled=$(Count-Matches 'agc.wait_producer_scheduled')",
    "wait_producer_completed=$(Count-Matches 'agc.wait_producer_completed')",
    "deadlock_break=$(Count-Matches 'agc.deadlock_break')",
    "queue_resumed=$(Count-Matches 'agc.queue_resumed')",
    "dcb_write_data=$(Count-Matches 'agc.dcb.write_data')",
    "dcb_release_mem=$(Count-Matches 'agc.dcb.release_mem')",
    "dcb_dma=$(Count-Matches 'agc.dcb.dma')",
    "event_write=$(Count-Matches 'event_write')",
    "ordered_action_fence_wait=$(Count-Matches 'vk.ordered_action_fence_wait')",
    "gpu_resident_false=$(Count-Matches 'gpu_resident=False')",
    "dispatch_noop=$(Count-Matches 'agc.dispatch_noop')",
    "device_lost_true=$(Count-Matches 'deviceLost=True')",
    "audio_zero_pcm=$(Count-Matches 'audio_out2.port-zero-pcm')",
    "ajm_lines=$(Count-Matches 'ajm.')"
)
$summaryLines | Set-Content -LiteralPath $summary -Encoding UTF8

$zip = Join-Path $root "SharpEmu_V61_22_1_DEMONS_PRODUCER_LINEAGE_$stamp.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip -CompressionLevel Optimal

Write-Host "[V61.22.1] Diagnostic complete." -ForegroundColor Green
Write-Host "[V61.22.1] Result ZIP: $zip"
Write-Host "[V61.22.1] Send this ZIP in the next message."
