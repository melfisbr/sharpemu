param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$state=Assert-StructuralContracts
$p=$state.Presenter
$a=$state.Agc

$markerPresenter=$p.Contains('SHARPEMU_V74_0_78_PRE_SNAPSHOT_SAMPLER_ALIAS_INDEX')
$markerAgc=$a.Contains('SHARPEMU_V74_0_78_PRODUCER_WAKE_DRAIN')
$uninit=($a -match 'AllocateUninitializedArray<byte>\s*\(\s*checked\(\(int\)physicalSourceByteCount\)\s*\)')
$legacy33=($p -match 'V7405633|V74056331|V74056332|PRE_SNAPSHOT_SAMPLER_ALIAS')

Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
Write-Host "$script:Tag v74078_presenter=$markerPresenter"
Write-Host "$script:Tag v74078_agc=$markerAgc"
Write-Host "$script:Tag uninitialized_large_snapshot=$uninit"
Write-Host "$script:Tag legacy_sampler_alias_marker=$legacy33"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag preserves_accumulated_source=True"

if($markerPresenter -and $markerAgc -and $uninit){
    Write-Host "$script:Tag State=AlreadyApplied"
}else{
    Write-Host "$script:Tag State=Ready"
}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
