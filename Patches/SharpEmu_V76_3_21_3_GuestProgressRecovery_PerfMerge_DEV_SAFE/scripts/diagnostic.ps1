param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Fail "EXE ausente: $exe"
}
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) {
    Fail "eboot ausente: $game"
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$env:SHARPEMU_PROFILE_RENDER = '1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION = '1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S = '5'
$env:SHARPEMU_TRACE_FRAME_STATS = '1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.21.3_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.21.3_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.21.3_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.21.3_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main = $false
$first = $false
$natural = $false
$deadline = $start.AddSeconds(240)
$naturalSeenAt = $null

while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    if (Test-Path -LiteralPath $stdout) {
        $main = Select-String -LiteralPath $stdout `
            -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $stderr) {
        $first = Select-String -LiteralPath $stderr `
            -Pattern 'Vulkan VideoOut presented first frame' `
            -Quiet -ErrorAction SilentlyContinue

        if (-not $natural) {
            $natural = Select-String -LiteralPath $stderr `
                -Pattern "bink2\.natural_guest_movie_observed.*ps_studios_logo\.bk2" `
                -Quiet -ErrorAction SilentlyContinue
            if ($natural) {
                $naturalSeenAt = Get-Date
            }
        }
    }

    # Once the natural Bink handoff is observed, retain ~35 seconds of
    # post-handoff evidence instead of killing immediately.
    if ($natural -and $naturalSeenAt -and
        (Get-Date) -gt $naturalSeenAt.AddSeconds(35)) {
        break
    }
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out = if (Test-Path -LiteralPath $stdout) {
    @(Get-Content -LiteralPath $stdout)
} else { @() }

$err = if (Test-Path -LiteralPath $stderr) {
    @(Get-Content -LiteralPath $stderr)
} else { @() }

$timeline = @($out | Where-Object {
    $_ -match 'Starting Initialization:|' +
              'RecordResourceDependencies\(\) took|' +
              'Finished Initialization:|' +
              'Starting Script:|' +
              'Starting main loop:|' +
              'GatherResourceFileInfo\(\) took'
})

$profile = @($err | Where-Object {
    $_ -match '\[V76\.3\.21\.3\]\[GUEST_PROGRESS_RECOVERY\]'
})
$agc = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP\]'
})
$naturalLines = @($err | Where-Object {
    $_ -match 'bink2\.natural_guest_movie_observed|\[BINK-HOST\].*NATURAL-REQUEST'
})
$drawCb = @($err | Where-Object {
    $_ -match '\[V76\.3\.8\.3\]\[DRAW_COMMAND_BUFFER\]'
})
$scanout = @($err | Where-Object {
    $_ -match '\[V74\.0\.56\.28\]\[DIRECT_SCANOUT\]'
})
$dual = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_(PHYSICAL_QUEUE|QUEUE_SUBMIT)'
})
$perf = @($err | Where-Object {
    $_ -match '\[PERF\]\[RENDER\]'
})
$slow = @($err | Where-Object {
    $_ -match '\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\]'
})
$device = @($err | Where-Object {
    $_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'
})
$av = @($err | Where-Object {
    $_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'
})
$fatal = @($err | Where-Object {
    $_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'
})

$maxAgcEnqueue = 0L
$maxAgcProcessed = 0L
foreach ($line in $agc) {
    $me = [regex]::Match($line,'phase=enqueue count=(\d+)')
    if ($me.Success) {
        $v=[long]$me.Groups[1].Value
        if ($v -gt $maxAgcEnqueue) { $maxAgcEnqueue=$v }
    }
    $mp = [regex]::Match($line,'phase=processed count=(\d+)')
    if ($mp.Success) {
        $v=[long]$mp.Groups[1].Value
        if ($v -gt $maxAgcProcessed) { $maxAgcProcessed=$v }
    }
}

$maxDrawSubmission = 0L
foreach ($line in $drawCb) {
    $m=[regex]::Match($line,'submission=(\d+)')
    if ($m.Success) {
        $v=[long]$m.Groups[1].Value
        if ($v -gt $maxDrawSubmission) { $maxDrawSubmission=$v }
    }
}

$maxScanoutFrame = 0L
foreach ($line in $scanout) {
    $m=[regex]::Match($line,'frame_count=(\d+)')
    if ($m.Success) {
        $v=[long]$m.Groups[1].Value
        if ($v -gt $maxScanoutFrame) { $maxScanoutFrame=$v }
    }
}

@(
    'tag=V76.3.21.3-GUEST-PROGRESS-RECOVERY-PERF-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "natural_ps_studios_request=$natural",
    "max_agc_enqueue_count=$maxAgcEnqueue",
    "max_agc_processed_count=$maxAgcProcessed",
    "max_draw_submission=$maxDrawSubmission",
    "max_direct_scanout_frame=$maxScanoutFrame",
    "natural_movie_lines=$($naturalLines.Count)",
    "slow_wait_lines=$($slow.Count)",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    'REFERENCE_V21_2_STALL=agc1024/submission1176-1181/scanout44/no-natural-bink',
    'REFERENCE_V17_1_PROGRESS=agc2048+/submission2064+/scanout83/natural-ps_studios',
    '',
    '--- ACTIVE PROFILE ---',
    $profile,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- NATURAL MOVIE ---',
    $naturalLines,
    '',
    '--- AGC LAST ---',
    ($agc | Select-Object -Last 24),
    '',
    '--- DRAW CB LAST ---',
    ($drawCb | Select-Object -Last 24),
    '',
    '--- SCANOUT LAST ---',
    ($scanout | Select-Object -Last 24),
    '',
    '--- DUAL LAST ---',
    ($dual | Select-Object -Last 32),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 24),
    '',
    '--- PERF LAST ---',
    ($perf | Select-Object -Last 32),
    '',
    '--- STDERR TAIL ---',
    ($err | Select-Object -Last 96)
) | Set-Content -LiteralPath $summary -Encoding UTF8

Compress-Archive `
    -LiteralPath @($stdout,$stderr,$summary) `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first natural_ps_studios=$natural " +
    "agc=$maxAgcProcessed draw_submission=$maxDrawSubmission " +
    "scanout_frame=$maxScanoutFrame"
)
Write-Host (
    "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
