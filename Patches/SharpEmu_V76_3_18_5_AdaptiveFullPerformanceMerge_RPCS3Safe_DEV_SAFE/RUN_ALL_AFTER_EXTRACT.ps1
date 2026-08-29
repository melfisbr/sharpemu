$ErrorActionPreference = 'Stop'
$Pkg = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Pkg

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$steps = @(
    'RUN_1_VALIDATE_PACKAGE.cmd',
    'RUN_2_PRECHECK.cmd',
    'RUN_3_APPLY_BUILD.cmd',
    'RUN_4_DIAGNOSTIC.cmd'
)

foreach ($step in $steps) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host " $step" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    & (Join-Path $Pkg $step)
    if ($LASTEXITCODE -ne 0) {
        throw "$step falhou"
    }
}

Write-Host ""
Write-Host "V76.3.18.5 FULL MERGE + DIAGNOSTIC CONCLUIDO" -ForegroundColor Green
