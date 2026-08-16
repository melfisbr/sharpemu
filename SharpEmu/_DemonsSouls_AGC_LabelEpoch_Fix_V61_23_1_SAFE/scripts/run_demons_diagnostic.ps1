param(
    [string]$RepositoryRoot,
    [string]$Game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot
$exe = Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Executable not found: $exe" }
if (!(Test-Path -LiteralPath $Game -PathType Leaf)) { throw "Game not found: $Game" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir = Join-Path $root "SharpEmu_V61_23_1_DEMONS_LABEL_EPOCH_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdout = Join-Path $outDir 'stdout.log'
$stderr = Join-Path $outDir 'stderr.log'
$oldEpoch = $env:SHARPEMU_LOG_AGC_EPOCH
$oldAgc = $env:SHARPEMU_LOG_AGC
try {
    # Full packet tracing distorted the V61.22.3 timing. Keep it off and emit
    # only the new epoch marker.
    $env:SHARPEMU_LOG_AGC = '0'
    $env:SHARPEMU_LOG_AGC_EPOCH = '1'
    Write-Host "[V61.23.1] Executable: $exe"
    Write-Host "[V61.23.1] Game:       $Game"
    Write-Host '[V61.23.1] Full AGC packet tracing is disabled.'
    Write-Host '[V61.23.1] Close SharpEmu after the observation is complete.'
    $p = Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $p.WaitForExit()
    $exitCode = $p.ExitCode
} finally {
    $env:SHARPEMU_LOG_AGC_EPOCH = $oldEpoch
    $env:SHARPEMU_LOG_AGC = $oldAgc
}

$err = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
$out = if (Test-Path -LiteralPath $stdout) { [IO.File]::ReadAllText($stdout) } else { '' }
function Count-Text([string]$Needle, [string]$Text) {
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}
$summary = @(
    'SharpEmu V61.23.1 AGC label-epoch diagnostic',
    "timestamp=$stamp",
    "exit_code=$exitCode",
    "main_loop=$(Count-Text 'Starting main loop:' $out)",
    "label_epoch_reset=$(Count-Text 'agc.label_epoch_reset' $err)",
    "wait_label_456CFF580=$(Count-Text '456CFF580' $err)",
    "wait_label_456CFF4C0=$(Count-Text '456CFF4C0' $err)",
    "deadlock_break=$(Count-Text 'deadlock_break' $err)",
    "device_lost_true=$(Count-Text 'deviceLost=True' $err)",
    "audio_zero_pcm=$(Count-Text 'pcm_nonzero=0' $err)"
)
$summary | Set-Content -LiteralPath (Join-Path $outDir 'SUMMARY.txt') -Encoding UTF8
$focus = Select-String -Path $stderr -Pattern 'agc.label_epoch_reset|456CFF580|456CFF4C0|deadlock_break|deviceLost|AJM|pcm_' -CaseSensitive:$false -ErrorAction SilentlyContinue
$focus | ForEach-Object { '{0}:{1}: {2}' -f $_.Path, $_.LineNumber, $_.Line } | Set-Content -LiteralPath (Join-Path $outDir 'FOCUS.txt') -Encoding UTF8
$zip = Join-Path $root "SharpEmu_V61_23_1_DEMONS_LABEL_EPOCH_$stamp.zip"
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force
Write-Host "[V61.23.1] RESULT ZIP: $zip"
Write-Host '[V61.23.1] Send this ZIP in the next message.'
