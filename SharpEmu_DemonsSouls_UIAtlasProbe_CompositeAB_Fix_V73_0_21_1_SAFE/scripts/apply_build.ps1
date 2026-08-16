param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
& ([IO.Path]::Combine($pkg,'scripts\validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts\precheck.ps1')) -RepoRoot $repo -Eboot $Eboot

$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$src=[IO.File]::ReadAllText($presenter)
$patched=New-PatchedPresenter $src

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine($repo,"SharpEmu_Backup_V73_0_21_1_$stamp")
$backup=[IO.Path]::Combine($backupRoot,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
[IO.File]::Copy($presenter,$backup,$true)

try {
    if($patched.Changed) {
        Write-Utf8NoBom $presenter $patched.Text
        $verify=[IO.File]::ReadAllText($presenter)
        $slice=Get-ProbeMethodSlice $verify
        if($slice.Text -match 'byteCount\s*>\s*MaxTrackedGuestImageBytes'){
            throw 'Installed source still contains sparse-probe size guard.'
        }
        if($slice.Text.IndexOf('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21_1',[StringComparison]::Ordinal) -lt 0){
            throw 'Installed marker missing.'
        }
        Write-Host '[V73.0.21.1] Bounded probe patch applied in-place; unrelated presenter changes preserved.' -ForegroundColor Green
    } else {
        Write-Host "[V73.0.21.1] Probe fix already satisfied ($($patched.Reason)); no source edit required." -ForegroundColor Yellow
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
catch {
    [IO.File]::Copy($backup,$presenter,$true)
    Write-Host "[V73.0.21.1] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

Write-Host '[V73.0.21.1] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "Presenter SHA256: $((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)"
Write-Host "Backup: $backupRoot"
