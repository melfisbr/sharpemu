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

# Remove diagnostic-only overrides so SetDefault(...,0) keeps normal run lean.
foreach ($name in @(
    'SHARPEMU_PROFILE_RENDER',
    'SHARPEMU_PROFILE_ORDERED_ACTION',
    'SHARPEMU_TRACE_FRAME_STATS',
    'SHARPEMU_TRACE_COMPUTE_PHASES',
    'SHARPEMU_TRACE_DRAW_PHASES',
    'SHARPEMU_TRACE_ORDERED_ACTION_LATENCY',
    'SHARPEMU_TRACE_GPU_SUBMISSION_LATENCY'
)) {
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}

Start-Process -FilePath $exe -ArgumentList @($game)
Write-Host "[$Tag] NORMAL PERFORMANCE LAUNCH started=$exe"
Write-Host "[$Tag] profiling/tracing=normal-default-off"
