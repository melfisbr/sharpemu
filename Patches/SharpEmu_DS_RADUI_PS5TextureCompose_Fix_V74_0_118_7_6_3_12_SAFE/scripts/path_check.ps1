param()
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Tag "PackageRoot=$script:PackageRoot"
Write-Tag "PackageRootExists=$(Test-Path -LiteralPath $script:PackageRoot)"
Write-Tag "ManifestExists=$(Test-Path -LiteralPath (Join-Path $script:PackageRoot 'manifest.sha256'))"
Write-Tag "PatchesRoot=$(Get-PatchesRoot)"
Write-Tag "RepositoryRoot=$(Get-RepositoryRoot)"
Write-Tag 'PATH CHECK PASSED'
