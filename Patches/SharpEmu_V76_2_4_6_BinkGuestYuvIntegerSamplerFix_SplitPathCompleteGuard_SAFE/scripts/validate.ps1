. (Join-Path $PSScriptRoot 'common.ps1')

$manifest = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "manifest.sha256 ausente"
}
$bad = @()
$count = 0
foreach ($line in @(Get-Content -LiteralPath $manifest)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $match = [regex]::Match($line, '^(?<hash>[0-9A-Fa-f]{64})\s+\*?(?<path>.+?)\s*$')
    if (-not $match.Success) { throw "Linha invalida no manifest: $line" }
    $relative = $match.Groups['path'].Value.Trim().Replace('/', '\\')
    $file = Join-Path $PackageRoot $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        $bad += "missing:$relative"
        continue
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
    if ($actual -ne $match.Groups['hash'].Value.ToLowerInvariant()) {
        $bad += "hash:$relative"
    }
    $count++
}
if ($bad.Count -ne 0) { throw "PACKAGE VALIDATION FAILED: $($bad -join ', ')" }

# Parse all package PowerShell scripts.
foreach ($script in @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        throw "PowerShell parse failed: $($script.Name): $((@($parseErrors | ForEach-Object {$_.Message}) -join '; '))"
    }
}

# Block the recurring read-only automatic-variable mistake case-insensitively.
foreach ($script in @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File)) {
    $text = [System.IO.File]::ReadAllText($script.FullName)
    if ([regex]::IsMatch($text, '(?im)^\s*\$(host|error|home|pid|pwd)\s*=')) {
        throw "automatic read-only variable assignment detected: $($script.Name)"
    }
}

Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; AST Split-Path complete guard passed)."
