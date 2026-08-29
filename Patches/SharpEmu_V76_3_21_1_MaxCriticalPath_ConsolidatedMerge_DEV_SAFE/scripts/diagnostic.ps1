param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Fail "SharpEmu.exe ausente: $exe"
}
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) {
    Fail "eboot ausente: $game"
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# Low-volume performance telemetry only.
$env:SHARPEMU_PROFILE_RENDER = '1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION = '1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S = '5'
$env:SHARPEMU_TRACE_FRAME_STATS = '1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.21.1_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.21.1_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.21.1_SUMMARY_$stamp.txt")
$gpuLog = Join-Path $Patches ("V76.3.21.1_NVIDIA_$stamp.log")
$result = Join-Path $Patches ("V76.3.21.1_RESULT_$stamp.zip")

$nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $nvidia) {
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
}

$started = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main = $false
$first = $false
$mainDetectedAt = $null
$nextGpuSample = Get-Date
$hardDeadline = $started.AddSeconds(390)

while (-not $p.HasExited -and (Get-Date) -lt $hardDeadline) {
    Start-Sleep -Milliseconds 500

    if (Test-Path -LiteralPath $stdout) {
        $sawMain = Select-String `
            -LiteralPath $stdout `
            -Pattern 'Starting main loop:' `
            -Quiet `
            -ErrorAction SilentlyContinue

        if ($sawMain -and -not $main) {
            $main = $true
            $mainDetectedAt = Get-Date
        }
    }

    if (Test-Path -LiteralPath $stderr) {
        $first = Select-String `
            -LiteralPath $stderr `
            -Pattern 'Vulkan VideoOut presented first frame' `
            -Quiet `
            -ErrorAction SilentlyContinue
    }

    if ($nvidia -and (Get-Date) -ge $nextGpuSample) {
        try {
            $sample = & $nvidia.Source `
                --query-gpu=utilization.gpu,memory.used,power.draw `
                --format=csv,noheader,nounits 2>$null

            if ($sample) {
                "$([DateTime]::Now.ToString('O')),$sample" |
                    Add-Content -LiteralPath $gpuLog -Encoding UTF8
            }
        }
        catch {}
        $nextGpuSample = (Get-Date).AddSeconds(5)
    }

    # Collect 180 seconds after main loop when possible.
    if ($mainDetectedAt -and
        (Get-Date) -ge $mainDetectedAt.AddSeconds(180)) {
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

function Get-MaxLong(
    [object[]]$Lines,
    [string]$Pattern) {

    $max = 0L
    $found = $false

    foreach ($line in $Lines) {
        $m = [regex]::Match($line, $Pattern)
        if ($m.Success) {
            $raw = $m.Groups[1].Value.Replace(',', '.')
            $v = 0.0
            if ([double]::TryParse(
                    $raw,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$v)) {
                if (-not $found -or $v -gt $max) {
                    $max = [long][Math]::Ceiling($v)
                    $found = $true
                }
            }
        }
    }

    if ($found) { return $max }
    return 0L
}

function Get-DoubleValues(
    [object[]]$Lines,
    [string]$Pattern) {

    $values = New-Object System.Collections.Generic.List[double]
    foreach ($line in $Lines) {
        $m = [regex]::Match($line, $Pattern)
        if (-not $m.Success) { continue }

        $raw = $m.Groups[1].Value.Replace(',', '.')
        $v = 0.0
        if ([double]::TryParse(
                $raw,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$v)) {
            $values.Add($v)
        }
    }
    return $values
}

$timeline = @($out | Where-Object {
    $_ -match 'Starting Initialization:|' +
              'RecordResourceDependencies\(\) took|' +
              'Finished Initialization:|' +
              'Starting Script:|' +
              'Starting main loop:|' +
              'GatherResourceFileInfo\(\) took'
})

$profile = @($err | Where-Object {
    $_ -match '\[V76\.3\.21\.1\]\[MAX_CRITICAL_PATH_MERGE\]'
})
$dual = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]'
})
$chain = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.1\]\[COMPUTE_CHAIN\]'
})
$drawBatch = @($err | Where-Object {
    $_ -match '\[V76\.3\.8\.3\]\[DRAW_COMMAND_BUFFER\]'
})
$micro = @($err | Where-Object {
    $_ -match '\[V76\.3\.8\.1\]\[ORDERED_MICROBATCH\]'
})
$payload = @($err | Where-Object {
    $_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'
})
$closureActivate = @($err | Where-Object {
    $_ -match 'WEIGHTED_PRODUCER_CLOSURE.*phase=activate'
})
$closureTake = @($err | Where-Object {
    $_ -match 'WEIGHTED_PRODUCER_CLOSURE.*phase=take'
})
$closureRelease = @($err | Where-Object {
    $_ -match 'WEIGHTED_PRODUCER_CLOSURE.*phase=release'
})
$fifoProducer = @($err | Where-Object {
    $_ -match 'FIFO_WATCHED_PRODUCER'
})
$slow = @($err | Where-Object {
    $_ -match '\[V74\.0\.27\]\[SLOW_WAIT_PRODUCER\]'
})
$waitFast = @($err | Where-Object {
    $_ -match '\[V74\.0\.94\.3\]\[WAIT_REGISTRY_FAST_ONLY\]'
})
$perf = @($err | Where-Object {
    $_ -match '\[PERF\]\[RENDER\]'
})
$cpFault = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP_FAULT\]'
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

$maxChain = Get-MaxLong $chain 'compute_in_batch=(\d+)'
$maxFullCollects = Get-MaxLong $waitFast 'full_collects=(\d+)'

$lastPayloadAvg = ''
if ($payload.Count -ne 0) {
    $m = [regex]::Match(
        $payload[-1],
        'avg=([0-9]+(?:[.,][0-9]+)?)')
    if ($m.Success) {
        $lastPayloadAvg = $m.Groups[1].Value
    }
}

$activationAge = Get-DoubleValues $closureActivate 'age_ms=([0-9]+(?:[.,][0-9]+)?)'
$waited = Get-DoubleValues $slow 'waited_ms=([0-9]+(?:[.,][0-9]+)?)'
$producerMs = Get-DoubleValues $slow 'producer_complete_ms=([0-9]+(?:[.,][0-9]+)?)'
$postMs = Get-DoubleValues $slow 'post_complete_wait_ms=([0-9]+(?:[.,][0-9]+)?)'

function Avg-Or-Zero($Values) {
    if ($Values.Count -eq 0) { return 0.0 }
    return ($Values | Measure-Object -Average).Average
}
function Max-Or-Zero($Values) {
    if ($Values.Count -eq 0) { return 0.0 }
    return ($Values | Measure-Object -Maximum).Maximum
}

$gpuUtil = New-Object System.Collections.Generic.List[double]
$vram = New-Object System.Collections.Generic.List[double]
$power = New-Object System.Collections.Generic.List[double]

if (Test-Path -LiteralPath $gpuLog) {
    foreach ($line in Get-Content -LiteralPath $gpuLog) {
        $parts = $line -split ','
        if ($parts.Count -lt 4) { continue }

        $v = 0.0
        if ([double]::TryParse(
                $parts[$parts.Count - 3].Trim(),
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$v)) {
            $gpuUtil.Add($v)
        }

        if ([double]::TryParse(
                $parts[$parts.Count - 2].Trim(),
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$v)) {
            $vram.Add($v)
        }

        if ([double]::TryParse(
                $parts[$parts.Count - 1].Trim(),
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$v)) {
            $power.Add($v)
        }
    }
}

@(
    'tag=V76.3.21.1-MAX-CRITICAL-PATH-CONSOLIDATED-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$started).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "payload_batch_last_avg=$lastPayloadAvg",
    "max_compute_in_batch=$maxChain",
    "draw_batch_trace_lines=$($drawBatch.Count)",
    "ordered_microbatch_trace_lines=$($micro.Count)",
    "closure_activate_lines=$($closureActivate.Count)",
    "closure_take_trace_lines=$($closureTake.Count)",
    "closure_release_lines=$($closureRelease.Count)",
    "closure_activation_age_avg_ms=$([Math]::Round((Avg-Or-Zero $activationAge),3))",
    "closure_activation_age_max_ms=$([Math]::Round((Max-Or-Zero $activationAge),3))",
    "fifo_watched_producer_trace_lines=$($fifoProducer.Count)",
    "slow_wait_lines=$($slow.Count)",
    "slow_wait_avg_ms=$([Math]::Round((Avg-Or-Zero $waited),3))",
    "slow_wait_max_ms=$([Math]::Round((Max-Or-Zero $waited),3))",
    "producer_complete_avg_ms=$([Math]::Round((Avg-Or-Zero $producerMs),3))",
    "producer_complete_max_ms=$([Math]::Round((Max-Or-Zero $producerMs),3))",
    "post_complete_avg_ms=$([Math]::Round((Avg-Or-Zero $postMs),3))",
    "post_complete_max_ms=$([Math]::Round((Max-Or-Zero $postMs),3))",
    "wait_full_collects_max=$maxFullCollects",
    "async_cp_faults=$($cpFault.Count)",
    "nvidia_samples=$($gpuUtil.Count)",
    "nvidia_gpu_util_avg=$([Math]::Round((Avg-Or-Zero $gpuUtil),1))",
    "nvidia_gpu_util_max=$([Math]::Round((Max-Or-Zero $gpuUtil),1))",
    "nvidia_vram_used_max_mb=$([Math]::Round((Max-Or-Zero $vram),1))",
    "nvidia_power_max_w=$([Math]::Round((Max-Or-Zero $power),1))",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- ACTIVE V21.1 PROFILE ---',
    $profile,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- PRODUCER CLOSURE ACTIVATE LAST ---',
    ($closureActivate | Select-Object -Last 32),
    '',
    '--- PRODUCER CLOSURE RELEASE LAST ---',
    ($closureRelease | Select-Object -Last 32),
    '',
    '--- FIFO WATCHED PRODUCER LAST ---',
    ($fifoProducer | Select-Object -Last 32),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 32),
    '',
    '--- PAYLOAD LAST ---',
    ($payload | Select-Object -Last 16),
    '',
    '--- COMPUTE CHAIN LAST ---',
    ($chain | Select-Object -Last 24),
    '',
    '--- DRAW BATCH LAST ---',
    ($drawBatch | Select-Object -Last 24),
    '',
    '--- DUAL QUEUE LAST ---',
    ($dual | Select-Object -Last 32),
    '',
    '--- WAIT FAST LAST ---',
    ($waitFast | Select-Object -Last 24),
    '',
    '--- PERF LAST ---',
    ($perf | Select-Object -Last 40),
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

$files = @($stdout,$stderr,$summary,$gpuLog) |
    Where-Object { Test-Path -LiteralPath $_ }

Compress-Archive `
    -LiteralPath $files `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first payload_avg=$lastPayloadAvg " +
    "chain=$maxChain slow_wait_max_ms=$([Math]::Round((Max-Or-Zero $waited),1))"
)
Write-Host (
    "[$Tag] gpu_avg=$([Math]::Round((Avg-Or-Zero $gpuUtil),1))% " +
    "gpu_max=$([Math]::Round((Max-Or-Zero $gpuUtil),1))% " +
    "vram_max_mb=$([Math]::Round((Max-Or-Zero $vram),1))"
)
Write-Host (
    "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
