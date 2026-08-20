. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot
$last=Join-Path $pkg 'LAST_BACKUP.txt'
if(-not(Test-Path -LiteralPath $last)){
    Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt not found." -ForegroundColor Red
    exit 1
}
$backup=(Get-Content -LiteralPath $last -Raw).Trim()
$overlayWas=$false
$state=Join-Path $pkg 'LAST_OVERLAY_EXISTED.txt'
if(Test-Path -LiteralPath $state){
    $overlayWas=(Get-Content -LiteralPath $state -Raw).Trim() -eq 'True'
}

Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $p.Ime -Force
Copy-Item -LiteralPath (Join-Path $backup 'SdlHostWindow.cs') -Destination $p.Sdl -Force
Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $p.Presenter -Force
Copy-Item -LiteralPath (Join-Path $backup 'HostMovieBridge.cs') -Destination $p.Host -Force
if($overlayWas){
    Copy-Item -LiteralPath (Join-Path $backup 'ImeInWindowOverlay.cs') -Destination $p.ImeOverlay -Force
}else{
    Remove-Item -LiteralPath $p.ImeOverlay -Force -ErrorAction SilentlyContinue
}
Write-Host "$script:Tag ROLLBACK COMPLETED. Backup=$backup" -ForegroundColor Yellow
