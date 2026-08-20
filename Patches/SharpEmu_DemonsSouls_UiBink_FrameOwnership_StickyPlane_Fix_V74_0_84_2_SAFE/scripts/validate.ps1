. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $hashFile=Join-Path $pkg 'PACKAGE_SHA256.txt'
if (-not (Test-Path $hashFile)) { Write-Host '[V74.0.84.2][ERROR] PACKAGE_SHA256.txt missing' -ForegroundColor Red; exit 1 }
$bad=0; $count=0
foreach ($line in Get-Content -LiteralPath $hashFile) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts=$line -split '\s+\*',2
    if ($parts.Count -ne 2) { Write-Host "[V74.0.84.2][ERROR] malformed hash line: $line" -ForegroundColor Red; $bad++; continue }
    $expected=$parts[0].Trim().ToUpperInvariant(); $rel=$parts[1].Trim(); $path=Join-Path $pkg $rel
    if (-not (Test-Path -LiteralPath $path)) { Write-Host "[V74.0.84.2][ERROR] missing file: $rel" -ForegroundColor Red; $bad++; continue }
    $actual=Sha $path; $count++
    if ($actual -ne $expected) { Write-Host "[V74.0.84.2][ERROR] hash mismatch: $rel" -ForegroundColor Red; $bad++ }
}
foreach ($ps1 in Get-ChildItem -LiteralPath (Join-Path $pkg 'scripts') -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { Write-Host "[V74.0.84.2][ERROR] PowerShell parse failed $($ps1.Name): $($errors[0].Message)" -ForegroundColor Red; $bad++ }
}
$apply=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\apply_build.ps1'))
foreach ($required in @('UI_BINK_FRAME_SNAPSHOT','UI_BINK_STICKY_PLANE','UI_BINK_PLANE_LEARN','FindLearnedUiBinkTextureBindingsV740842')) {
    if (-not $apply.Contains($required)) { Write-Host "[V74.0.84.2][ERROR] apply marker missing: $required" -ForegroundColor Red; $bad++ }
}
if ($bad) { Write-Host "[V74.0.84.2] PACKAGE VALIDATION FAILED issues=$bad" -ForegroundColor Red; exit 1 }
Write-Host "[V74.0.84.2] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; structural markers present)." -ForegroundColor Green
