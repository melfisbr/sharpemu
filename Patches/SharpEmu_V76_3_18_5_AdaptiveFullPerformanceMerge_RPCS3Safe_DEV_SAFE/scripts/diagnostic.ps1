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

# Diagnostics override SetDefault() traces only.
$env:SHARPEMU_PROFILE_RENDER = '1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION = '1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S = '5'
$env:SHARPEMU_TRACE_FRAME_STATS = '1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.18.5_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.18.5_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.18.5_SUMMARY_$stamp.txt")
$gpuCsv = Join-Path $Patches ("V76.3.18.5_NVIDIA_GPU_$stamp.csv")
$result = Join-Path $Patches ("V76.3.18.5_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

# Optional 2-second NVIDIA telemetry. It is diagnostic only.
$gpuJob = $null
$nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $nvidia) {
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
}
if ($nvidia) {
    "timestamp,gpu_util_percent,memory_util_percent,memory_used_mb,memory_total_mb" |
        Set-Content -LiteralPath $gpuCsv -Encoding ASCII

    $gpuJob = Start-Job `
        -ArgumentList @($nvidia.Source, $gpuCsv, $p.Id) `
        -ScriptBlock {
            param($NvidiaPath, $CsvPath, $PidToWatch)

            while (Get-Process -Id $PidToWatch -ErrorAction SilentlyContinue) {
                try {
                    $line = & $NvidiaPath `
                        --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total `
                        --format=csv,noheader,nounits 2>$null |
                        Select-Object -First 1

                    if ($line) {
                        Add-Content -LiteralPath $CsvPath -Value $line -Encoding ASCII
                    }
                } catch {}

                Start-Sleep -Seconds 2
            }
        }
}

$main = $false
$first = $false
$deadline = $start.AddSeconds(230)

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

    if ($main -and $first -and (Get-Date) -gt $start.AddSeconds(200)) {
        break
    }
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

if ($gpuJob) {
    Stop-Job $gpuJob -ErrorAction SilentlyContinue | Out-Null
    Receive-Job $gpuJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $gpuJob -Force -ErrorAction SilentlyContinue
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

$profile = @($err | Where-Object {
    $_ -match '\[V76\.3\.18\.5\]\[ADAPTIVE_FULL_MERGE\]'
})

$dual = @($err | Where-Object {
    $_ -match '\[V74\.0\.113\.1\]\[(DUAL_PHYSICAL_QUEUE|DUAL_PHYSICAL_QUEUE_READY|DUAL_QUEUE_SUBMIT|DUAL_QUEUE_PRESENT_JOIN)\]'
})

$dualEnabled = @($dual | Where-Object {
    $_ -match 'DUAL_PHYSICAL_QUEUE\]' -and $_ -match 'enabled=1'
}).Count -gt 0

$gfxSubmit = 0L
$computeSubmit = 0L
foreach ($line in $dual) {
    $lane = [regex]::Match($line, 'lane=(graphics|compute)')
    $count = [regex]::Match($line, 'lane_count=(\d+)')
    if ($lane.Success -and $count.Success) {
        $v = [long]$count.Groups[1].Value
        if ($lane.Groups[1].Value -eq 'graphics') {
            if ($v -gt $gfxSubmit) { $gfxSubmit = $v }
        } else {
            if ($v -gt $computeSubmit) { $computeSubmit = $v }
        }
    }
}

$cp = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP\]'
})
$cpFault = @($err | Where-Object {
    $_ -match '\[V76\.3\.17\.0\]\[AGC_ASYNC_CP_FAULT\]'
})

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

$payload = @($err | Where-Object {
    $_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'
})
$lastPayloadAvg = ''
if ($payload.Count -gt 0) {
    $m = [regex]::Match($payload[-1], 'avg=([0-9]+(?:[.,][0-9]+)?)')
    if ($m.Success) { $lastPayloadAvg = $m.Groups[1].Value }
}

$residency = @($err | Where-Object {
    $_ -match '\[V74\.0\.117\.13\]\[SHADER_GLOBAL_RESIDENCY\]'
})
$lastResidency = $residency | Select-Object -Last 1

$descriptor = @($err | Where-Object {
    $_ -match '\[V74\.0\.117\.16\]\[DESCRIPTOR_SET_CACHE\]'
})
$residentShader = @($err | Where-Object {
    $_ -match '\[V74\.0\.118\.0\]\[RESIDENT_SHADER\]'
})

$waitFast = @($err | Where-Object {
    $_ -match 'WAIT_REGISTRY_FAST_ONLY|WAIT_REGISTRY_FAST_DRAIN'
})
$waitDrain = @($err | Where-Object {
    $_ -match '\[V74\.0\.71\]\[DEDICATED_WAIT_DRAIN\]'
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

$gpuLines = if (Test-Path -LiteralPath $gpuCsv) {
    @(Get-Content -LiteralPath $gpuCsv | Select-Object -Skip 1)
} else { @() }

$gpuUtilValues = New-Object System.Collections.Generic.List[int]
$gpuMemValues = New-Object System.Collections.Generic.List[int]

foreach ($line in $gpuLines) {
    $parts = $line -split ','
    if ($parts.Count -ge 5) {
        $gpuText = $parts[1].Trim()
        $memText = $parts[3].Trim()
        $gpuValue = 0
        $memValue = 0

        if ([int]::TryParse($gpuText, [ref]$gpuValue)) {
            $gpuUtilValues.Add($gpuValue)
        }
        if ([int]::TryParse($memText, [ref]$memValue)) {
            $gpuMemValues.Add($memValue)
        }
    }
}

$gpuAvg = 0.0
$gpuMax = 0
$gpuMemMax = 0
if ($gpuUtilValues.Count -gt 0) {
    $gpuAvg = ($gpuUtilValues | Measure-Object -Average).Average
    $gpuMax = ($gpuUtilValues | Measure-Object -Maximum).Maximum
}
if ($gpuMemValues.Count -gt 0) {
    $gpuMemMax = ($gpuMemValues | Measure-Object -Maximum).Maximum
}

@(
    'tag=V76.3.18.5-ADAPTIVE-FULL-PERFORMANCE-MERGE',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "dual_physical_enabled=$dualEnabled",
    "dual_graphics_submit_max=$gfxSubmit",
    "dual_compute_submit_max=$computeSubmit",
    "max_compute_in_batch=$maxChain",
    "payload_batch_last_avg=$lastPayloadAvg",
    "async_cp_faults=$($cpFault.Count)",
    "global_residency_samples=$($residency.Count)",
    "descriptor_cache_samples=$($descriptor.Count)",
    "resident_shader_samples=$($residentShader.Count)",
    "slow_wait_lines=$($slow.Count)",
    "nvidia_samples=$($gpuUtilValues.Count)",
    "nvidia_gpu_util_avg=$([Math]::Round($gpuAvg,2))",
    "nvidia_gpu_util_max=$gpuMax",
    "nvidia_vram_used_max_mb=$gpuMemMax",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    '',
    '--- ACTIVE V18.5 PROFILE ---',
    $profile,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- DUAL QUEUE LAST ---',
    ($dual | Select-Object -Last 64),
    '',
    '--- ASYNC AGC LAST ---',
    ($cp | Select-Object -Last 24),
    '',
    '--- COMPUTE CHAIN LAST ---',
    ($chain | Select-Object -Last 24),
    '',
    '--- PAYLOAD LAST ---',
    ($payload | Select-Object -Last 16),
    '',
    '--- GLOBAL RESIDENCY LAST ---',
    ($residency | Select-Object -Last 16),
    '',
    '--- DESCRIPTOR CACHE LAST ---',
    ($descriptor | Select-Object -Last 8),
    '',
    '--- RESIDENT SHADER LAST ---',
    ($residentShader | Select-Object -Last 8),
    '',
    '--- WAIT FAST LAST ---',
    ($waitFast | Select-Object -Last 16),
    '',
    '--- WAIT DRAIN LAST ---',
    ($waitDrain | Select-Object -Last 16),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 24),
    '',
    '--- PERF LAST ---',
    ($perf | Select-Object -Last 32),
    '',
    '--- NVIDIA LAST ---',
    ($gpuLines | Select-Object -Last 20),
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
    "[$Tag] main=$main first=$first dual=$dualEnabled " +
    "gfx=$gfxSubmit compute=$computeSubmit chain=$maxChain avg=$lastPayloadAvg"
)
Write-Host (
    "[$Tag] nvidia_avg=$([Math]::Round($gpuAvg,2))% " +
    "nvidia_max=$gpuMax% vram_max_mb=$gpuMemMax"
)
Write-Host (
    "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
