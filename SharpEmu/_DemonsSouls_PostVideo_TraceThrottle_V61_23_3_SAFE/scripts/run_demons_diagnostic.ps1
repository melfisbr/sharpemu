param(
    [string]$RepositoryRoot,
    [string]$Game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

$exe = Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Executable missing: $exe" }
if (!(Test-Path -LiteralPath $Game)) { throw "Game missing: $Game" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root "SharpEmu_V61_23_3_DEMONS_REALTIME_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout = Join-Path $out 'stdout.log'
$stderr = Join-Path $out 'stderr.log'
$telemetry = Join-Path $out 'PROCESS_TELEMETRY.csv'

# V61.23.2 generated >110 MB of stderr and drove the game to ~0.1 FPS.
# Explicitly neutralize all high-frequency tracing inherited from any shell.
$env:SHARPEMU_LOG_AGC = $null
$env:SHARPEMU_LOG_AGC_SHADER = $null
$env:SHARPEMU_LOG_VK_RESOURCES = $null
$env:SHARPEMU_LOG_AGC_EPOCH = $null
$env:SHARPEMU_TRACE_GUEST_IMAGES = $null
$env:SHARPEMU_VK_VALIDATION = $null
$env:SHARPEMU_VK_DEBUG_LABELS = $null

'elapsed_s,cpu_s,working_set_mb,private_mb,threads,responding' |
    Set-Content -LiteralPath $telemetry -Encoding ASCII

Write-Host "[V61.23.3] Executable: $exe"
Write-Host "[V61.23.3] Game:       $Game"
Write-Host '[V61.23.3] Full AGC/Shader/Vulkan-resource tracing: OFF'
Write-Host '[V61.23.3] Observe whether the Sony Interactive Entertainment screen now advances at normal speed.'
Write-Host '[V61.23.3] Close the SharpEmu window after the observation.'

$p = Start-Process -FilePath $exe -ArgumentList @($Game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$sw = [Diagnostics.Stopwatch]::StartNew()
while (!$p.HasExited) {
    Start-Sleep -Seconds 5
    try {
        $p.Refresh()
        $elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        $cpu = [Math]::Round($p.TotalProcessorTime.TotalSeconds, 2)
        $ws = [Math]::Round($p.WorkingSet64 / 1MB, 1)
        $priv = [Math]::Round($p.PrivateMemorySize64 / 1MB, 1)
        $threads = $p.Threads.Count
        $responding = $p.Responding
        "$elapsed,$cpu,$ws,$priv,$threads,$responding" |
            Add-Content -LiteralPath $telemetry -Encoding ASCII
    }
    catch {
        if (!$p.HasExited) {
            "telemetry_error=$($_.Exception.Message)" |
                Add-Content -LiteralPath (Join-Path $out 'TELEMETRY_ERRORS.txt')
        }
    }
}
$sw.Stop()
$exitCode = $p.ExitCode

$errText = if (Test-Path -LiteralPath $stderr) {
    [IO.File]::ReadAllText($stderr)
} else { '' }

$outText = if (Test-Path -LiteralPath $stdout) {
    [IO.File]::ReadAllText($stdout)
} else { '' }

$combined = $outText + "`n" + $errText
$summary = @(
    'version=61.23.3',
    "exit_code=$exitCode",
    "runtime_seconds=$([Math]::Round($sw.Elapsed.TotalSeconds,1))",
    "stderr_bytes=$((Get-Item -LiteralPath $stderr).Length)",
    "bink_completed=$(([regex]::Matches($combined,'Bink2 bridge completed:')).Count)",
    "direct_boot_completed=$([int]$combined.Contains('bink2.direct_boot_completed'))",
    "guest_frame=$([int]$combined.Contains('Vulkan VideoOut presented guest frame'))",
    "device_lost=$([int]$combined.Contains('deviceLost=True'))",
    "wait_suspended=$(([regex]::Matches($combined,'agc.wait_suspended')).Count)",
    "queue_resumed=$(([regex]::Matches($combined,'agc.queue_resumed')).Count)",
    "full_agc_trace=0"
)
$summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$focusPattern = 'Bink2 bridge completed|direct_boot_completed|presented guest frame|deviceLost|Host shutdown|Starting main loop|ResourcePool'
($combined -split "`r?`n") |
    Select-String -Pattern $focusPattern |
    ForEach-Object { $_.Line } |
    Set-Content -LiteralPath (Join-Path $out 'FOCUS.txt') -Encoding UTF8

$zip = "$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.23.3] RESULT: $zip"
