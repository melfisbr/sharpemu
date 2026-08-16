param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($pkg,'scripts\validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts\precheck.ps1')) -RepoRoot $repo -Eboot $Eboot

$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    if([IO.File]::Exists($vp)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$dst=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$payload=[IO.Path]::Combine($pkg,'payload\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$current=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
$target=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine($repo,"SharpEmu_Backup_V73_0_21_$stamp")
$backup=[IO.Path]::Combine(
    $backupRoot,
    'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
[IO.File]::Copy($dst,$backup,$true)

try{
    if($current -ne $target){
        [IO.File]::Copy($payload,$dst,$true)
        $installed=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        if($installed -ne $target){
            throw "Installed presenter hash mismatch: $installed"
        }
        Write-Host '[V73.0.21] Exact validated presenter payload installed.' -ForegroundColor Green
    } else {
        Write-Host '[V73.0.21] Exact presenter payload already installed.' -ForegroundColor Yellow
    }

    $libs=[IO.Path]::Combine($base,'SharpEmu.Libs\SharpEmu.Libs.csproj')
    & dotnet restore $libs --nologo
    if($LASTEXITCODE -ne 0){throw 'dotnet restore failed.'}
    & dotnet build $libs -c Debug --no-restore --nologo
    if($LASTEXITCODE -ne 0){throw 'SharpEmu.Libs build failed.'}

    $cli=[IO.Path]::Combine($base,'SharpEmu.CLI\SharpEmu.CLI.csproj')
    if([IO.File]::Exists($cli)){
        & dotnet build $cli -c Debug --nologo
        if($LASTEXITCODE -ne 0){throw 'SharpEmu.CLI build failed.'}
    }
}
catch{
    [IO.File]::Copy($backup,$dst,$true)
    Write-Host "[V73.0.21] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

Write-Host '[V73.0.21] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "Presenter SHA256: $((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash)"
Write-Host "Backup: $backupRoot"
