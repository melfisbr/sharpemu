. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$required=@(
    'ANALYSIS.txt',
    'FIX_NOTES.txt',
    'README.md',
    'manifest.json',
    'scripts\common.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1',
    'scripts\run_test.ps1',
    'scripts\rollback.ps1',
    'scripts\validate.ps1'
)

$missing=@()
foreach($r in $required){
    if(-not(Test-Path -LiteralPath (Join-Path $pkg $r))){$missing+=$r}
}
if($missing.Count -gt 0){
    Write-Host "$script:Tag [ERROR] Missing files: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

$parseIssues=@()
foreach($f in Get-ChildItem (Join-Path $pkg 'scripts') -Filter '*.ps1'){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count -gt 0){
        foreach($e in $errors){$parseIssues+=("$($f.Name): "+$e.Message)}
    }
}
if($parseIssues.Count -gt 0){
    foreach($issue in $parseIssues){
        Write-Host "$script:Tag [ERROR] PowerShell parse failed $issue" -ForegroundColor Red
    }
    exit 1
}

$commonText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\common.ps1'))
$runner=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\run_test.ps1'))

$checks=[ordered]@{
    main_menu_only_marker=$commonText.Contains('SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE')
    main_menu_name=$commonText.Contains('"main_menu.bk2"')
    main_menu_ngp_name=$commonText.Contains('"main_menu_ngp.bk2"')
    live_runtime_log=$runner.Contains('LIVE_RUNTIME_LOG')
    no_temp_stderr=-not $runner.Contains('RedirectStandardError')
    no_temp_stdout=-not $runner.Contains('RedirectStandardOutput')
    no_locked_read_pattern=-not $runner.Contains('SharpEmuV74088_stderr_')
    direct_native_pipeline=$runner.Contains('& $p.Exe $eboot 2>&1')
}
$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}
if($issues -gt 0){
    Write-Host "$script:Tag PACKAGE VALIDATION FAILED issues=$issues" -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; main-menu-only loop scope; live Patches logging; no temp stderr/stdout lock race)." -ForegroundColor Green
