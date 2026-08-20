. "$PSScriptRoot\common.ps1"
$p=Paths

try{
    Assert-V740883 $p.Repo
}
catch{
    Write-Host "$script:Tag [ERROR] V74.0.88.3 source baseline is not installed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if(-not(Test-Path -LiteralPath $p.Exe)){
    Write-Host "$script:Tag [ERROR] SharpEmu executable missing: $($p.Exe)" -ForegroundColor Red
    exit 3
}

Write-Host "$script:Tag RepositoryRoot=$($p.Repo)"
Write-Host "$script:Tag HostMovieSHA256=$(Sha $p.Host)"
Write-Host "$script:Tag v88_3_source_baseline=True"
Write-Host "$script:Tag executable_exists=True"
Write-Host "$script:Tag Finding: RUN_5 reached the native SharpEmu launch, so source validation had already passed." -ForegroundColor Cyan
Write-Host "$script:Tag Finding: Windows PowerShell promoted native stderr to NativeCommandError because common.ps1 uses ErrorActionPreference=Stop." -ForegroundColor Cyan
Write-Host "$script:Tag Repair: invoke SharpEmu through cmd.exe with 2>&1 inside cmd, so PowerShell receives one normal stdout stream." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
