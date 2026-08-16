param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740263 -RepositoryRoot $RepositoryRoot
$packageRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($packageRoot,'scripts','validate.ps1'))
& ([IO.Path]::Combine($packageRoot,'scripts','precheck.ps1')) `
    -RepositoryRoot $root `
    -Eboot $Eboot

$agcPath=Get-AgcPathV740263 -Root $root
$hostMoviePath=Get-HostMoviePathV740263 -Root $root
$payload=[IO.Path]::Combine(
    $packageRoot,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine(
    $root,'.sharpemu-hotfix-backup',"V74_0_26_3_$stamp")
[IO.Directory]::CreateDirectory($backupRoot)|Out-Null

$agcBackup=[IO.Path]::Combine($backupRoot,'AgcExports.cs')
[IO.File]::Copy($agcPath,$agcBackup,$true)

$hostBefore=(Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash

try{
    $current=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
    $target=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash

    if($current -ne $target){
        [IO.File]::Copy($payload,$agcPath,$true)
        $installed=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
        if($installed -ne $target){
            throw "[V74.0.26.3] Installed AGC hash mismatch: $installed"
        }
        Write-Host '[V74.0.26.3] AGC FIX APPLIED: WRITE_DATA packet-position uses ordered action without GPU->CPU visibility.' -ForegroundColor Green
    } else {
        Write-Host '[V74.0.26.3] AGC fix already installed.' -ForegroundColor Yellow
    }

    Push-Location $root
    try{
        Write-Host '[V74.0.26.3] Building Release win-x64...'
        & dotnet build `
            'src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Release `
            -r win-x64 `
            --nologo
        if($LASTEXITCODE -ne 0){
            throw "[V74.0.26.3] Release build failed: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $hostAfter=(Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash
    if($hostAfter -ne $hostBefore){
        throw '[V74.0.26.3] READ-ONLY MEDIA INVARIANT FAILED: HostMovieBridge changed.'
    }
}
catch{
    [IO.File]::Copy($agcBackup,$agcPath,$true)
    Write-Host "[V74.0.26.3] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

Write-Host '[V74.0.26.3] APPLY + RELEASE BUILD PASSED.' -ForegroundColor Green
Write-Host "[V74.0.26.3] AGC SHA256: $((Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26.3] HostMovieBridge unchanged: $((Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26.3] Backup: $backupRoot"
