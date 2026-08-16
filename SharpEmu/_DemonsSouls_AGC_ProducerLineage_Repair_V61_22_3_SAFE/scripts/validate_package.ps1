. (Join-Path $PSScriptRoot "common.ps1")
$packageRoot = Get-PackageRoot
$manifest = Join-Path $packageRoot "manifest.sha256"
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "manifest.sha256 ausente."
}

$lines = Get-Content -LiteralPath $manifest
$checked = 0
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        continue
    }
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2) {
        throw "Linha invalida no manifest: $line"
    }
    $expected = $parts[0].Trim().ToUpperInvariant()
    $relative = $parts[1].Trim()
    $path = Join-Path $packageRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo ausente: $relative"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Hash divergente: $relative`nExpected=$expected`nActual=$actual"
    }
    $checked++
}

# Syntax preflight added in V61.22.3.  This deliberately uses PowerShell's own
# parser so a malformed diagnostic script is rejected during package validation,
# before any precheck/build/game command is attempted.
$syntaxErrors = New-Object System.Collections.Generic.List[string]
$psScripts = Get-ChildItem -LiteralPath (Join-Path $packageRoot "scripts") -Filter "*.ps1" -File
foreach ($script in $psScripts) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors)
    foreach ($parseError in @($errors)) {
        if ($null -ne $parseError) {
            $syntaxErrors.Add(
                $script.Name + ": line " + $parseError.Extent.StartLineNumber +
                ", column " + $parseError.Extent.StartColumnNumber +
                ": " + $parseError.Message)
        }
    }
}
if ($syntaxErrors.Count -gt 0) {
    $details = [string]::Join([Environment]::NewLine, $syntaxErrors)
    throw "PACKAGE POWERSHELL SYNTAX VALIDATION FAILED:`n$details"
}

Write-Host "[V61.22.3] PACKAGE VALIDATION PASSED ($checked hashed files; $($psScripts.Count) PowerShell scripts parsed)." -ForegroundColor Green
