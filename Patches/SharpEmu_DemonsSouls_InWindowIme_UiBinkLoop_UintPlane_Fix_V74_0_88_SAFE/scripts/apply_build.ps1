. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot
$patches=Patches

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if($pre -ne 0 -and $pre -ne 10){exit $pre}

$backup=$null
$overlayExisted=$false
if($pre -ne 10){
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $backup=Join-Path $p.Repo ('.sharpemu-hotfix-backup\DemonSoulsInWindowImeUiBinkV74088_'+$stamp)
    New-Item -ItemType Directory -Force $backup|Out-Null

    Copy-Item -LiteralPath $p.Ime -Destination (Join-Path $backup 'ImeDialogExports.cs') -Force
    Copy-Item -LiteralPath $p.Sdl -Destination (Join-Path $backup 'SdlHostWindow.cs') -Force
    Copy-Item -LiteralPath $p.Presenter -Destination (Join-Path $backup 'VulkanVideoPresenter.cs') -Force
    Copy-Item -LiteralPath $p.Host -Destination (Join-Path $backup 'HostMovieBridge.cs') -Force
    if(Test-Path -LiteralPath $p.ImeOverlay){
        $overlayExisted=$true
        Copy-Item -LiteralPath $p.ImeOverlay -Destination (Join-Path $backup 'ImeInWindowOverlay.cs') -Force
    }

    Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value $backup -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $pkg 'LAST_OVERLAY_EXISTED.txt') -Value $overlayExisted -Encoding ASCII

    try{
        Copy-Item -LiteralPath (Join-Path $pkg 'payload\ImeDialogExports.cs') -Destination $p.Ime -Force
        Copy-Item -LiteralPath (Join-Path $pkg 'payload\ImeInWindowOverlay.cs') -Destination $p.ImeOverlay -Force

        $sdl=NL([IO.File]::ReadAllText($p.Sdl))
        $presenter=NL([IO.File]::ReadAllText($p.Presenter))
        $host=NL([IO.File]::ReadAllText($p.Host))

        $sdl=Apply-SdlV74088 $sdl
        $presenter=Apply-PresenterV74088 $presenter
        $host=Apply-HostMovieV74088 $host

        WritePreserving $p.Sdl $sdl
        WritePreserving $p.Presenter $presenter
        WritePreserving $p.Host $host

        Assert-V74088 $p.Repo

        Write-Host "$script:Tag SOURCE PATCH APPLIED." -ForegroundColor Green
        Write-Host "$script:Tag ImePostSHA256=$(Sha $p.Ime)"
        Write-Host "$script:Tag ImeOverlaySHA256=$(Sha $p.ImeOverlay)"
        Write-Host "$script:Tag SdlPostSHA256=$(Sha $p.Sdl)"
        Write-Host "$script:Tag PresenterPostSHA256=$(Sha $p.Presenter)"
        Write-Host "$script:Tag HostMoviePostSHA256=$(Sha $p.Host)"
        Write-Host "$script:Tag Backup=$backup"
    }
    catch{
        Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $p.Ime -Force
        Copy-Item -LiteralPath (Join-Path $backup 'SdlHostWindow.cs') -Destination $p.Sdl -Force
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
        Copy-Item -LiteralPath (Join-Path $backup 'HostMovieBridge.cs') -Destination $p.Host -Force
        if($overlayExisted){
            Copy-Item -LiteralPath (Join-Path $backup 'ImeInWindowOverlay.cs') -Destination $p.ImeOverlay -Force
        }else{
            Remove-Item -LiteralPath $p.ImeOverlay -Force -ErrorAction SilentlyContinue
        }
        Write-Host "$script:Tag [ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$script:Tag SAFE rollback completed." -ForegroundColor Yellow
        exit 1
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ('SharpEmu_V74_0_88_INWINDOW_IME_UI_BINK_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')

& dotnet build $p.Cli -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE
if($code -ne 0){
    if($backup){
        $overlayWas=(Get-Content -LiteralPath (Join-Path $pkg 'LAST_OVERLAY_EXISTED.txt') -Raw).Trim() -eq 'True'
        Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $p.Ime -Force
        Copy-Item -LiteralPath (Join-Path $backup 'SdlHostWindow.cs') -Destination $p.Sdl -Force
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
        Copy-Item -LiteralPath (Join-Path $backup 'HostMovieBridge.cs') -Destination $p.Host -Force
        if($overlayWas){
            Copy-Item -LiteralPath (Join-Path $backup 'ImeInWindowOverlay.cs') -Destination $p.ImeOverlay -Force
        }else{
            Remove-Item -LiteralPath $p.ImeOverlay -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "$script:Tag [ERROR] BUILD FAILED; SAFE rollback completed." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
