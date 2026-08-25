param()
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Tag "PackageRoot=$script:PackageRoot"
Write-Tag "PatchesRoot=$(Get-PatchesRoot)"
Write-Tag "RepositoryRoot=$(Get-RepositoryRoot)"
$rad=Get-InstalledRadVideo64
Write-Tag "ExternalRAD=$rad"
if($null -eq $rad){throw "$script:Tag official RAD executable missing"}
Write-Tag 'PATH CHECK PASSED'
