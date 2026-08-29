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

# Keep only aggregate profiling; V18.1 disabled detailed hotpath census.
$env:SHARPEMU_PROFILE_RENDER = '1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION = '1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S = '5'
$env:SHARPEMU_TRACE_FRAME_STATS = '1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.18.1_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.18.1_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.18.1_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.18.1_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main = $false
$first = $false
$deadline = $start.AddSeconds(230)

while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $stdout) {
        $main = Select-String -LiteralPath $stdout `
            -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stderr) {
        $first = Select-String -LiteralPath $stderr `
            -Pattern 'Vulkan VideoOut presented first frame' -Quiet -ErrorAction SilentlyContinue
    }
    if ($main -and $first -and (Get-Date) -gt $start.AddSeconds(200)) {
        break
    }
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out = if (Test-Path $stdout) { @(Get-Content $stdout) } else { @() }
$err = if (Test-Path $stderr) { @(Get-Content $stderr) } else { @() }

$timeline = @($out | Where-Object {
    $_ -match 'Starting Initialization:|' +
              'RecordResourceDependencies\(\) took|' +
              'Finished Initialization:|' +
              'Starting Script:|' +
              'Starting main loop:|' +
              'GatherResourceFileInfo\(\) took'
})

$profile = @($err | Where-Object {
    $_ -match '\[V76\.3\.18\.1\]\[MAX_THROUGHPUT_PROFILE\]'
})
$dual = @($err | Where-Object {
    $_ -match 'DUAL_PHYSICAL_QUEUE|DUAL_QUEUE_SUBMIT|DUAL_QUEUE_POLICY'
})
$residentShader = @($err | Where-Object {
    $_ -match 'RESIDENT_SHADER'
})
$residentGlobal = @($err | Where-Object {
    $_ -match 'SHADER_GLOBAL_RESIDENCY|RESIDENT_GLOBAL|RESIDENT_READ_ONLY'
})
$descriptor = @($err | Where-Object {
    $_ -match 'DESCRIPTOR_SET_BLOCK_CACHE'
})
$rebar = @($err | Where-Object {
    $_ -match 'REBAR_GLOBAL_DIRECT|RUNTIME_SCALAR_DIRECT'
})
$payload = @($err | Where-Object {
    $_ -match 'PAYLOAD_BATCH_SUBMIT'
})
$drawBatch = @($err | Where-Object {
    $_ -match 'DRAW_COMMAND_BUFFER'
})
$chain = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.1\]\[COMPUTE_CHAIN\]'
})
$waitFast = @($err | Where-Object {
    $_ -match 'WAIT_REGISTRY_FAST_ONLY'
})
$slow = @($err | Where-Object {
    $_ -match 'SLOW_WAIT_PRODUCER'
})
$perf = @($err | Where-Object {
    $_ -match '\[PERF\]\[RENDER\]'
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

$lastPayloadAvg = ''
if ($payload.Count -gt 0) {
    $m = [regex]::Match($payload[-1], 'avg=([0-9]+(?:[.,][0-9]+)?)')
    if ($m.Success) { $lastPayloadAvg = $m.Groups[1].Value }
}

$maxChain = 0
foreach ($line in $chain) {
    $m = [regex]::Match($line,'compute_in_batch=(\d+)')
    if ($m.Success) {
        $v = [int]$m.Groups[1].Value
        if ($v -gt $maxChain) { $maxChain = $v }
    }
}

$maxFullCollects = 0L
foreach ($line in $waitFast) {
    $m = [regex]::Match($line,'full_collects=(\d+)')
    if ($m.Success) {
        $v = [long]$m.Groups[1].Value
        if ($v -gt $maxFullCollects) { $maxFullCollects = $v }
    }
}

@(
    'tag=V76.3.18.1-MAX-THROUGHPUT-RESIDENT-RESOURCE-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "last_payload_batch_avg=$lastPayloadAvg",
    "max_compute_in_batch=$maxChain",
    "resident_shader_trace_lines=$($residentShader.Count)",
    "resident_global_trace_lines=$($residentGlobal.Count)",
    "descriptor_cache_trace_lines=$($descriptor.Count)",
    "rebar_scalar_trace_lines=$($rebar.Count)",
    "wait_full_collects_max=$maxFullCollects",
    "slow_wait_lines=$($slow.Count)",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- PROFILE ---',$profile,
    '',
    '--- BOOT ---',$timeline,
    '',
    '--- DUAL QUEUE LAST ---',($dual | Select-Object -Last 48),
    '',
    '--- RESIDENT SHADER LAST ---',($residentShader | Select-Object -Last 16),
    '',
    '--- RESIDENT GLOBAL LAST ---',($residentGlobal | Select-Object -Last 24),
    '',
    '--- DESCRIPTOR CACHE LAST ---',($descriptor | Select-Object -Last 16),
    '',
    '--- REBAR / SCALAR LAST ---',($rebar | Select-Object -Last 16),
    '',
    '--- PAYLOAD LAST ---',($payload | Select-Object -Last 16),
    '',
    '--- DRAW BATCH LAST ---',($drawBatch | Select-Object -Last 16),
    '',
    '--- CHAIN LAST ---',($chain | Select-Object -Last 16),
    '',
    '--- WAIT FAST LAST ---',($waitFast | Select-Object -Last 16),
    '',
    '--- SLOW WAIT LAST ---',($slow | Select-Object -Last 16),
    '',
    '--- PERF LAST ---',($perf | Select-Object -Last 40),
    '',
    '--- DEVICE LOST ---',$device,
    '',
    '--- ACCESS VIOLATION ---',$av,
    '',
    '--- FATAL ---',$fatal
) | Set-Content -LiteralPath $summary -Encoding UTF8

Compress-Archive `
    -LiteralPath @($stdout,$stderr,$summary) `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first payload_avg=$lastPayloadAvg " +
    "chain=$maxChain full_collects=$maxFullCollects"
)
Write-Host (
    "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
