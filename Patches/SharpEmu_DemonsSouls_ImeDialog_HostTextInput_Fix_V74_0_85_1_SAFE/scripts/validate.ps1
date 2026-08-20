. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$manifest=Join-Path $pkg 'PACKAGE_SHA256.txt'
$issues=0
if (-not (Test-Path $manifest)) { Write-Host '[V74.0.85.1][ERROR] PACKAGE_SHA256.txt missing' -ForegroundColor Red; exit 1 }
$lines=Get-Content -LiteralPath $manifest
foreach($line in $lines){
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts=$line -split '\s+',2
    if ($parts.Count -ne 2) { $issues++; Write-Host "[V74.0.85.1][ERROR] malformed hash line: $line" -ForegroundColor Red; continue }
    $expected=$parts[0].Trim().ToUpperInvariant(); $rel=$parts[1].Trim().Replace('/','\')
    $path=Join-Path $pkg $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $issues++; Write-Host "[V74.0.85.1][ERROR] missing: $rel" -ForegroundColor Red; continue }
    $actual=(Sha $path).ToUpperInvariant()
    if ($actual -ne $expected) { $issues++; Write-Host "[V74.0.85.1][ERROR] hash mismatch: $rel" -ForegroundColor Red }
}
foreach($ps in Get-ChildItem -LiteralPath (Join-Path $pkg 'scripts') -Filter '*.ps1' -File){
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){ $issues++; Write-Host "[V74.0.85.1][ERROR] PowerShell parse failed $($ps.Name): $($errors[0].Message)" -ForegroundColor Red }
}
$payload=[IO.File]::ReadAllText((PayloadSource))
foreach($m in @('SHARPEMU_V74_0_85_1_IME_DIALOG_HOST_TEXT_INPUT','host_panel_open','text_commit','StatusRunning','powershell.exe')){
    if(-not $payload.Contains($m)){ $issues++; Write-Host "[V74.0.85.1][ERROR] payload marker missing: $m" -ForegroundColor Red }
}
if($payload.Contains('DefaultInputText = "Sharp"')){ $issues++; Write-Host '[V74.0.85.1][ERROR] legacy immediate autofill leaked into payload' -ForegroundColor Red }
if($issues -gt 0){ Write-Host "[V74.0.85.1] PACKAGE VALIDATION FAILED issues=$issues" -ForegroundColor Red; exit 1 }
Write-Host "[V74.0.85.1] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed; IME host-panel payload verified)." -ForegroundColor Green
