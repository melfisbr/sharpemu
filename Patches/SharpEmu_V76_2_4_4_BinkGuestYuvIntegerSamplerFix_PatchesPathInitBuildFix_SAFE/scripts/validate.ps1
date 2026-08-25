$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifest)) { throw "manifest.sha256 ausente" }

$manifestLines = Get-Content -LiteralPath $manifest | Where-Object { $_.Trim() }
$checked = 0
foreach ($manifestLine in $manifestLines) {
    if ($manifestLine -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') {
        throw "Linha de manifest inválida: $manifestLine"
    }
    $expectedHash = $Matches[1].ToLowerInvariant()
    $relativePath = $Matches[2]
    $fullPath = Join-Path $PackageRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) { throw "Arquivo do manifest ausente: $relativePath" }
    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Hash mismatch: $relativePath expected=$expectedHash actual=$actualHash"
    }
    $checked++
}

# Parse all PowerShell scripts.
$parseErrors = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $parseErrors.Add("$($_.FullName): $($parseError.Message)")
    }
}
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse FAILED:`n$($parseErrors -join "`n")"
}

# Reject assignments to common automatic read-only variables.
$forbiddenAssignment = '(?im)^\s*\$(Host|Error|PID|PSHome|PSScriptRoot|PSCommandPath)\s*='
Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $scriptText = [System.IO.File]::ReadAllText($_.FullName)
    if ($scriptText -match $forbiddenAssignment) {
        throw "Atribuição proibida a variável automática em $($_.Name): $($Matches[0].Trim())"
    }
}

Write-Tag "PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; automatic-variable guard passed)."
