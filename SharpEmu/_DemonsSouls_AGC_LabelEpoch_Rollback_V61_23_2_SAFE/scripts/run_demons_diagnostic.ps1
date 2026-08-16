param([string]$RepositoryRoot,[string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$exe=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Executable missing: $exe" }
if (!(Test-Path -LiteralPath $Game)) { throw "Game missing: $Game" }
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root "SharpEmu_V61_23_2_DEMONS_POSTVIDEO_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout=Join-Path $out 'stdout.log'; $stderr=Join-Path $out 'stderr.log'

$env:SHARPEMU_LOG_AGC_EPOCH=$null
$env:SHARPEMU_LOG_AGC='1'
$env:SHARPEMU_LOG_AGC_SHADER='1'
$env:SHARPEMU_LOG_VK_RESOURCES='1'
$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
$exit=$p.ExitCode

$all=''
if (Test-Path $stderr) { $all += [IO.File]::ReadAllText($stderr) }
$focus=Join-Path $out 'FOCUS.txt'
$patterns='Bink2 bridge completed|direct_boot_completed|presented guest frame|agc.wait_suspended|agc.wait_producer|queue_resumed|dispatch_noop|agc.rt_sampled|deviceLost|Host shutdown|ordered_action_fence_wait'
$selected=($all -split "`r?`n") | Select-String -Pattern $patterns
$selected | ForEach-Object { $_.Line } | Set-Content -LiteralPath $focus -Encoding UTF8

$summary=@(
 "version=61.23.2",
 "exit_code=$exit",
 "bink_completed=$(([regex]::Matches($all,'Bink2 bridge completed:')).Count)",
 "direct_boot_completed=$([int]$all.Contains('bink2.direct_boot_completed'))",
 "guest_frame=$([int]$all.Contains('Vulkan VideoOut presented guest frame'))",
 "wait_suspended=$(([regex]::Matches($all,'agc.wait_suspended')).Count)",
 "queue_resumed=$(([regex]::Matches($all,'queue_resumed')).Count)",
 "dispatch_noop=$(([regex]::Matches($all,'agc.dispatch_noop')).Count)",
 "rt_sampled=$(([regex]::Matches($all,'agc.rt_sampled')).Count)",
 "device_lost=$([int]$all.Contains('deviceLost=True'))"
)
$summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.23.2] RESULT: $zip"
