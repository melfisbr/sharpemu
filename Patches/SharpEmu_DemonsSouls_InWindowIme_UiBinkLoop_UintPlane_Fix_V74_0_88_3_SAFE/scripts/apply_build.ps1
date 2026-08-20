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
    $backup=Join-Path $p.Repo ('.sharpemu-hotfix-backup\PostIntroLoopScopeV740883_'+$stamp)
    New-Item -ItemType Directory -Force $backup|Out-Null
    Copy-Item -LiteralPath $p.Host -Destination (Join-Path $backup 'HostMovieBridge.cs') -Force
    Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value $backup -Encoding UTF8

    try{
        $hostMovieText=NL([IO.File]::ReadAllText($p.Host))
        $hostMovieText=Apply-PostIntroLoopScopeV740883 $hostMovieText
        WritePreserving $p.Host $hostMovieText
        Assert-V740883 $p.Repo

        Write-Host "$script:Tag SOURCE PATCH APPLIED." -ForegroundColor Green
        Write-Host "$script:Tag HostMoviePostSHA256=$(Sha $p.Host)"
        Write-Host "$script:Tag Backup=$backup"
    }
    catch{
        Copy-Item -LiteralPath (Join-Path $backup 'HostMovieBridge.cs') -Destination $p.Host -Force
        Write-Host "$script:Tag [ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$script:Tag SAFE rollback completed." -ForegroundColor Yellow
        exit 1
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue

$log=Join-Path $patches ('SharpEmu_V74_0_88_3_POST_INTRO_LOOP_SCOPE_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build $p.Cli -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE

if($code -ne 0){
    if($backup){
        Copy-Item -LiteralPath (Join-Path $backup 'HostMovieBridge.cs') -Destination $p.Host -Force
    }
    Write-Host "$script:Tag [ERROR] BUILD FAILED; SAFE rollback completed." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
