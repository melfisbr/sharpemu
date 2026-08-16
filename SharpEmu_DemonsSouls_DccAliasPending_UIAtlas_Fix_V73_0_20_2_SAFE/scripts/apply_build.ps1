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
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $vp=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $ag=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$presenter=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\Agc\AgcExports.cs')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine(
    $repo,
    "SharpEmu_Backup_V73_0_20_2_$stamp")

$items=@(
    @{
        Source=$presenter
        Backup=[IO.Path]::Combine(
            $backupRoot,
            'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    },
    @{
        Source=$agc
        Backup=[IO.Path]::Combine(
            $backupRoot,
            'SharpEmu.Libs\Agc\AgcExports.cs')
    }
)

foreach($item in $items){
    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($item.Backup)) | Out-Null
    [IO.File]::Copy($item.Source,$item.Backup,$true)
}

function Restore-V730202 {
    foreach($item in $items){
        if([IO.File]::Exists($item.Backup)){
            [IO.File]::Copy($item.Backup,$item.Source,$true)
        }
    }
    Write-Host "[V73.0.20.2] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
}

try{
    $pt=[IO.File]::ReadAllText($presenter)
    $at=[IO.File]::ReadAllText($agc)
    $already=
        $pt.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2') -and
        $at.Contains('SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2')

    if(-not $already){
        & ([IO.Path]::Combine($pkg,'scripts\patch_v73020.ps1')) `
            -PresenterPath $presenter `
            -AgcPath $agc
    } else {
        Write-Host '[V73.0.20.2] Source already patched; build only.' -ForegroundColor Yellow
    }

    $pt=[IO.File]::ReadAllText($presenter)
    $at=[IO.File]::ReadAllText($agc)

    foreach($marker in @(
        'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2',
        '[V73.0.20.2][LARGE_PROBE_SEEDED]'
    )){
        if(-not $pt.Contains($marker)){
            throw "Presenter verification failed: $marker"
        }
    }

    foreach($marker in @(
        'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2',
        '[V73.0.20.2][DCC_ALIAS_PENDING]',
        '(preferGpuResident || resolvedDccAlias)'
    )){
        if(-not $at.Contains($marker)){
            throw "AGC verification failed: $marker"
        }
    }

    $libs=[IO.Path]::Combine(
        $base,
        'SharpEmu.Libs\SharpEmu.Libs.csproj')
    & dotnet restore $libs --nologo
    if($LASTEXITCODE -ne 0){throw 'dotnet restore failed.'}

    & dotnet build $libs -c Debug --no-restore --nologo
    if($LASTEXITCODE -ne 0){throw 'SharpEmu.Libs build failed.'}

    $cli=[IO.Path]::Combine(
        $base,
        'SharpEmu.CLI\SharpEmu.CLI.csproj')
    if([IO.File]::Exists($cli)){
        & dotnet build $cli -c Debug --nologo
        if($LASTEXITCODE -ne 0){throw 'SharpEmu.CLI build failed.'}
    }
}
catch{
    Restore-V730202
    throw
}

Write-Host '[V73.0.20.2] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "Presenter SHA256: $((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)"
Write-Host "AgcExports SHA256: $((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)"
Write-Host "Backup: $backupRoot"
