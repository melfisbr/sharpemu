param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($pkg,'scripts\validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts\precheck.ps1')) `
    -RepoRoot $repo `
    -Eboot $Eboot

$base=$null
foreach($c in @([IO.Path]::Combine($repo,'src'),$repo)){
    $candidate=[IO.Path]::Combine(
        $c,
        'SharpEmu.Libs\SaveData\SaveDataExports.cs'
    )
    if([IO.File]::Exists($candidate)){
        $base=$c
        break
    }
}
if($null -eq $base){throw 'Source layout nao reconhecido.'}

$rel='SharpEmu.Libs\SaveData\SaveDataExports.cs'
$dst=[IO.Path]::Combine($base,$rel)

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=[IO.Path]::Combine(
    $repo,
    "SharpEmu_Backup_V73_0_18_2_$stamp",
    $rel
)
[IO.Directory]::CreateDirectory(
    [IO.Path]::GetDirectoryName($backup)
) | Out-Null
[IO.File]::Copy($dst,$backup,$true)

try{
    & ([IO.Path]::Combine($pkg,'scripts\patch_savedata.ps1')) `
        -SourcePath $dst

    $after=[IO.File]::ReadAllText($dst)
    foreach($m in @(
        'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18',
        'Nid = "z1JA8-iJt3k"',
        'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18'
    )){
        if(-not $after.Contains($m)){
            throw "Post-patch verification failed: $m"
        }
    }

    $libs=[IO.Path]::Combine(
        $base,
        'SharpEmu.Libs\SharpEmu.Libs.csproj'
    )
    if(-not [IO.File]::Exists($libs)){
        throw "Projeto ausente: $libs"
    }

    & dotnet restore $libs --nologo
    if($LASTEXITCODE -ne 0){throw 'dotnet restore falhou.'}

    & dotnet build $libs -c Debug --no-restore --nologo
    if($LASTEXITCODE -ne 0){throw 'build SharpEmu.Libs falhou.'}

    $cli=[IO.Path]::Combine(
        $base,
        'SharpEmu.CLI\SharpEmu.CLI.csproj'
    )
    if([IO.File]::Exists($cli)){
        & dotnet build $cli -c Debug --nologo
        if($LASTEXITCODE -ne 0){throw 'build SharpEmu.CLI falhou.'}
    }
}
catch{
    [IO.File]::Copy($backup,$dst,$true)
    Write-Host "[V73.0.18.2] ROLLBACK: $backup" -ForegroundColor Yellow
    throw
}

$h=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
Write-Host "[V73.0.18.2] APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "[V73.0.18.2] SaveDataExports SHA256=$h"
Write-Host "[V73.0.18.2] Backup: $backup"
