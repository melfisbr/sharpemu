. (Join-Path $PSScriptRoot 'common.ps1')

$manifestPath = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "$PackageTag manifest.sha256 ausente" }
$manifestLines = Get-Content -LiteralPath $manifestPath
$checked = 0
foreach ($manifestLine in $manifestLines) {
    if ([string]::IsNullOrWhiteSpace($manifestLine)) { continue }
    if ($manifestLine -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') { throw "$PackageTag linha de manifest inválida: $manifestLine" }
    $expectedHash = $Matches[1].ToLowerInvariant()
    $relativePath = $Matches[2]
    $fullPath = Join-Path $PackageRoot ($relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "$PackageTag arquivo ausente: $relativePath" }
    $actualHash = Get-Sha256V76245 $fullPath
    if ($actualHash -ne $expectedHash) { throw "$PackageTag hash mismatch: $relativePath" }
    $checked++
}

$scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -File -Filter '*.ps1')
foreach ($scriptFile in $scriptFiles) { Assert-PowerShellParsesV76245 $scriptFile.FullName }

# Guard against the exact defect this package fixes inside its own scripts.
foreach ($scriptFile in $scriptFiles) {
    $scriptText = Read-TextV76245 $scriptFile.FullName
    if ((Get-SuspiciousSplitPathCountV76245 $scriptText) -ne 0) {
        throw "$PackageTag package itself contains suspicious Split-Path null argument: $($scriptFile.Name)"
    }
}

Write-Host "$PackageTag PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; Split-Path null guard passed)."
