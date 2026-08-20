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

$runner=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\run_test.ps1'))
$checks=[ordered]@{
    live_runtime_log=$runner.Contains('LIVE_RUNTIME_LOG')
    native_stderr_merge_marker=$runner.Contains('V74.0.88.4 NATIVE_STDERR_MERGE')
    uses_comspec=$runner.Contains('& $env:ComSpec /D /S /C $cmdLine')
    cmd_owns_2to1=$runner.Contains('$cmdLine=') -and $runner.Contains('2>&1')
    old_direct_native_removed=-not $runner.Contains('& $p.Exe $eboot 2>&1')
    temp_stderr_removed=-not $runner.Contains('RedirectStandardError')
    temp_stdout_removed=-not $runner.Contains('RedirectStandardOutput')
    autoflush=$runner.Contains('$writer.AutoFlush=$true')
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

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; cmd-owned native stderr merge; live Patches logging; no NativeCommandError path)." -ForegroundColor Green
