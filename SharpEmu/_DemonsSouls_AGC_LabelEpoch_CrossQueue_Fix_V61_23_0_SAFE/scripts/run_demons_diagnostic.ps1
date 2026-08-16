param(
 [string]$RepositoryRoot,
 [string]$Game='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$exe=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Executable not found: $exe" }
if (!(Test-Path -LiteralPath $Game)) { throw "Game not found: $Game" }
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir=Join-Path $root "SharpEmu_V61_23_0_DEMONS_LABEL_EPOCH_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout=Join-Path $outDir 'stdout.log'; $stderr=Join-Path $outDir 'stderr.log'
$oldEpoch=$env:SHARPEMU_LOG_AGC_EPOCH
$oldAgc=$env:SHARPEMU_LOG_AGC
try {
    # Keep full AGC packet tracing OFF: V61.22.3 proved it perturbs timing heavily.
    $env:SHARPEMU_LOG_AGC='0'
    $env:SHARPEMU_LOG_AGC_EPOCH='1'
    Write-Host "[V61.23.0] Executable: $exe"
    Write-Host "[V61.23.0] Game:       $Game"
    Write-Host '[V61.23.0] Full AGC tracing is disabled for this performance-valid run.'
    Write-Host '[V61.23.0] Close SharpEmu after the observation is complete.'
    $p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $p.WaitForExit()
    $exitCode=$p.ExitCode
} finally {
    $env:SHARPEMU_LOG_AGC_EPOCH=$oldEpoch
    $env:SHARPEMU_LOG_AGC=$oldAgc
}
$err= if(Test-Path $stderr){[IO.File]::ReadAllText($stderr)}else{''}
$out= if(Test-Path $stdout){[IO.File]::ReadAllText($stdout)}else{''}
function C([string]$needle,[string]$text){ ([regex]::Matches($text,[regex]::Escape($needle))).Count }
$summary=@(
 'SharpEmu V61.23.0 AGC label-epoch diagnostic',
 "timestamp=$stamp",
 "exit_code=$exitCode",
 "main_loop=$(C 'Starting main loop:' $out)",
 "label_epoch_reset=$(C 'agc.label_epoch_reset' $err)",
 "wait_suspended=$(C 'agc.wait_suspended' $err)",
 "wait_label_456CFF580=$(C '456CFF580' $err)",
 "wait_label_456CFF4C0=$(C '456CFF4C0' $err)",
 "deadlock_break=$(C 'deadlock_break' $err)",
 "device_lost_true=$(C 'deviceLost=True' $err)",
 "audio_zero_pcm=$(C 'pcm_nonzero=0' $err)"
)
$summary | Set-Content -LiteralPath (Join-Path $outDir 'SUMMARY.txt') -Encoding UTF8
$focus=Select-String -Path $stderr -Pattern 'agc.label_epoch_reset|agc.wait_suspended|456CFF580|456CFF4C0|deadlock_break|deviceLost|AJM|pcm_' -CaseSensitive:$false -ErrorAction SilentlyContinue
$focus | ForEach-Object { "{0}:{1}: {2}" -f $_.Path,$_.LineNumber,$_.Line } | Set-Content -LiteralPath (Join-Path $outDir 'FOCUS.txt') -Encoding UTF8
$zip=Join-Path $root "SharpEmu_V61_23_0_DEMONS_LABEL_EPOCH_$stamp.zip"
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force
Write-Host "[V61.23.0] RESULT ZIP: $zip"
Write-Host '[V61.23.0] Send this ZIP in the next message.'
