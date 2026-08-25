param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$tag='[V74.0.118.7.6.3.13.1-DS-RAD-NIHAV-HYBRID-PARSERFIX]'
$packageRoot=Split-Path -Parent $PSScriptRoot
$patchesRoot=Split-Path -Parent $packageRoot
$repositoryRoot=Split-Path -Parent $patchesRoot

Write-Host "$tag PackageRoot=$packageRoot"
Write-Host "$tag PackageRootExists=$(Test-Path -LiteralPath $packageRoot)"
Write-Host "$tag ManifestExists=$(Test-Path -LiteralPath (Join-Path $packageRoot 'manifest.sha256'))"
Write-Host "$tag PatchesRoot=$patchesRoot"
Write-Host "$tag RepositoryRoot=$repositoryRoot"

if(-not(Test-Path -LiteralPath (Join-Path $repositoryRoot 'src'))) {
    throw "$tag repository src directory missing: $repositoryRoot"
}

# Parse common.ps1 before claiming PATH CHECK PASSED.
$tokens=$null
$parseErrors=$null
$commonPath=Join-Path $PSScriptRoot 'common.ps1'
[void][Management.Automation.Language.Parser]::ParseFile(
    $commonPath,
    [ref]$tokens,
    [ref]$parseErrors)
if(@($parseErrors).Count -ne 0) {
    throw "$tag common.ps1 parser preflight failed: $(($parseErrors | ForEach-Object {$_.Message}) -join '; ')"
}

Write-Host "$tag common.ps1 parser preflight=PASSED"
Write-Host "$tag PATH CHECK PASSED"
