. (Join-Path $PSScriptRoot 'common.ps1')

$packageRoot = Get-PackageRoot
$manifest = Join-Path $packageRoot 'MANIFEST.sha256'
if (-not (Test-Path -LiteralPath $manifest)) { throw "$script:Tag MANIFEST.sha256 missing." }

$entries = Get-Content -LiteralPath $manifest | Where-Object { $_ -and -not $_.StartsWith('#') }
$count = 0
foreach ($line in $entries) {
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw "$script:Tag Invalid manifest line: $line"
    }
    $expected = $matches[1].ToUpperInvariant()
    $rel = $matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = Join-Path $packageRoot $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$script:Tag Package file missing: $rel"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if ($actual -ne $expected) { throw "$script:Tag Hash mismatch: $rel" }
    $count++
}

$parseErrors = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    foreach ($e in $errors) { $parseErrors.Add(($_.Name + ': ' + $e.Message)) }
}
if ($parseErrors.Count -gt 0) {
    throw "$script:Tag PowerShell parse failure(s):`n$($parseErrors -join "`n")"
}

Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed)."
