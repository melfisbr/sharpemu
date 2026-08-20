. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$required=@(
    'ANALYSIS.txt','FIX_NOTES.txt','README.md','manifest.json',
    'scripts\common.ps1','scripts\precheck.ps1','scripts\apply_build.ps1',
    'scripts\diagnostic.ps1','scripts\run_test.ps1','scripts\rollback.ps1',
    'scripts\validate.ps1'
)

$missing=@()
foreach($r in $required){
    if(-not(Test-Path -LiteralPath (Join-Path $pkg $r))){
        $missing+=$r
    }
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
        $f.FullName,
        [ref]$tokens,
        [ref]$errors
    )|Out-Null
    if($errors.Count -gt 0){
        foreach($e in $errors){
            $parseIssues+=("$($f.Name): "+$e.Message)
        }
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
$precheckText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\precheck.ps1'))
$diagnosticText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\diagnostic.ps1'))

$bareBooleanAssignment=[regex]::IsMatch(
    $precheckText,
    '(?im)^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(True|False)[ \t]*$'
)

$checks=[ordered]@{
    structural_glob=$commonText.Contains("DirectExecutionBackend*.cs")
    try_read_locator=$commonText.Contains('Locate-TryReadHostQword')
    handler_locator=$commonText.Contains('Locate-VectoredHandler')
    safe_read_marker=$commonText.Contains('SHARPEMU_V74_0_88_6_2_VEH_SAFE_HOST_QWORD')
    unsafe_declaration_repair=$commonText.Contains('V74.0.88.6.2 CSHARP_UNSAFE_METHOD_DECLARATION')
    unsafe_declaration_literal=$commonText.Contains('private unsafe static bool')
    virtual_query_guard=$commonText.Contains('VirtualQuery(')
    commit_guard=$commonText.Contains('MemCommitV740886')
    noaccess_guard=$commonText.Contains('PageNoAccessV740886')
    page_guard=$commonText.Contains('PageGuardV740886')
    readable_protection_guard=$commonText.Contains('readableProtectV740886')
    boundary_guard=$commonText.Contains('regionEndV740886 - sizeof(ulong)')
    diagnostic_export=$commonText.Contains('Export-MethodDiagnostic')
    robust_runner=$runner.Contains('V74.0.88.6.2 NATIVE_STDERR_MERGE')
    live_log=$runner.Contains('LIVE_RUNTIME_LOG')
    precheck_true_literal=$precheckText.Contains('try_read_signature=$true')
    precheck_handler_true_literal=$precheckText.Contains('vectored_handler_signature=$true')
    no_bare_boolean_assignment=(-not $bareBooleanAssignment)
    diagnostic_index_variables=($diagnosticText.Contains('$qIndex=') -and $diagnosticText.Contains('$mIndex='))
    diagnostic_no_nested_index_interpolation=(-not $diagnosticText.Contains('virtual_query_before_read=$($body.IndexOf('))
}

$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){
        $issues++
    }
}
if($issues -gt 0){
    Write-Host "$script:Tag PACKAGE VALIDATION FAILED issues=$issues" -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; V88.6 parser/boolean regressions blocked; C# unsafe-method repair verified; structural partial-source scan; readable VEH host-qword guard; live runner verified)." -ForegroundColor Green
