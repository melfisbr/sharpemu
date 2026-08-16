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
foreach($c in @([IO.Path]::Combine($repo,'src'),$repo)){
    $p=[IO.Path]::Combine($c,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $a=[IO.Path]::Combine($c,'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($p) -and [IO.File]::Exists($a)){
        $base=$c
        break
    }
}
if($null -eq $base){throw 'Source layout nao reconhecido.'}

$rels=@(
    'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'SharpEmu.Libs\Agc\AgcExports.cs'
)
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine($repo,"SharpEmu_Backup_V73_0_19_$stamp")
foreach($rel in $rels){
    $src=[IO.Path]::Combine($base,$rel)
    $bak=[IO.Path]::Combine($backupRoot,$rel)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($bak)) | Out-Null
    [IO.File]::Copy($src,$bak,$true)
}

function Restore-V73019 {
    foreach($rel in $rels){
        $dst=[IO.Path]::Combine($base,$rel)
        $bak=[IO.Path]::Combine($backupRoot,$rel)
        if([IO.File]::Exists($bak)){[IO.File]::Copy($bak,$dst,$true)}
    }
}

try{
    & ([IO.Path]::Combine($pkg,'scripts\patch_ui_textures.ps1')) `
        -PresenterPath ([IO.Path]::Combine($base,$rels[0])) `
        -AgcPath ([IO.Path]::Combine($base,$rels[1]))

    $libs=[IO.Path]::Combine($base,'SharpEmu.Libs\SharpEmu.Libs.csproj')
    if(-not [IO.File]::Exists($libs)){throw "Project missing: $libs"}

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
    Restore-V73019
    Write-Host "[V73.0.19] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

$ph=(Get-FileHash -LiteralPath ([IO.Path]::Combine($base,$rels[0])) -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath ([IO.Path]::Combine($base,$rels[1])) -Algorithm SHA256).Hash
Write-Host '[V73.0.19] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "Presenter SHA256 after: $ph"
Write-Host "AgcExports SHA256 after: $ah"
Write-Host "Backup: $backupRoot"
