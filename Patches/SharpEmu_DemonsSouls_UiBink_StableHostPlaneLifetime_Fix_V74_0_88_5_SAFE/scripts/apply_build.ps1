. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot
$patches=Patches

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if($pre -ne 0 -and $pre -ne 10){exit $pre}

$backup=$null
if($pre -ne 10){
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $backup=Join-Path $p.Repo ('.sharpemu-hotfix-backup\StableHostMoviePlaneLifetimeV740885_'+$stamp)
    New-Item -ItemType Directory -Force $backup|Out-Null
    Copy-Item -LiteralPath $p.Presenter -Destination (Join-Path $backup 'VulkanVideoPresenter.cs') -Force
    Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value $backup -Encoding UTF8

    try{
        $presenter=NL([IO.File]::ReadAllText($p.Presenter))
        $presenter=Apply-StableHostMoviePlaneLifetimeV740885 $presenter
        $presenter=Apply-HostMovieUploadTraceV740885 $presenter
        WritePreserving $p.Presenter $presenter
        Assert-V740885 $p.Repo

        Write-Host "$script:Tag SOURCE PATCH APPLIED." -ForegroundColor Green
        Write-Host "$script:Tag PresenterPostSHA256=$(Sha $p.Presenter)"
        Write-Host "$script:Tag Backup=$backup"
    }
    catch{
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
        Write-Host "$script:Tag [ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$script:Tag SAFE rollback completed." -ForegroundColor Yellow
        exit 1
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue

$log=Join-Path $patches ('SharpEmu_V74_0_88_5_STABLE_HOST_PLANE_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build $p.Cli -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE

if($code -ne 0){
    if($backup){
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
    }
    Write-Host "$script:Tag [ERROR] BUILD FAILED; SAFE rollback completed." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
