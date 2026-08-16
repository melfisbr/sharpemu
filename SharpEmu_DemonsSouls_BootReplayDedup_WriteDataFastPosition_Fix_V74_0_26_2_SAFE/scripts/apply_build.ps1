param(
    [string]$RepositoryRoot="",
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$root=Resolve-RepoV740262 -RepositoryRoot $RepositoryRoot
$packageRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($packageRoot,'scripts','validate.ps1'))
& ([IO.Path]::Combine($packageRoot,'scripts','precheck.ps1')) `
    -RepositoryRoot $root `
    -Eboot $Eboot

$agcPath=Get-AgcV740262 -Root $root
$hostMoviePath=Get-HostMovieV740262 -Root $root
$payload=[IO.Path]::Combine(
    $packageRoot,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=[IO.Path]::Combine(
    $root,'.sharpemu-hotfix-backup',"V74_0_26_2_$stamp")
[IO.Directory]::CreateDirectory($backupRoot)|Out-Null
$agcBackup=[IO.Path]::Combine($backupRoot,'AgcExports.cs')
[IO.File]::Copy($agcPath,$agcBackup,$true)

try{
    $current=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
    $target=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash

    if($current -ne $target){
        [IO.File]::Copy($payload,$agcPath,$true)
        $installed=(Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash
        if($installed -ne $target){
            throw "[V74.0.26.2] Installed AGC hash mismatch: $installed"
        }
        Write-Host '[V74.0.26.2] AGC FIX APPLIED: WRITE_DATA packet-position no longer requests GPU->CPU visibility.' -ForegroundColor Green
    } else {
        Write-Host '[V74.0.26.2] AGC fix already present.' -ForegroundColor Yellow
    }

    # Deliberately no write to HostMovieBridge.cs. V31.7.9 is enabled by
    # environment only in RUN_4.
    $beforeMediaHash=(Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash

    Push-Location $root
    try{
        Write-Host '[V74.0.26.2] Building Release win-x64...'
        & dotnet build `
            'src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Release `
            -r win-x64 `
            --nologo
        if($LASTEXITCODE -ne 0){
            throw "[V74.0.26.2] Release build failed: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $afterMediaHash=(Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash
    if($afterMediaHash -ne $beforeMediaHash){
        throw '[V74.0.26.2] READ-ONLY MEDIA INVARIANT FAILED: HostMovieBridge changed during build.'
    }
}
catch{
    [IO.File]::Copy($agcBackup,$agcPath,$true)
    Write-Host "[V74.0.26.2] ROLLBACK completed: $backupRoot" -ForegroundColor Yellow
    throw
}

Write-Host '[V74.0.26.2] APPLY + RELEASE BUILD PASSED.' -ForegroundColor Green
Write-Host "[V74.0.26.2] AGC SHA256: $((Get-FileHash -LiteralPath $agcPath -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26.2] HostMovieBridge unchanged: $((Get-FileHash -LiteralPath $hostMoviePath -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26.2] Backup: $backupRoot"
