. "$PSScriptRoot\common.ps1"

$pkg=PackageRoot
$required=@(
    'ANALYSIS.txt',
    'FIX_NOTES.txt',
    'README.md',
    'manifest.json',
    'payload\ImeDialogExports.cs',
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
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors) | Out-Null
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

$rt=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\run_test.ps1'))
if(-not $rt.Contains('$pt=NL([IO.File]::ReadAllText((PresenterSource)))')){
    Write-Host "$script:Tag [ERROR] run_test PresenterSource closing-parenthesis regression guard failed." -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; run_test parenthesis regression guard passed)." -ForegroundColor Green
