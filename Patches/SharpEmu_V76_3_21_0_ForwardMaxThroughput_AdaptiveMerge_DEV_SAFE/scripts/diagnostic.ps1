param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "EXE ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# MAX mode by default.
Remove-Item Env:SHARPEMU_V763210_SAFE_MODE -ErrorAction SilentlyContinue

# Keep only summary-level profiling enabled.
$env:SHARPEMU_PROFILE_RENDER = '1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION = '1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S = '5'
$env:SHARPEMU_TRACE_FRAME_STATS = '1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.21.0_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.21.0_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.21.0_SUMMARY_$stamp.txt")
$gpuCsv = Join-Path $Patches ("V76.3.21.0_NVIDIA_GPU_$stamp.csv")
$result = Join-Path $Patches ("V76.3.21.0_RESULT_$stamp.zip")

"timestamp,gpu_util_percent,memory_used_mb,memory_total_mb,graphics_clock_mhz,sm_clock_mhz" |
    Set-Content -LiteralPath $gpuCsv -Encoding ASCII

$nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $nvidia) {
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
}

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main = $false
$first = $false
$lastGpuSample = [DateTime]::MinValue
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

    if ($nvidia -and ((Get-Date) - $lastGpuSample).TotalSeconds -ge 5) {
        $lastGpuSample = Get-Date
        try {
            $sample = & $nvidia.Source `
                --query-gpu=utilization.gpu,memory.used,memory.total,clocks.gr,clocks.sm `
                --format=csv,noheader,nounits 2>$null |
                Select-Object -First 1

            if ($sample) {
                $line = "$(Get-Date -Format o),$sample"
                Add-Content -LiteralPath $gpuCsv -Value $line -Encoding ASCII
            }
        }
        catch {}
    }

    if ($main -and $first -and (Get-Date) -gt $start.AddSeconds(190)) {
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
    $_ -match '\[V76\.3\.21\.0\]\[FORWARD_MAX_MERGE\]'
})
$dual = @($err | Where-Object { $_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]' })
$cp = @($err | Where-Object { $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP\]' })
$cpFault = @($err | Where-Object { $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP_FAULT\]' })
$payload = @($err | Where-Object { $_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]' })
$chain = @($err | Where-Object { $_ -match '\[V76\.3\.17\.1\]\[COMPUTE_CHAIN\]' })
$watched = @($err | Where-Object { $_ -match 'WATCHED_WRITE_PRODUCER_FASTPATH|CROSS_QUEUE_WATCHED_INLINE_WRITE' })
$residency = @($err | Where-Object { $_ -match 'GLOBAL_RESIDENCY|RESIDENT_GLOBAL|SHADER_GLOBAL_DIRECT_UPLOAD' })
$descriptor = @($err | Where-Object { $_ -match 'DESCRIPTOR_SET_CACHE' })
$residentShader = @($err | Where-Object { $_ -match '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\]' })
$fastWait = @($err | Where-Object { $_ -match '\[V74\.0\.94\.3\]\[WAIT_REGISTRY_FAST_ONLY\]' })
$slow = @($err | Where-Object { $_ -match 'SLOW_WAIT_PRODUCER' })
$perf = @($err | Where-Object { $_ -match '\[PERF\]\[RENDER\]' })
$mem = @($err | Where-Object { $_ -match '\[V74\.0\.8\.1\]\[MEM\]' })
$device = @($err | Where-Object {
    $_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'
})
$av = @($err | Where-Object { $_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION' })
$fatal = @($err | Where-Object { $_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException' })

$gfxMax = 0L
$computeMax = 0L
foreach ($line in $dual) {
    $lane = [regex]::Match($line,'lane=(graphics|compute)')
    $count = [regex]::Match($line,'lane_count=(\d+)')
    if ($lane.Success -and $count.Success) {
        $v = [long]$count.Groups[1].Value
        if ($lane.Groups[1].Value -eq 'graphics') {
            if ($v -gt $gfxMax) { $gfxMax = $v }
        } else {
            if ($v -gt $computeMax) { $computeMax = $v }
        }
    }
}

$payloadAvg = ''
if ($payload.Count) {
    $m = [regex]::Match($payload[-1],'avg=([0-9]+(?:[.,][0-9]+)?)')
    if ($m.Success) { $payloadAvg = $m.Groups[1].Value }
}

$maxChain = 0
foreach ($line in $chain) {
    $m = [regex]::Match($line,'compute_in_batch=(\d+)')
    if ($m.Success) {
        $v = [int]$m.Groups[1].Value
        if ($v -gt $maxChain) { $maxChain = $v }
    }
}

$fullCollectMax = 0L
foreach ($line in $fastWait) {
    $m = [regex]::Match($line,'full_collects=(\d+)')
    if ($m.Success) {
        $v = [long]$m.Groups[1].Value
        if ($v -gt $fullCollectMax) { $fullCollectMax = $v }
    }
}

$gpuRows = @()
if (Test-Path $gpuCsv) {
    try {
        $gpuRows = @(Import-Csv -LiteralPath $gpuCsv)
    } catch {}
}
$gpuUtil = @()
$vram = @()
foreach ($row in $gpuRows) {
    $u = 0.0
    if ([double]::TryParse(
            ($row.gpu_util_percent -replace ',','.'),
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$u)) {
        $gpuUtil += $u
    }
    $m = 0.0
    if ([double]::TryParse(
            ($row.memory_used_mb -replace ',','.'),
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$m)) {
        $vram += $m
    }
}

$gpuAvg = if ($gpuUtil.Count) {
    [Math]::Round(($gpuUtil | Measure-Object -Average).Average,2)
} else { 0 }
$gpuMax = if ($gpuUtil.Count) {
    [Math]::Round(($gpuUtil | Measure-Object -Maximum).Maximum,2)
} else { 0 }
$vramMax = if ($vram.Count) {
    [Math]::Round(($vram | Measure-Object -Maximum).Maximum,0)
} else { 0 }

@(
    'tag=V76.3.21.0-FORWARD-MAX-THROUGHPUT-ADAPTIVE-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "dual_graphics_submit_max=$gfxMax",
    "dual_compute_submit_max=$computeMax",
    "payload_batch_last_avg=$payloadAvg",
    "max_compute_in_batch=$maxChain",
    "async_cp_faults=$($cpFault.Count)",
    "watched_producer_trace_lines=$($watched.Count)",
    "global_residency_trace_lines=$($residency.Count)",
    "descriptor_cache_trace_lines=$($descriptor.Count)",
    "resident_shader_trace_lines=$($residentShader.Count)",
    "wait_full_collects_max=$fullCollectMax",
    "slow_wait_lines=$($slow.Count)",
    "nvidia_samples=$($gpuUtil.Count)",
    "nvidia_gpu_util_avg=$gpuAvg",
    "nvidia_gpu_util_max=$gpuMax",
    "nvidia_vram_used_max_mb=$vramMax",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- ACTIVE V21 PROFILE ---',
    $profile,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- DUAL QUEUE LAST ---',
    ($dual | Select-Object -Last 32),
    '',
    '--- ASYNC AGC LAST ---',
    ($cp | Select-Object -Last 16),
    '',
    '--- PAYLOAD LAST ---',
    ($payload | Select-Object -Last 16),
    '',
    '--- CHAIN LAST ---',
    ($chain | Select-Object -Last 16),
    '',
    '--- WATCHED PRODUCER LAST ---',
    ($watched | Select-Object -Last 24),
    '',
    '--- RESIDENCY LAST ---',
    ($residency | Select-Object -Last 24),
    '',
    '--- RESIDENT SHADER LAST ---',
    ($residentShader | Select-Object -Last 16),
    '',
    '--- WAIT FAST LAST ---',
    ($fastWait | Select-Object -Last 16),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 16),
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

$files = @($stdout,$stderr,$summary,$gpuCsv) |
    Where-Object { Test-Path -LiteralPath $_ }

Compress-Archive `
    -LiteralPath $files `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first gfx=$gfxMax compute=$computeMax " +
    "payload_avg=$payloadAvg chain=$maxChain"
)
Write-Host (
    "[$Tag] gpu_avg=$gpuAvg gpu_max=$gpuMax vram_max_mb=$vramMax " +
    "full_collects=$fullCollectMax slow_wait=$($slow.Count)"
)
Write-Host (
    "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
