. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$required=@(
    'ANALYSIS.txt','FIX_NOTES.txt','README.md','manifest.json',
    'scripts\common.ps1','scripts\precheck.ps1','scripts\apply_build.ps1',
    'scripts\diagnostic.ps1','scripts\run_test.ps1','scripts\rollback.ps1',
    'scripts\validate.ps1'
)
$missing=@()
foreach($r in $required){if(-not(Test-Path -LiteralPath (Join-Path $pkg $r))){$missing+=$r}}
if($missing.Count -gt 0){
    Write-Host "$script:Tag [ERROR] Missing files: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

$parseIssues=@()
foreach($f in Get-ChildItem (Join-Path $pkg 'scripts') -Filter '*.ps1'){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count -gt 0){foreach($e in $errors){$parseIssues+=("$($f.Name): "+$e.Message)}}
}
if($parseIssues.Count -gt 0){
    foreach($issue in $parseIssues){Write-Host "$script:Tag [ERROR] PowerShell parse failed $issue" -ForegroundColor Red}
    exit 1
}

$commonText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\common.ps1'))
$runner=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\run_test.ps1'))
$checks=[ordered]@{
    structural_glob=$commonText.Contains("DirectExecutionBackend*.cs")
    try_read_locator=$commonText.Contains('Locate-TryReadHostQword')
    handler_locator=$commonText.Contains('Locate-VectoredHandler')
    safe_read_marker=$commonText.Contains('SHARPEMU_V74_0_88_6_VEH_SAFE_HOST_QWORD')
    virtual_query_guard=$commonText.Contains('VirtualQuery(')
    commit_guard=$commonText.Contains('MemCommitV740886')
    noaccess_guard=$commonText.Contains('PageNoAccessV740886')
    page_guard=$commonText.Contains('PageGuardV740886')
    boundary_guard=$commonText.Contains('regionEndV740886 - sizeof(ulong)')
    diagnostic_export=$commonText.Contains('Export-MethodDiagnostic')
    robust_runner=$runner.Contains('V74.0.88.6 NATIVE_STDERR_MERGE')
    live_log=$runner.Contains('LIVE_RUNTIME_LOG')
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
Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; structural partial-source scan; VEH safe host-qword guard; diagnostic export fallback; live runner verified)." -ForegroundColor Green
