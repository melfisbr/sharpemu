param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "Debug exe ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# Make V21.4 behavior impossible during this verification, even if a stale binary/source exists.
$env:SHARPEMU_V763214_DISABLE='1'
$env:SHARPEMU_BINK_AUTO_BOOT='0'
Remove-Item Env:\SHARPEMU_BINK_BOOT_SEQUENCE -ErrorAction SilentlyContinue

# Low-overhead: rely on existing sampled Async AGC / submission / scanout telemetry.
$env:SHARPEMU_TRACE_SCENE_PIPELINE_GAPS='0'
$env:SHARPEMU_TRACE_GEOMETRY_DRAWS='0'
$env:SHARPEMU_TRACE_PRIMITIVE_PIPELINE='0'
$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS='0'
$env:SHARPEMU_PERIODIC_SNAPSHOT_SECONDS='0'
$env:SHARPEMU_PROFILE_RENDER='0'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='0'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches "V76.3.21.4.1_STDOUT_$stamp.log"
$stderr = Join-Path $Patches "V76.3.21.4.1_STDERR_$stamp.log"
$summary = Join-Path $Patches "V76.3.21.4.1_SUMMARY_$stamp.txt"
$result = Join-Path $Patches "V76.3.21.4.1_RESULT_$stamp.zip"
$snapshotStdout = Join-Path $Patches "V76.3.21.4.1_STDOUT_SNAPSHOT_$stamp.log"
$snapshotStderr = Join-Path $Patches "V76.3.21.4.1_STDERR_SNAPSHOT_$stamp.log"

$start = Get-Date
$p = Start-Process -FilePath $exe -ArgumentList @($game) -PassThru `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr

$deadline = $start.AddSeconds(210)
$naturalSeenAt = $null

while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    if (-not $naturalSeenAt -and (Test-Path -LiteralPath $stderr)) {
        $hit = Select-String -LiteralPath $stderr `
            -Pattern "NATURAL-REQUEST.*file='ps_studios_logo\.bk2'|natural_guest_movie_observed.*file='ps_studios_logo\.bk2'" `
            -Quiet -ErrorAction SilentlyContinue
        if ($hit) { $naturalSeenAt = Get-Date }
    }

    if ($naturalSeenAt -and (Get-Date) -ge $naturalSeenAt.AddSeconds(15)) {
        break
    }
}

$processLeftRunning = -not $p.HasExited
$exitCode = ''
if ($p.HasExited) {
    try {
        $p.WaitForExit()
        $exitCode = $p.ExitCode
    }
    catch {}
}

# IMPORTANT: unlike V21.4, reaching the diagnostic collection deadline does NOT
# kill SharpEmu. The emulator stays open for observation/game interaction.
Start-Sleep -Milliseconds 200

$out = if (Test-Path -LiteralPath $stdout) { @(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue) } else { @() }
$err = if (Test-Path -LiteralPath $stderr) { @(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue) } else { @() }

function Get-MaxLong([object[]]$Lines,[string]$Pattern) {
    $max = 0L
    foreach ($line in $Lines) {
        $m = [regex]::Match($line,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            $v = 0L
            if ([long]::TryParse($m.Groups[1].Value,[ref]$v) -and $v -gt $max) {
                $max = $v
            }
        }
    }
    return $max
}

$natural = @($err | Where-Object {
    $_ -match "NATURAL-REQUEST.*file='ps_studios_logo\.bk2'|natural_guest_movie_observed.*file='ps_studios_logo\.bk2'"
})
$agcEnqueue = @($err | Where-Object { $_ -match '\[AGC_ASYNC_CP\].*phase=enqueue' })
$agcProcessed = @($err | Where-Object { $_ -match '\[AGC_ASYNC_CP\].*phase=processed' })
$graphics = @($err | Where-Object { $_ -match 'queue=dcb\.graphics.*submission=\d+' })
$scanout = @($err | Where-Object { $_ -match '\[DIRECT_SCANOUT\].*frame_count=\d+' })
$mem = @($err | Where-Object { $_ -match '\[V74\.0\.8\.1\]\[MEM\]' })
$device = @($err | Where-Object { $_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]' })
$av = @($err | Where-Object { $_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION' })
$fatal = @($err | Where-Object { $_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException' })
$v214Residue = @($err | Where-Object { $_ -match '\[V76\.3\.21\.4\]\[AGC_PUBLISH_FAIRNESS\]' })

$maxEnqueue = Get-MaxLong $agcEnqueue 'count=(\d+)'
$maxProcessed = Get-MaxLong $agcProcessed 'count=(\d+)'
$maxGraphics = Get-MaxLong $graphics 'queue=dcb\.graphics.*submission=(\d+)'
$maxScanout = Get-MaxLong $scanout 'frame_count=(\d+)'

$lastTimelineSubmitted = 0L
$lastTimelineCompleted = 0L
$lastPending = -1L
if ($mem.Count -gt 0) {
    $last = [string]$mem[-1]
    $tm = [regex]::Match($last,'timeline=(\d+)/(\d+)')
    if ($tm.Success) {
        [long]::TryParse($tm.Groups[1].Value,[ref]$lastTimelineSubmitted) | Out-Null
        [long]::TryParse($tm.Groups[2].Value,[ref]$lastTimelineCompleted) | Out-Null
    }
    $pm = [regex]::Match($last,'pending=(\d+)')
    if ($pm.Success) {
        [long]::TryParse($pm.Groups[1].Value,[ref]$lastPending) | Out-Null
    }
}

$gpuDrained = $lastTimelineSubmitted -gt 0 -and
              $lastTimelineSubmitted -eq $lastTimelineCompleted -and
              $lastPending -eq 0

$passedV214Regression = $maxEnqueue -gt 512 -or $maxGraphics -gt 700 -or $maxScanout -gt 24

$stallClass =
    if ($natural.Count -gt 0) {
        'progressed-to-ps-studios'
    }
    elseif ($passedV214Regression) {
        'recovered-beyond-v214-regression'
    }
    elseif ($gpuDrained) {
        'gpu-drained-before-v214-regression-threshold'
    }
    elseif ($maxEnqueue -gt $maxProcessed) {
        'async-consumer-lag'
    }
    else {
        'collection-ended-without-decisive-stall'
    }

@(
    'tag=V76.3.21.4.1-AGC-PUBLISH-FAIRNESS-ROLLBACK-NORMAL-RUN-RECOVERY-DEV-SAFE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "exit_code=$exitCode",
    "process_left_running=$processLeftRunning",
    "process_id=$($p.Id)",
    "v214_runtime_marker_lines=$($v214Residue.Count)",
    "natural_ps_studios_request=$($natural.Count -gt 0)",
    "max_agc_enqueue_count=$maxEnqueue",
    "max_agc_processed_count=$maxProcessed",
    "max_draw_submission=$maxGraphics",
    "max_direct_scanout_frame=$maxScanout",
    "passed_v214_regression_threshold=$passedV214Regression",
    "last_timeline=$lastTimelineSubmitted/$lastTimelineCompleted",
    "last_pending=$lastPending",
    "gpu_drained=$gpuDrained",
    "stall_class=$stallClass",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- NATURAL PS STUDIOS ---',
    $natural,
    '',
    '--- ASYNC AGC LAST ---',
    (($agcEnqueue + $agcProcessed) | Select-Object -Last 96),
    '',
    '--- GRAPHICS/SCANOUT LAST ---',
    (($graphics + $scanout) | Select-Object -Last 64),
    '',
    '--- LAST MEMORY STATE ---',
    ($mem | Select-Object -Last 16),
    '',
    '--- V21.4 RUNTIME RESIDUE ---',
    $v214Residue,
    '',
    '--- DEVICE LOST ---',
    $device,
    '',
    '--- ACCESS VIOLATION ---',
    $av,
    '',
    '--- FATAL ---',
    $fatal
) | Set-Content -LiteralPath $summary -Encoding UTF8

$pack = @($summary)

if ($processLeftRunning) {
    if (Copy-LiveFile $stdout $snapshotStdout) { $pack += $snapshotStdout }
    if (Copy-LiveFile $stderr $snapshotStderr) { $pack += $snapshotStderr }
}
else {
    if (Test-Path -LiteralPath $stdout) { $pack += $stdout }
    if (Test-Path -LiteralPath $stderr) { $pack += $stderr }
}

$pack = @($pack | Where-Object { Test-Path -LiteralPath $_ })
Compress-Archive -LiteralPath $pack -DestinationPath $result -CompressionLevel Optimal -Force

Write-Host ""
Write-Host "[$Tag] DIAGNOSTIC COMPLETE" -ForegroundColor Green
Write-Host "[$Tag] natural_ps=$($natural.Count -gt 0) enqueue=$maxEnqueue processed=$maxProcessed draw=$maxGraphics scanout=$maxScanout"
Write-Host "[$Tag] gpu_drained=$gpuDrained stall_class=$stallClass"
Write-Host "[$Tag] process_left_running=$processLeftRunning pid=$($p.Id)"
Write-Host "[$Tag] result=$result"
if ($processLeftRunning) {
    Write-Host "[$Tag] SharpEmu foi deixado ABERTO intencionalmente apos a coleta." -ForegroundColor Yellow
}
