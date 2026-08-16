param(
    [string]$RepositoryRoot,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$agcText = [IO.File]::ReadAllText($agc)
if (-not (Test-ContainsOrdinal -Text $agcText -Pattern 'SHARPEMU_TRACE_LABEL_PROVENANCE') -or
    -not (Test-ContainsOrdinal -Text $agcText -Pattern '[V73.4][LABEL]')) {
    throw '[V73.4] Diagnostic refused: provenance instrumentation is not installed.'
}

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.4] EBOOT missing: {0}' -f $Eboot)
}

$exe = $null
foreach ($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $exe = $candidate
        break
    }
}
if ($null -eq $exe) {
    throw '[V73.4] SharpEmu.exe not found. Run RUN_APPLY_BUILD_V73_4.cmd first.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_4_LABEL_PROVENANCE_RESULT_{0}' -f $stamp)
$sourceDir = Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $out | Out-Null
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'

$oldProv = $env:SHARPEMU_TRACE_LABEL_PROVENANCE
$oldAgc = $env:SHARPEMU_LOG_AGC
$oldAgcShader = $env:SHARPEMU_LOG_AGC_SHADER
$oldVk = $env:SHARPEMU_LOG_VK_RESOURCES
$oldDraws = $env:SHARPEMU_TRACE_DRAWS
$oldFrames = $env:SHARPEMU_TRACE_FRAME_PACKETS
$oldGeometry = $env:SHARPEMU_TRACE_GEOMETRY_DRAWS

try {
    $env:SHARPEMU_TRACE_LABEL_PROVENANCE = '1'
    Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_TRACE_DRAWS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_TRACE_FRAME_PACKETS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_TRACE_GEOMETRY_DRAWS -ErrorAction SilentlyContinue

    Write-Host '[V73.4] Starting bounded label provenance diagnostic.'
    Write-Host '[V73.4] Let Demons Souls reach the usual post-video stall, then close the emulator.'
    Write-Host '[V73.4] Full AGC/Vulkan tracing remains disabled.'

    $process = Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $process.WaitForExit()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
}
finally {
    if ($null -eq $oldProv) { Remove-Item Env:SHARPEMU_TRACE_LABEL_PROVENANCE -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_LABEL_PROVENANCE = $oldProv }
    if ($null -eq $oldAgc) { Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC = $oldAgc }
    if ($null -eq $oldAgcShader) { Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC_SHADER = $oldAgcShader }
    if ($null -eq $oldVk) { Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_VK_RESOURCES = $oldVk }
    if ($null -eq $oldDraws) { Remove-Item Env:SHARPEMU_TRACE_DRAWS -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_DRAWS = $oldDraws }
    if ($null -eq $oldFrames) { Remove-Item Env:SHARPEMU_TRACE_FRAME_PACKETS -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_FRAME_PACKETS = $oldFrames }
    if ($null -eq $oldGeometry) { Remove-Item Env:SHARPEMU_TRACE_GEOMETRY_DRAWS -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_GEOMETRY_DRAWS = $oldGeometry }
}

$stdoutLines = @()
$stderrLines = @()
if (Test-Path -LiteralPath $stdout -PathType Leaf) {
    $stdoutLines = @([IO.File]::ReadAllLines($stdout))
}
if (Test-Path -LiteralPath $stderr -PathType Leaf) {
    $stderrLines = @([IO.File]::ReadAllLines($stderr))
}

$prov = @($stderrLines | Where-Object { $_.IndexOf('[V73.4][LABEL]', [StringComparison]::Ordinal) -ge 0 })
$targets = @($prov | Where-Object { $_.IndexOf('wait_target ', [StringComparison]::Ordinal) -ge 0 })
$computeOverlap = @($prov | Where-Object { $_.IndexOf('compute_overlap ', [StringComparison]::Ordinal) -ge 0 })
$computeScan = @($prov | Where-Object { $_.IndexOf('compute_scan ', [StringComparison]::Ordinal) -ge 0 })
$rangeOverlap = @($prov | Where-Object { $_.IndexOf('range_overlap ', [StringComparison]::Ordinal) -ge 0 })
$pm4Overlap = @($rangeOverlap | Where-Object { $_.IndexOf('source=pm4_producer_registered', [StringComparison]::Ordinal) -ge 0 })
$writebackOverlap = @($rangeOverlap | Where-Object { $_.IndexOf('source=gpu_writeback', [StringComparison]::Ordinal) -ge 0 })
$eventAddressed = @($prov | Where-Object { $_.IndexOf('event_write_addressed ', [StringComparison]::Ordinal) -ge 0 })

$waitSuspended = @($stderrLines | Where-Object { $_.IndexOf('agc.wait_suspended', [StringComparison]::OrdinalIgnoreCase) -ge 0 })
$queueResumed = @($stderrLines | Where-Object { $_.IndexOf('agc.queue_resumed', [StringComparison]::OrdinalIgnoreCase) -ge 0 })
$orderedFence = @($stderrLines | Where-Object { $_.IndexOf('vk.ordered_action_fence_wait', [StringComparison]::OrdinalIgnoreCase) -ge 0 })
$backpressure = @($stderrLines | Where-Object { $_.IndexOf('vk.guest_queue_backpressure', [StringComparison]::OrdinalIgnoreCase) -ge 0 })
$metadata = @(
    $stdoutLines |
        Where-Object { $_.IndexOf('SCE import metadata:', [StringComparison]::OrdinalIgnoreCase) -ge 0 }
)

Write-Utf8Lines -Path (Join-Path $out 'LABEL_PROVENANCE_ALL.txt') -Lines $prov
Write-Utf8Lines -Path (Join-Path $out 'WAIT_TARGETS.txt') -Lines $targets
Write-Utf8Lines -Path (Join-Path $out 'COMPUTE_OVERLAPS.txt') -Lines $computeOverlap
Write-Utf8Lines -Path (Join-Path $out 'COMPUTE_SCANS.txt') -Lines $computeScan
Write-Utf8Lines -Path (Join-Path $out 'RANGE_OVERLAPS.txt') -Lines $rangeOverlap
Write-Utf8Lines -Path (Join-Path $out 'PM4_PRODUCER_OVERLAPS.txt') -Lines $pm4Overlap
Write-Utf8Lines -Path (Join-Path $out 'GPU_WRITEBACK_OVERLAPS.txt') -Lines $writebackOverlap
Write-Utf8Lines -Path (Join-Path $out 'ADDRESSED_EVENT_WRITE.txt') -Lines $eventAddressed
Write-Utf8Lines -Path (Join-Path $out 'WAIT_SUSPENDED.txt') -Lines $waitSuspended
Write-Utf8Lines -Path (Join-Path $out 'QUEUE_RESUMED.txt') -Lines $queueResumed

# Classify the evidence without changing emulator semantics.
$classification = 'producer-path-not-yet-observed'
if ($computeOverlap.Count -gt 0) {
    $disabledWriteback = @(
        $computeOverlap |
            Where-Object { $_.IndexOf('writeback=0', [StringComparison]::Ordinal) -ge 0 }
    )
    $readonlyOverlap = @(
        $computeOverlap |
            Where-Object { $_.IndexOf('writable=0', [StringComparison]::Ordinal) -ge 0 }
    )

    if ($disabledWriteback.Count -gt 0) {
        $classification = 'compute-overlap-writeback-disabled'
    }
    elseif ($readonlyOverlap.Count -gt 0) {
        $classification = 'compute-overlap-not-classified-writable'
    }
    elseif ($writebackOverlap.Count -gt 0) {
        $classification = 'compute-overlap-and-writeback-observed-check-value-wake'
    }
    else {
        $classification = 'compute-overlap-writable-but-no-writeback-overlap'
    }
}
elseif ($pm4Overlap.Count -gt 0) {
    $classification = 'pm4-producer-overlap-observed'
}
elseif ($eventAddressed.Count -gt 0) {
    $classification = 'addressed-event-write-observed'
}
elseif ($computeScan.Count -gt 0) {
    $classification = 'compute-ran-without-label-range-overlap'
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.4')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('provenance_lines={0}' -f $prov.Count))
$summary.Add(('wait_targets={0}' -f $targets.Count))
$summary.Add(('compute_overlaps={0}' -f $computeOverlap.Count))
$summary.Add(('compute_scan_samples={0}' -f $computeScan.Count))
$summary.Add(('range_overlaps={0}' -f $rangeOverlap.Count))
$summary.Add(('pm4_producer_overlaps={0}' -f $pm4Overlap.Count))
$summary.Add(('gpu_writeback_overlaps={0}' -f $writebackOverlap.Count))
$summary.Add(('addressed_event_writes={0}' -f $eventAddressed.Count))
$summary.Add(('wait_suspended_lines={0}' -f $waitSuspended.Count))
$summary.Add(('queue_resumed_lines={0}' -f $queueResumed.Count))
$summary.Add(('ordered_fence_sample_lines={0}' -f $orderedFence.Count))
$summary.Add(('backpressure_sample_lines={0}' -f $backpressure.Count))
$summary.Add(('runtime_unresolved_lines={0}' -f @($stderrLines | Where-Object { $_.IndexOf('unresolved:', [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count))
$summary.Add(('device_lost_true_lines={0}' -f @($stderrLines | Where-Object { $_.IndexOf('deviceLost=True', [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count))
foreach ($line in $metadata) {
    $summary.Add(('metadata={0}' -f $line))
}
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

# Always include exact current sources needed by the next semantic decision.
$sourceRelative = @(
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderScalarEvaluator.cs',
    'src\SharpEmu.ShaderCompiler\Gen5ShaderIr.cs',
    'src\SharpEmu.Libs\Gpu\GuestGpuTypes.cs',
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'
)
$sourceHashes = New-Object System.Collections.Generic.List[string]
foreach ($relative in $sourceRelative) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $sourceHashes.Add(('MISSING  {0}' -f $relative))
        continue
    }

    $destination = Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $sourceHashes.Add(
        ('{0}  {1}' -f
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash,
            $relative))
}
Write-Utf8Lines -Path (Join-Path $out 'SOURCE_SHA256.txt') -Lines $sourceHashes

Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\V73_3_PRODUCERLESS_WAITS.csv') `
    -Destination (Join-Path $out 'V73_3_PRODUCERLESS_WAITS.csv') -Force

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force

Write-Host ('[V73.4] RESULT: {0}' -f $zipPath)
Write-Host ('[V73.4] classification={0}' -f $classification)
Write-Host ('[V73.4] targets={0} compute_overlap={1} writeback_overlap={2} pm4_overlap={3} event_addressed={4}' -f
    $targets.Count,
    $computeOverlap.Count,
    $writebackOverlap.Count,
    $pm4Overlap.Count,
    $eventAddressed.Count)
Write-Host ('[V73.4] waits/resumes={0}/{1}' -f $waitSuspended.Count, $queueResumed.Count)
