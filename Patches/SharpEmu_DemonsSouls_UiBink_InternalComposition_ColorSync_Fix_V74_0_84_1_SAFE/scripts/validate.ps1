. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$hashFile=Join-Path $pkg 'PACKAGE_SHA256.txt'
if (-not (Test-Path $hashFile)) { Write-Host '[V74.0.84.1][ERROR] PACKAGE_SHA256.txt missing' -ForegroundColor Red; exit 1 }
$bad=0; $count=0
foreach ($line in Get-Content -LiteralPath $hashFile) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts=$line -split '\s+\*',2
    if ($parts.Count -ne 2) { Write-Host "[V74.0.84.1][ERROR] malformed hash line: $line" -ForegroundColor Red; $bad++; continue }
    $expected=$parts[0].Trim().ToUpperInvariant()
    $rel=$parts[1].Trim()
    $path=Join-Path $pkg $rel
    if (-not (Test-Path -LiteralPath $path)) { Write-Host "[V74.0.84.1][ERROR] missing file: $rel" -ForegroundColor Red; $bad++; continue }
    $actual=Sha $path
    $count++
    if ($actual -ne $expected) { Write-Host "[V74.0.84.1][ERROR] hash mismatch: $rel" -ForegroundColor Red; $bad++ }
}
foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $pkg 'scripts') -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { Write-Host "[V74.0.84.1][ERROR] PowerShell parse failed $($ps1.Name): $($errors[0].Message)" -ForegroundColor Red; $bad++ }
}
$applyText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\apply_build.ps1'))
if ($applyText.Contains('$eb.Replace($needle,NL(')) {
    Write-Host '[V74.0.84.1][ERROR] Regression guard: nested NL call inside String.Replace reintroduced.' -ForegroundColor Red
    $bad++
}
if (-not $applyText.Contains('$replacementNormalized=NL $replacement')) {
    Write-Host '[V74.0.84.1][ERROR] Regression guard: parser-safe replacement normalization marker missing.' -ForegroundColor Red
    $bad++
}

if ($bad) { Write-Host "[V74.0.84.1] PACKAGE VALIDATION FAILED issues=$bad" -ForegroundColor Red; exit 1 }
Write-Host "[V74.0.84.1] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; nested-call regression guard passed)." -ForegroundColor Green
