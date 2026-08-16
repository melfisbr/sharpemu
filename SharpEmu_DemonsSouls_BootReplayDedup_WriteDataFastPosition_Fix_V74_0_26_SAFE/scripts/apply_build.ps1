param([string]$RepositoryRoot="",[string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoV74026 -RepositoryRoot $RepositoryRoot
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
& ([IO.Path]::Combine($pkg,'scripts','validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts','precheck.ps1')) -RepositoryRoot $root -Eboot $Eboot
$agc=Get-AgcV74026 -Root $root
$host=Get-HostMovieV74026 -Root $root
$payload=[IO.Path]::Combine($pkg,'payload','SharpEmu.Libs','Agc','AgcExports.cs')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$broot=[IO.Path]::Combine($root,'.sharpemu-hotfix-backup',"V74_0_26_$stamp")
[IO.Directory]::CreateDirectory($broot)|Out-Null
$ab=[IO.Path]::Combine($broot,'AgcExports.cs')
$hb=[IO.Path]::Combine($broot,'HostMovieBridge.cs')
[IO.File]::Copy($agc,$ab,$true)
[IO.File]::Copy($host,$hb,$true)

try{
    if((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash){
        [IO.File]::Copy($payload,$agc,$true)
        Write-Host '[V74.0.26] AGC FIX APPLIED: packet-position WRITE_DATA uses no-GPU-readback ordered action.' -ForegroundColor Green
    }
    $ht=[IO.File]::ReadAllText($host)
    if((Get-MediaDedupeStateV74026 -Text $ht) -eq 'Baseline'){
        [IO.File]::WriteAllText($host,(Convert-MediaDedupeV74026 -Text $ht),[Text.UTF8Encoding]::new($false))
        Write-Host '[V74.0.26] MEDIA FIX APPLIED: canonical host-boot replay dedupe is default-on.' -ForegroundColor Green
    }
    Push-Location $root
    try{
        Write-Host '[V74.0.26] Building Release win-x64...'
        & dotnet build 'src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Release -r win-x64 --nologo
        if($LASTEXITCODE -ne 0){throw "[V74.0.26] Release build failed: $LASTEXITCODE"}
    } finally {Pop-Location}
}
catch{
    [IO.File]::Copy($ab,$agc,$true)
    [IO.File]::Copy($hb,$host,$true)
    Write-Host "[V74.0.26] ROLLBACK completed: $broot" -ForegroundColor Yellow
    throw
}
Write-Host '[V74.0.26] APPLY + RELEASE BUILD PASSED.' -ForegroundColor Green
Write-Host "[V74.0.26] AGC SHA256: $((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)"
Write-Host "[V74.0.26] Media state: $(Get-MediaDedupeStateV74026 -Text ([IO.File]::ReadAllText($host)))"
Write-Host "[V74.0.26] Backup: $broot"
