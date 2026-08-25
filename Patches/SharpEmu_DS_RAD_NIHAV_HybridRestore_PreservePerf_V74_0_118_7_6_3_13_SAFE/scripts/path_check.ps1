param()
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Tag "PackageRoot=$script:PackageRoot"
Write-Tag "PatchesRoot=$(Get-PatchesRoot)"
Write-Tag "RepositoryRoot=$(Get-RepositoryRoot)"
Write-Tag 'PATH CHECK PASSED'
