param(
    [string]$RepositoryRoot,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$presenterText = [IO.File]::ReadAllText($presenter)
if (-not (Test-ContainsOrdinal -Text $presenterText -Pattern 'RequireGlobalVisibility: false,') -or
    -not (Test-ContainsOrdinal -Text $presenterText -Pattern 'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)')) {
    throw '[V73.3] Diagnostic refused: fixed visibility binding is not installed.'
}

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.3] EBOOT missing: {0}' -f $Eboot)
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
    throw '[V73.3] SharpEmu.exe not found. Run RUN_APPLY_BUILD_V73_3.cmd first.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_3_ORDERED_VISIBILITY_RESULT_{0}' -f $stamp)
$followup = Join-Path $out 'followup_sources'
New-Item -ItemType Directory -Force -Path $out | Out-Null
New-Item -ItemType Directory -Force -Path $followup | Out-Null

$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'

$oldAgc = $env:SHARPEMU_LOG_AGC
$oldAgcShader = $env:SHARPEMU_LOG_AGC_SHADER
$oldVk = $env:SHARPEMU_LOG_VK_RESOURCES
$oldDraws = $env:SHARPEMU_TRACE_DRAWS
$oldFrames = $env:SHARPEMU_TRACE_FRAME_PACKETS

try {
    Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_TRACE_DRAWS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_TRACE_FRAME_PACKETS -ErrorAction SilentlyContinue

    Write-Host '[V73.3] Starting representative Demons Souls run.'
    Write-Host '[V73.3] Let it reach the usual post-video/menu transition, then close the emulator.'
    Write-Host ('[V73.3] Executable: {0}' -f $exe)

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
    if ($null -eq $oldAgc) { Remove-Item Env:SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC = $oldAgc }
    if ($null -eq $oldAgcShader) { Remove-Item Env:SHARPEMU_LOG_AGC_SHADER -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_AGC_SHADER = $oldAgcShader }
    if ($null -eq $oldVk) { Remove-Item Env:SHARPEMU_LOG_VK_RESOURCES -ErrorAction SilentlyContinue } else { $env:SHARPEMU_LOG_VK_RESOURCES = $oldVk }
    if ($null -eq $oldDraws) { Remove-Item Env:SHARPEMU_TRACE_DRAWS -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_DRAWS = $oldDraws }
    if ($null -eq $oldFrames) { Remove-Item Env:SHARPEMU_TRACE_FRAME_PACKETS -ErrorAction SilentlyContinue } else { $env:SHARPEMU_TRACE_FRAME_PACKETS = $oldFrames }
}

$allLines = New-Object System.Collections.Generic.List[string]
foreach ($path in @($stdout, $stderr)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }

    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $allLines.Add($line)
    }
}

function Get-LinesContaining {
    param([string]$Needle)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $allLines) {
        if ($line.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $result.Add($line)
        }
    }

    return $result.ToArray()
}

$ordered = @(Get-LinesContaining 'vk.ordered_action_fence_wait')
$backpressure = @(Get-LinesContaining 'vk.guest_queue_backpressure')
$starvation = @(Get-LinesContaining 'vk.guest_queue_starvation')
$waits = @(Get-LinesContaining 'agc.wait_suspended')
$resumed = @(Get-LinesContaining 'agc.queue_resumed')
$rejects = @(Get-LinesContaining 'agc.dispatch_reject')
$noops = @(Get-LinesContaining 'agc.dispatch_noop')
$events = @(Get-LinesContaining '[V17][EVENT_FASTPATH]')
$frames = @(Get-LinesContaining 'Vulkan VideoOut presented guest frame')
$unresolved = @(Get-LinesContaining 'unresolved:')
$deviceLost = @(Get-LinesContaining 'deviceLost=True')
$metadata = @(Get-LinesContaining 'SCE import metadata:')

$orderedMax = Get-MaxCounterFromLines -Lines $ordered -Field 'count'
$backpressureMax = Get-MaxCounterFromLines -Lines $backpressure -Field 'count'
$eventMax = Get-MaxCounterFromLines -Lines $events -Field 'n'

$orderedComparison = 'not-observed'
if ($orderedMax -gt 0) {
    if ($orderedMax -lt 512) {
        $orderedComparison = 'improved'
    }
    elseif ($orderedMax -eq 512) {
        $orderedComparison = 'same-sampled-bound'
    }
    else {
        $orderedComparison = 'higher'
    }
}

$backpressureComparison = 'not-observed'
if ($backpressureMax -gt 0) {
    if ($backpressureMax -lt 8) {
        $backpressureComparison = 'improved'
    }
    elseif ($backpressureMax -eq 8) {
        $backpressureComparison = 'same'
    }
    else {
        $backpressureComparison = 'higher'
    }
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.3')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('presenter_sha256={0}' -f (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash))
$summary.Add(('ordered_action_fence_wait_sample_lines={0}' -f $ordered.Count))
$summary.Add(('ordered_action_fence_wait_max_counter={0}' -f $orderedMax))
$summary.Add('baseline_ordered_action_fence_wait_max_counter=512')
$summary.Add(('ordered_fence_counter_vs_baseline={0}' -f $orderedComparison))
$summary.Add(('guest_queue_backpressure_lines={0}' -f $backpressure.Count))
$summary.Add(('guest_queue_backpressure_max_counter={0}' -f $backpressureMax))
$summary.Add('baseline_guest_queue_backpressure_max_counter=8')
$summary.Add(('backpressure_counter_vs_baseline={0}' -f $backpressureComparison))
$summary.Add(('guest_queue_starvation_lines={0}' -f $starvation.Count))
$summary.Add(('wait_suspended_lines={0}' -f $waits.Count))
$summary.Add('baseline_wait_suspended_lines=7')
$summary.Add(('queue_resumed_lines={0}' -f $resumed.Count))
$summary.Add('baseline_queue_resumed_lines=0')
$summary.Add(('dispatch_reject_lines={0}' -f $rejects.Count))
$summary.Add(('dispatch_noop_lines={0}' -f $noops.Count))
$summary.Add(('event_fastpath_max_n={0}' -f $eventMax))
$summary.Add(('guest_frame_lines={0}' -f $frames.Count))
$summary.Add(('runtime_unresolved_lines={0}' -f $unresolved.Count))
$summary.Add(('device_lost_true_lines={0}' -f $deviceLost.Count))
foreach ($line in $metadata) {
    $summary.Add(('metadata={0}' -f $line))
}

Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary
Write-Utf8Lines -Path (Join-Path $out 'WAIT_SUSPENDED.txt') -Lines $waits
Write-Utf8Lines -Path (Join-Path $out 'QUEUE_RESUMED.txt') -Lines $resumed
Write-Utf8Lines -Path (Join-Path $out 'ORDERED_FENCE_WAITS.txt') -Lines $ordered
Write-Utf8Lines -Path (Join-Path $out 'BACKPRESSURE.txt') -Lines $backpressure
Write-Utf8Lines -Path (Join-Path $out 'STARVATION.txt') -Lines $starvation

# If producerless waits remain, collect exact current evaluator/resource-binding
# source now so the next correction does not need another collector round.
$terms = @(
    'Gen5GlobalMemoryBinding',
    'Gen5ShaderScalarEvaluator',
    'WriteBackToGuest',
    'GuestMemoryBuffer'
)
$matched = @{}
$matchLines = New-Object System.Collections.Generic.List[string]

$csFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue)
foreach ($file in $csFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($term in $terms) {
        if ($text.IndexOf($term, [StringComparison]::Ordinal) -lt 0) {
            continue
        }

        $matched[$file.FullName] = $true
        $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
        $matchLines.Add(('{0}`t{1}' -f $relative, $term))
    }
}

$sourceHashes = New-Object System.Collections.Generic.List[string]
$copied = 0
foreach ($source in @($matched.Keys | Sort-Object)) {
    if ($copied -ge 30) {
        break
    }

    $relative = $source.Substring($root.Length).TrimStart('\','/')
    $destination = Join-Path $followup $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $sourceHashes.Add(('{0}  {1}' -f $hash, $relative))
    $copied++
}

Write-Utf8Lines -Path (Join-Path $out 'FOLLOWUP_SOURCE_MATCHES.txt') -Lines @($matchLines | Sort-Object -Unique)
Write-Utf8Lines -Path (Join-Path $out 'FOLLOWUP_SOURCE_SHA256.txt') -Lines $sourceHashes

Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\BUG_PROOF.txt') `
    -Destination (Join-Path $out 'V73_3_BUG_PROOF.txt') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'evidence\BASELINE_RUNTIME_METRICS.json') `
    -Destination (Join-Path $out 'BASELINE_RUNTIME_METRICS.json') -Force

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force

Write-Host ('[V73.3] RESULT: {0}' -f $zipPath)
Write-Host ('[V73.3] ordered fence counter: current={0}, baseline>=512' -f $orderedMax)
Write-Host ('[V73.3] backpressure counter: current={0}, baseline=8' -f $backpressureMax)
Write-Host ('[V73.3] waits/resumes: current={0}/{1}, baseline=7/0' -f $waits.Count, $resumed.Count)
Write-Host ('[V73.3] follow-up evaluator/resource files copied: {0}' -f $copied)
