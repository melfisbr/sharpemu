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
$stdout = Join-Path $Patches ("V76.3.18.0_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.18.0_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.18.0_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.18.0_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main = $false
$first = $false
$deadline = $start.AddSeconds(220)

while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    if (Test-Path -LiteralPath $stdout) {
        $main = Select-String `
            -LiteralPath $stdout `
            -Pattern 'Starting main loop:' `
            -Quiet `
            -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $stderr) {
        $first = Select-String `
            -LiteralPath $stderr `
            -Pattern 'Vulkan VideoOut presented first frame' `
            -Quiet `
            -ErrorAction SilentlyContinue
    }

    if ($main -and $first -and (Get-Date) -gt $start.AddSeconds(190)) {
        break
    }
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out = if (Test-Path -LiteralPath $stdout) {
    @(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)
} else { @() }

$err = if (Test-Path -LiteralPath $stderr) {
    @(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)
} else { @() }

$timeline = @($out | Where-Object {
    $_ -match 'Starting Initialization:|' +
              'RecordResourceDependencies\(\) took|' +
              'Finished Initialization:|' +
              'Starting Script:|' +
              'Starting main loop:|' +
              'GatherResourceFileInfo\(\) took'
})

$merge = @($err | Where-Object {
    $_ -match '\[V76\.3\.18\.0\]\[(RPCS3_QUEUE_MERGE|QUEUE_ARCHITECTURE)\]'
})

$dualCreate = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_PHYSICAL_QUEUE\]'
})
$dualReady = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_PHYSICAL_QUEUE_READY\]'
})
$dualPolicy = @($err | Where-Object {
    $_ -match '\[V76\.3\.8\.3\]\[DUAL_QUEUE_POLICY\]'
})
$dualSubmit = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]'
})
$dualPresent = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_PRESENT_JOIN\]'
})

$graphicsMax = 0L
$computeMax = 0L
$switchMax = 0L
$waitedDualSubmitLines = 0
foreach ($line in $dualSubmit) {
    $lane = [regex]::Match($line, 'lane=(graphics|compute)')
    $count = [regex]::Match($line, 'lane_count=(\d+)')
    $switch = [regex]::Match($line, 'switch_count=(\d+)')
    $wait = [regex]::Match($line, '\bwait=(\d+)')

    if ($lane.Success -and $count.Success) {
        $v = [long]$count.Groups[1].Value
        if ($lane.Groups[1].Value -eq 'graphics') {
            if ($v -gt $graphicsMax) { $graphicsMax = $v }
        }
        else {
            if ($v -gt $computeMax) { $computeMax = $v }
        }
    }

    if ($switch.Success) {
        $v = [long]$switch.Groups[1].Value
        if ($v -gt $switchMax) { $switchMax = $v }
    }

    if ($wait.Success -and [long]$wait.Groups[1].Value -ne 0) {
        $waitedDualSubmitLines++
    }
}

$payload = @($err | Where-Object {
    $_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'
})
$lastPayloadAvg = ''
if ($payload.Count -ne 0) {
    $m = [regex]::Match($payload[-1], 'avg=([0-9]+(?:[.,][0-9]+)?)')
    if ($m.Success) { $lastPayloadAvg = $m.Groups[1].Value }
}

$chain = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.1\]\[COMPUTE_CHAIN\]'
})
$maxChain = 0
foreach ($line in $chain) {
    $m = [regex]::Match($line, 'compute_in_batch=(\d+)')
    if ($m.Success) {
        $v = [int]$m.Groups[1].Value
        if ($v -gt $maxChain) { $maxChain = $v }
    }
}

$cp = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP\]'
})
$cpFault = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP_FAULT\]'
})

$waitFast = @($err | Where-Object {
    $_ -match '\[V74\.0\.94\.3\]\[WAIT_REGISTRY_FAST_ONLY\]'
})
$maxFullCollects = 0L
foreach ($line in $waitFast) {
    $m = [regex]::Match($line, 'full_collects=(\d+)')
    if ($m.Success) {
        $v = [long]$m.Groups[1].Value
        if ($v -gt $maxFullCollects) { $maxFullCollects = $v }
    }
}

$waitDrain = @($err | Where-Object {
    $_ -match '\[V74\.0\.71\]\[DEDICATED_WAIT_DRAIN\]'
})
$slow = @($err | Where-Object {
    $_ -match 'SLOW_WAIT_PRODUCER'
})
$perf = @($err | Where-Object {
    $_ -match '\[PERF\]\[RENDER\]'
})
$starvation = @($err | Where-Object {
    $_ -match 'QUEUE_STARVATION|guest_queue_starvation'
})
$mem = @($err | Where-Object {
    $_ -match '\[V74\.0\.8\.1\]\[MEM\]'
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

$dualEnabled = $false
foreach ($line in $dualCreate) {
    if ($line -match 'enabled=1') {
        $dualEnabled = $true
        break
    }
}

@(
    'tag=V76.3.18.0-RPCS3-INSPIRED-QUEUE-ARCHITECTURE-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "dual_physical_enabled=$dualEnabled",
    "dual_graphics_submit_max=$graphicsMax",
    "dual_compute_submit_max=$computeMax",
    "dual_switch_count_max=$switchMax",
    "dual_waited_trace_lines=$waitedDualSubmitLines",
    "payload_batch_last_avg=$lastPayloadAvg",
    "max_compute_in_batch=$maxChain",
    "async_cp_trace_lines=$($cp.Count)",
    "async_cp_faults=$($cpFault.Count)",
    "wait_full_collects_max=$maxFullCollects",
    "wait_drain_trace_lines=$($waitDrain.Count)",
    "slow_wait_lines=$($slow.Count)",
    "queue_starvation_lines=$($starvation.Count)",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- V18 MERGE ---',
    $merge,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- DUAL CREATE ---',
    $dualCreate,
    $dualReady,
    $dualPolicy,
    '',
    '--- DUAL SUBMIT LAST ---',
    ($dualSubmit | Select-Object -Last 48),
    '',
    '--- DUAL PRESENT LAST ---',
    ($dualPresent | Select-Object -Last 16),
    '',
    '--- PAYLOAD LAST ---',
    ($payload | Select-Object -Last 16),
    '',
    '--- COMPUTE CHAIN LAST ---',
    ($chain | Select-Object -Last 16),
    '',
    '--- ASYNC AGC LAST ---',
    ($cp | Select-Object -Last 24),
    '',
    '--- WAIT FAST LAST ---',
    ($waitFast | Select-Object -Last 24),
    '',
    '--- WAIT DRAIN LAST ---',
    ($waitDrain | Select-Object -Last 24),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 24),
    '',
    '--- STARVATION ---',
    ($starvation | Select-Object -Last 24),
    '',
    '--- PERF LAST ---',
    ($perf | Select-Object -Last 32),
    '',
    '--- MEM LAST ---',
    ($mem | Select-Object -Last 8),
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

$files = @($stdout,$stderr,$summary) |
    Where-Object { Test-Path -LiteralPath $_ }

Compress-Archive `
    -LiteralPath $files `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first dual=$dualEnabled " +
    "gfx_submit=$graphicsMax compute_submit=$computeMax " +
    "payload_avg=$lastPayloadAvg compute_chain=$maxChain"
)
Write-Host (
    "[$Tag] full_collects=$maxFullCollects slow_wait=$($slow.Count) " +
    "device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
