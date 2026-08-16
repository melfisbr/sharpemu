param(
    [string]$RepositoryRoot,
    [string]$Game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$source = [IO.File]::ReadAllText($target)
if ($source.Contains('V61.23.1 label generation reset') -or
    $source.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'DIAGNOSTIC ERROR: eager epoch deletion still active. Run APPLY_BUILD V61.23.5.'
}

$exe = Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Executable missing: $exe" }
if (!(Test-Path -LiteralPath $Game)) { throw "Game missing: $Game" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root "SharpEmu_V61_23_5_DEMONS_REALTIME_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout = Join-Path $out 'stdout.log'
$stderr = Join-Path $out 'stderr.log'
$telemetry = Join-Path $out 'PROCESS_TELEMETRY.csv'

# High-frequency tracing was proven to perturb runtime severely (~0.1 FPS,
# >110 MB stderr in V61.23.2). Keep the observation representative.
$env:SHARPEMU_LOG_AGC = $null
$env:SHARPEMU_LOG_AGC_SHADER = $null
$env:SHARPEMU_LOG_VK_RESOURCES = $null
$env:SHARPEMU_LOG_AGC_EPOCH = $null
$env:SHARPEMU_TRACE_GUEST_IMAGES = $null
$env:SHARPEMU_VK_VALIDATION = $null
$env:SHARPEMU_VK_DEBUG_LABELS = $null

'elapsed_s,cpu_s,working_set_mb,private_mb,threads,responding' |
    Set-Content -LiteralPath $telemetry -Encoding ASCII

Write-Host "[V61.23.5] Executable: $exe"
Write-Host "[V61.23.5] Game:       $Game"
Write-Host '[V61.23.5] High-frequency AGC/Shader/Vulkan tracing: OFF'
Write-Host '[V61.23.5] Keep the game open past the second video / Sony presents screen.'
Write-Host '[V61.23.5] Close SharpEmu after observing progress.'

$p = Start-Process -FilePath $exe -ArgumentList @($Game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$sw = [Diagnostics.Stopwatch]::StartNew()
while (!$p.HasExited) {
    Start-Sleep -Seconds 5
    try {
        $p.Refresh()
        "$([Math]::Round($sw.Elapsed.TotalSeconds,1)),$([Math]::Round($p.TotalProcessorTime.TotalSeconds,2)),$([Math]::Round($p.WorkingSet64/1MB,1)),$([Math]::Round($p.PrivateMemorySize64/1MB,1)),$($p.Threads.Count),$($p.Responding)" |
            Add-Content -LiteralPath $telemetry -Encoding ASCII
    } catch {}
}
$sw.Stop()
$exitCode = $p.ExitCode

$outText = if (Test-Path -LiteralPath $stdout) { [IO.File]::ReadAllText($stdout) } else { '' }
$errText = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
$combined = $outText + "`n" + $errText
$stderrBytes = if (Test-Path -LiteralPath $stderr) { (Get-Item -LiteralPath $stderr).Length } else { 0 }

@(
    'version=61.23.5',
    "exit_code=$exitCode",
    "runtime_seconds=$([Math]::Round($sw.Elapsed.TotalSeconds,1))",
    "stderr_bytes=$stderrBytes",
    "bink_completed=$(([regex]::Matches($combined,'Bink2 bridge completed:')).Count)",
    "direct_boot_completed=$([int]$combined.Contains('bink2.direct_boot_completed'))",
    "guest_frame=$([int]$combined.Contains('Vulkan VideoOut presented guest frame'))",
    "device_lost=$([int]$combined.Contains('deviceLost=True'))",
    "epoch_reset=$(([regex]::Matches($combined,'agc.label_epoch_reset')).Count)",
    'full_agc_trace=0'
) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

$focusPattern = 'Starting main loop|ResourcePool|Bink2 bridge completed|direct_boot_completed|presented guest frame|deviceLost|Host shutdown|VideoOut window closing|pipeline cache saved'
($combined -split "`r?`n") |
    Select-String -Pattern $focusPattern |
    ForEach-Object { $_.Line } |
    Set-Content -LiteralPath (Join-Path $out 'FOCUS.txt') -Encoding UTF8

$zip = "$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.23.5] RESULT: $zip"
