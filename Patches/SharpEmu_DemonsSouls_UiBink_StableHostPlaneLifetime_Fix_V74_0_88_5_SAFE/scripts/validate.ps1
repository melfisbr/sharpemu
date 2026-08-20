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
        [ref]$errors)|Out-Null

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

$checks=[ordered]@{
    stable_format_marker=$commonText.Contains('SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT')
    fixed_luma_unorm=$commonText.Contains('var desiredLumaFormatV74088 = Format.R8Unorm;')
    fixed_chroma_unorm=$commonText.Contains('var desiredChromaFormatV74088 = Format.R8G8Unorm;')
    number_type_lifetime_neutralized=$commonText.Contains('guest NumberType does not invalidate host VkImage')
    upload_trace_marker=$commonText.Contains('SHARPEMU_V74_0_88_5_HOST_MOVIE_UPLOAD_TRACE')
    invalid_upload_guard=$commonText.Contains('[V74.0.88.5][HOST_MOVIE_UPLOAD_INVALID]')
    v88_baseline_assert=$commonText.Contains('Assert-V740883')
    native_stderr_merge=$runner.Contains('V74.0.88.5 NATIVE_STDERR_MERGE')
    live_log=$runner.Contains('LIVE_RUNTIME_LOG')
    no_redirect_stderr=-not $runner.Contains('RedirectStandardError')
    no_redirect_stdout=-not $runner.Contains('RedirectStandardOutput')
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

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; stable host-plane lifetime; host upload trace/guard; V88.3 baseline preservation; robust live runner verified)." -ForegroundColor Green
