. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$manifest=Join-Path $pkg 'PACKAGE_SHA256.txt'
if(-not(Test-Path $manifest)){Write-Host '[V74.0.77.2][ERROR] PACKAGE_SHA256.txt missing' -ForegroundColor Red;exit 1}
$bad=0;$count=0
foreach($line in Get-Content $manifest){
 if([string]::IsNullOrWhiteSpace($line)){continue}
 $parts=$line -split '\s+\*?',2;if($parts.Count-ne 2){$bad++;continue}
 $expected=$parts[0].Trim().ToUpperInvariant();$rel=$parts[1].Trim().Replace('/','\');$p=Join-Path $pkg $rel
 if(-not(Test-Path -LiteralPath $p)){Write-Host "[V74.0.77.2][ERROR] missing: $rel" -ForegroundColor Red;$bad++;continue}
 $actual=Sha $p;$count++;if($actual-ne$expected){Write-Host "[V74.0.77.2][ERROR] hash mismatch: $rel" -ForegroundColor Red;$bad++}
}
foreach($ps1 in Get-ChildItem (Join-Path $pkg 'scripts') -Filter *.ps1){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($ps1.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){Write-Host "[V74.0.77.2][ERROR] PowerShell parse: $($ps1.Name)" -ForegroundColor Red;$errors|ForEach-Object{Write-Host $_};$bad++}
}
if($bad){Write-Host "[V74.0.77.2] PACKAGE VALIDATION FAILED issues=$bad" -ForegroundColor Red;exit 1}
Write-Host "[V74.0.77.2] PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed)." -ForegroundColor Green
