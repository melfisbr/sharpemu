. "$PSScriptRoot\common.ps1"

$pkg=PackageRoot
$repo=RepoRoot
$patches=Patches
$ime=ImeDialogSource
$presenter=PresenterSource

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE

if($pre -ne 0 -and $pre -ne 10){
    exit $pre
}

$backup=$null

if($pre -ne 10){
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $backup=Join-Path $repo ('.sharpemu-hotfix-backup\CharacterCreatorUiImeCompositeV7408615_'+$stamp)

    New-Item -ItemType Directory -Force $backup | Out-Null

    Copy-Item -LiteralPath $ime -Destination (Join-Path $backup 'ImeDialogExports.cs') -Force
    Copy-Item -LiteralPath $presenter -Destination (Join-Path $backup 'VulkanVideoPresenter.cs') -Force

    Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value $backup -Encoding UTF8

    try{
        Copy-Item -LiteralPath (ImePayload) -Destination $ime -Force

        $pt=NL([IO.File]::ReadAllText($presenter))
        $pt=Apply-PresenterV7408615 $pt
        WritePreserving $presenter $pt

        Assert-V7408615 $repo

        Write-Host "$script:Tag SOURCE PATCH APPLIED." -ForegroundColor Green
        Write-Host "$script:Tag ImePostSHA256=$(Sha $ime)"
        Write-Host "$script:Tag PresenterPostSHA256=$(Sha $presenter)"
        Write-Host "$script:Tag Backup=$backup"
    }
    catch{
        Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $ime -Force
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $presenter -Force

        Write-Host "$script:Tag [ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$script:Tag SAFE rollback completed." -ForegroundColor Yellow
        exit 1
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$log=Join-Path $patches ('SharpEmu_V74_0_86_1_5_CHARACTER_CREATOR_UI_BINK_IME_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')

& dotnet build (CliProject) -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $log
$code=$LASTEXITCODE

if($code -ne 0){
    if($backup){
        Copy-Item -LiteralPath (Join-Path $backup 'ImeDialogExports.cs') -Destination $ime -Force
        Copy-Item -LiteralPath (Join-Path $backup 'VulkanVideoPresenter.cs') -Destination $presenter -Force
    }

    Write-Host "$script:Tag [ERROR] BUILD FAILED; SAFE rollback completed." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
