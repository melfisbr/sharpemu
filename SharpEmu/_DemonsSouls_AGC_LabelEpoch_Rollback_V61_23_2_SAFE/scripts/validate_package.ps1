param([string]$PackageRoot)
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$PackageRoot=$PackageRoot.Trim('"')
$manifest=Join-Path $PackageRoot 'SHA256SUMS.txt'
if (!(Test-Path -LiteralPath $manifest)) { throw 'SHA256SUMS.txt missing.' }
$errors=@()
Get-Content -LiteralPath $manifest | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    $parts=$_ -split '\s+\*?',2
    $expected=$parts[0].Trim().ToUpperInvariant()
    $rel=$parts[1].Trim().Replace('/','\')
    $path=Join-Path $PackageRoot $rel
    if (!(Test-Path -LiteralPath $path)) { $errors+="missing: $rel"; return }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) { $errors+="hash mismatch: $rel" }
}
$parseErrors=@()
Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens=$null; $errs=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errs)
    if ($errs.Count -gt 0) { $parseErrors += "$($_.Name): $($errs[0].Message)" }
}
if ($errors.Count -or $parseErrors.Count) { throw (($errors+$parseErrors) -join '; ') }
Write-Host "[V61.23.2] PACKAGE VALIDATION PASSED."
