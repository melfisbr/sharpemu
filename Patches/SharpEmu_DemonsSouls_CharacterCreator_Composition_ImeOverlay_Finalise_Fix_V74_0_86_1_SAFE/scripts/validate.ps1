. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$required=@(
 'ANALYSIS.txt','FIX_NOTES.txt','README.md','manifest.json',
 'scripts\common.ps1','scripts\precheck.ps1','scripts\apply_build.ps1','scripts\diagnostic.ps1','scripts\run_test.ps1','scripts\rollback.ps1','scripts\validate.ps1',
 'payload\ImeDialogExports.cs','patch\Presenter.fields.insert.txt','patch\Presenter.helpers.insert.txt'
)
$missing=@()
foreach($r in $required){ if(-not(Test-Path -LiteralPath (Join-Path $pkg $r))){ $missing+=$r } }
if($missing.Count -gt 0){ Write-Host "$script:Tag [ERROR] Missing files: $($missing -join ', ')" -ForegroundColor Red; exit 1 }
Get-Content (Join-Path $pkg 'scripts\common.ps1') | Out-Null
Get-Content (Join-Path $pkg 'scripts\apply_build.ps1') | Out-Null
Get-Content (Join-Path $pkg 'scripts\run_test.ps1') | Out-Null
Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; required files present)." -ForegroundColor Green
