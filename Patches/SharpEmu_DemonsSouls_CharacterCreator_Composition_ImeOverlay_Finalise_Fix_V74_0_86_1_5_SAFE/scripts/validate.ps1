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
    [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName,
        [ref]$tokens,
        [ref]$errors) | Out-Null

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
    Write-Host "$script:Tag [ERROR] run_test PresenterSource parenthesis regression guard failed." -ForegroundColor Red
    exit 1
}

$common=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\common.ps1'))

if(-not $common.Contains('Find-LastTopLevelReturnLine')){
    Write-Host "$script:Tag [ERROR] structural final-return finder missing." -ForegroundColor Red
    exit 1
}


$imePayload=[IO.File]::ReadAllText((Join-Path $pkg 'payload\ImeDialogExports.cs'))
$base64Match=[regex]::Match(
    $imePayload,
    'const string encodedScript = "([A-Za-z0-9+/=]+)";')
if(-not $base64Match.Success){
    Write-Host "$script:Tag [ERROR] IME encodedScript Base64 constant not found." -ForegroundColor Red
    exit 1
}
try{
    $decodedImeScript=[Text.Encoding]::Unicode.GetString(
        [Convert]::FromBase64String($base64Match.Groups[1].Value))
}
catch{
    Write-Host "$script:Tag [ERROR] IME encodedScript Base64 decode failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$imeTokens=$null
$imeErrors=$null
[System.Management.Automation.Language.Parser]::ParseInput(
    $decodedImeScript,
    [ref]$imeTokens,
    [ref]$imeErrors) | Out-Null
if($imeErrors.Count -gt 0){
    foreach($e in $imeErrors){
        Write-Host "$script:Tag [ERROR] Embedded IME PowerShell parse failed: $($e.Message)" -ForegroundColor Red
    }
    exit 1
}
if($imePayload.Contains('var script = @"')){
    Write-Host "$script:Tag [ERROR] Legacy C# verbatim-string IME payload still present." -ForegroundColor Red
    exit 1
}


$commonText=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\common.ps1'))
if(-not $commonText.Contains('Get-ImeEmbeddedScript')){
    Write-Host "$script:Tag [ERROR] Base64-aware IME post-apply helper missing." -ForegroundColor Red
    exit 1
}
if($commonText.Contains("if(-not `$it.Contains(`$m))")){
    Write-Host "$script:Tag [ERROR] Legacy plaintext-only IME post-apply assertion regression detected." -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; embedded IME decoded+parsed; Base64-aware post-apply guard passed; structural guards passed)." -ForegroundColor Green
