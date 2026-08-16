param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Resolve-RepoRootV730221 -RepositoryRoot $RepositoryRoot
$packageRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($packageRoot,'scripts','validate.ps1'))
& ([IO.Path]::Combine($packageRoot,'scripts','precheck.ps1')) `
    -RepositoryRoot $repo `
    -Eboot $Eboot

$agc=Get-AgcPathV730221 -Root $repo
$text=[IO.File]::ReadAllText($agc)
$state=Get-CompositeMergeStateV730221 -Text $text

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine(
    $repo,
    '.sharpemu-hotfix-backup',
    "TargetlessCompositeMerge_V73_0_22_1_$stamp")
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backup=[IO.Path]::Combine($backupRoot,'AgcExports.cs')
[IO.File]::Copy($agc,$backup,$true)

try{
    if($state -eq 'Baseline'){
        $patched=Convert-AgcCompositeMergeV730221 -Text $text
        [IO.File]::WriteAllText(
            $agc,
            $patched,
            [Text.UTF8Encoding]::new($false))

        $verify=[IO.File]::ReadAllText($agc)
        $verifyState=Get-CompositeMergeStateV730221 -Text $verify
        if($verifyState -ne 'Applied'){
            throw "[V73.0.22.1] Post-write state invalid: $verifyState"
        }

        Write-Host '[V73.0.22.1] Two-condition PPSA01341 composite merge applied.' -ForegroundColor Green
    } else {
        Write-Host '[V73.0.22.1] Composite merge already present; build only.' -ForegroundColor Yellow
    }

    Write-Host '[V73.0.22.1] Building Release win-x64...'
    Push-Location $repo
    try{
        & dotnet build `
            'src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Release `
            -r win-x64 `
            --nologo
        if($LASTEXITCODE -ne 0){
            throw "[V73.0.22.1] Release build failed: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}
catch{
    [IO.File]::Copy($backup,$agc,$true)
    Write-Host "[V73.0.22.1] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

$finalHash=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
Write-Host '[V73.0.22.1] APPLY + RELEASE BUILD PASSED.' -ForegroundColor Green
Write-Host "[V73.0.22.1] AgcExports SHA256: $finalHash"
Write-Host "[V73.0.22.1] Backup: $backupRoot"
