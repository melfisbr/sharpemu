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
$stdout = Join-Path $Patches ("V76.3.21.2_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.21.2_STDERR_$stamp.log")
$nvidia = Join-Path $Patches ("V76.3.21.2_NVIDIA_$stamp.csv")
$summary = Join-Path $Patches ("V76.3.21.2_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.21.2_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

"sample,time,gpu_util_pct,vram_used_mb,power_w" |
    Set-Content -LiteralPath $nvidia -Encoding UTF8

$sample = 0
$nextNvidia = Get-Date
$main = $false
$first = $false
$deadline = $start.AddSeconds(180)

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

    if ((Get-Date) -ge $nextNvidia) {
        $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($smi) {
            try {
                $row = & $smi.Source `
                    --query-gpu=utilization.gpu,memory.used,power.draw `
                    --format=csv,noheader,nounits 2>$null |
                    Select-Object -First 1
                if ($row) {
                    "$sample,$((Get-Date).ToString('o')),$row" |
                        Add-Content -LiteralPath $nvidia -Encoding UTF8
                }
            }
            catch {}
        }
        $sample++
        $nextNvidia = (Get-Date).AddSeconds(5)
    }
}

$exitCode = ''
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}
else {
    try {
        $p.WaitForExit()
        $exitCode = $p.ExitCode
    }
    catch {}
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
    $_ -match '\[V76\.3\.21\.2\]\[GLOBAL_SNAPSHOT_BOUNDS\]'
})
$repair = @($err | Where-Object {
    $_ -match '\[V76\.3\.21\.2\]\[GLOBAL_SNAPSHOT_REPAIR\]'
})
$presenterFailed = @($err | Where-Object {
    $_ -match '\[LOADER\]\[ERROR\] Vulkan VideoOut presenter failed:'
})
$argRange = @($err | Where-Object {
    $_ -match 'ArgumentOutOfRangeException'
})
$windowUnexpected = @($err | Where-Object {
    $_ -match 'Vulkan VideoOut window closing; requested=False'
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
$perf = @($err | Where-Object {
    $_ -match '\[PERF\]\[RENDER\]'
})
$payload = @($err | Where-Object {
    $_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'
})
$slow = @($err | Where-Object {
    $_ -match 'SLOW_WAIT_PRODUCER'
})
$residency = @($err | Where-Object {
    $_ -match 'SHADER_GLOBAL_RESIDENCY'
})

$gpuValues = @()
$vramValues = @()
$powerValues = @()

if (Test-Path -LiteralPath $nvidia) {
    foreach ($line in @(Get-Content -LiteralPath $nvidia | Select-Object -Skip 1)) {
        $parts = $line -split ','
        if ($parts.Count -ge 5) {
            $g = 0.0
            $v = 0.0
            $w = 0.0
            if ([double]::TryParse(
                    $parts[2].Trim(),
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$g)) {
                $gpuValues += $g
            }
            if ([double]::TryParse(
                    $parts[3].Trim(),
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$v)) {
                $vramValues += $v
            }
            if ([double]::TryParse(
                    $parts[4].Trim(),
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$w)) {
                $powerValues += $w
            }
        }
    }
}

$gpuAvg = if ($gpuValues.Count) {
    [Math]::Round(($gpuValues | Measure-Object -Average).Average, 2)
} else { 0 }
$gpuMax = if ($gpuValues.Count) {
    [Math]::Round(($gpuValues | Measure-Object -Maximum).Maximum, 2)
} else { 0 }
$vramMax = if ($vramValues.Count) {
    [Math]::Round(($vramValues | Measure-Object -Maximum).Maximum, 1)
} else { 0 }
$powerMax = if ($powerValues.Count) {
    [Math]::Round(($powerValues | Measure-Object -Maximum).Maximum, 2)
} else { 0 }

@(
    'tag=V76.3.21.2-GLOBAL-SNAPSHOT-BOUNDS-LOADING-CRASH-RECOVERY',
    "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
    "exit_code=$exitCode",
    "main_loop_detected=$main",
    "first_frame_detected=$first",
    "global_snapshot_repair_lines=$($repair.Count)",
    "presenter_failed_markers=$($presenterFailed.Count)",
    "argument_out_of_range_markers=$($argRange.Count)",
    "unexpected_window_close_markers=$($windowUnexpected.Count)",
    "device_lost_markers=$($device.Count)",
    "access_violation_markers=$($av.Count)",
    "fatal_markers=$($fatal.Count)",
    "nvidia_samples=$($gpuValues.Count)",
    "nvidia_gpu_util_avg=$gpuAvg",
    "nvidia_gpu_util_max=$gpuMax",
    "nvidia_vram_used_max_mb=$vramMax",
    "nvidia_power_max_w=$powerMax",
    '',
    '--- ACTIVE V21.2 PROFILE ---',
    $profile,
    '',
    '--- BOOT ---',
    $timeline,
    '',
    '--- GLOBAL SNAPSHOT REPAIR LAST ---',
    ($repair | Select-Object -Last 64),
    '',
    '--- PRESENTER FAILED ---',
    $presenterFailed,
    '',
    '--- ARGUMENT OUT OF RANGE ---',
    $argRange,
    '',
    '--- PAYLOAD LAST ---',
    ($payload | Select-Object -Last 16),
    '',
    '--- RESIDENCY LAST ---',
    ($residency | Select-Object -Last 16),
    '',
    '--- SLOW WAIT LAST ---',
    ($slow | Select-Object -Last 16),
    '',
    '--- PERF LAST ---',
    ($perf | Select-Object -Last 32),
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

$files = @($stdout,$stderr,$nvidia,$summary) |
    Where-Object { Test-Path -LiteralPath $_ }

Compress-Archive `
    -LiteralPath $files `
    -DestinationPath $result `
    -CompressionLevel Optimal `
    -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE"
Write-Host (
    "[$Tag] main=$main first=$first repairs=$($repair.Count) " +
    "presenter_failed=$($presenterFailed.Count) arg_range=$($argRange.Count)"
)
Write-Host (
    "[$Tag] gpu_avg=$gpuAvg gpu_max=$gpuMax vram_max_mb=$vramMax " +
    "device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
)
Write-Host "[$Tag] result=$result"
