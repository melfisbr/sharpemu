. "$PSScriptRoot\common.ps1"
$p=Paths
$patches=Patches

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$log=Join-Path $patches ('SharpEmu_V74_0_88_4_RUNNER_REBUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build $p.Cli -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $log
$code=$LASTEXITCODE

if($code -ne 0){
    Write-Host "$script:Tag [ERROR] BUILD FAILED. No source files were changed by V74.0.88.4." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag NO SOURCE CHANGES REQUIRED." -ForegroundColor Cyan
Write-Host "$script:Tag REBUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
