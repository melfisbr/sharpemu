param([string]$PackageRoot="")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$candidate = $PackageRoot
if([string]::IsNullOrWhiteSpace($candidate)){
    $candidate = Split-Path -Parent $PSScriptRoot
}

$candidate = ($candidate -replace '^\s+|\s+$','')
$candidate = ($candidate -replace '^"|"$','')
$candidate = ($candidate -replace '[\\/]+$','')
$root = (Resolve-Path -LiteralPath $candidate).Path

$manifest = Join-Path $root "SHA256SUMS.txt"
$count = 0

foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}

    $m = [regex]::Match($line,'^([0-9a-fA-F]{64})  (.+)$')
    if(-not $m.Success){
        throw "[NIHAV-RAW] Invalid manifest line."
    }

    $path = Join-Path $root ($m.Groups[2].Value.Replace('/','\'))
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "[NIHAV-RAW] Missing file: $($m.Groups[2].Value)"
    }

    $actual = (
        Get-FileHash -LiteralPath $path -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if($actual -ne $m.Groups[1].Value.ToLowerInvariant()){
        throw "[NIHAV-RAW] Hash mismatch: $($m.Groups[2].Value)"
    }

    $count++
}

foreach($ps1 in Get-ChildItem `
    -LiteralPath (Join-Path $root "scripts") `
    -Filter *.ps1 `
    -File){

    $tokens = $null
    $errors = $null

    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,
        [ref]$tokens,
        [ref]$errors)

    if($errors.Count -gt 0){
        throw (
            "[NIHAV-RAW] PowerShell parse failed: " +
            $ps1.Name +
            " :: " +
            $errors[0].Message)
    }
}

$runner = [IO.File]::ReadAllText(
    (Join-Path $root "scripts\capture_raw_truth.ps1"))

foreach($required in @(
    'V72.4.3.2.26.0.16 NIHAV_RAW_FRAME_TRUTH',
    'V72.4.3.2.26.0.16.0.1 VALIDATOR_DYNAMIC_OUTPUT_FIX',
    '-an -nm=frmpts -vpfx',
    'logo_intro.bk2',
    'attract_movie.bk2',
    'Name = "logo_intro_t4"',
    'Name = "attract_t30"',
    '$test.Name + "_RAW.pgm"',
    'RAW_SHA256=',
    'PGM_HEADER=',
    'SOURCE_CHANGE=NONE',
    'BUILD=NONE'
)){
    if(-not $runner.Contains($required)){
        throw "[NIHAV-RAW] Required marker missing: $required"
    }
}

foreach($pattern in @(
    '(?im)^\s*git\s+(pull|fetch|clone)\b',
    '(?im)^\s*cargo\s+build\b',
    '(?im)^\s*dotnet(?:\.exe)?\s+build\b',
    '(?im)^\s*Set-Content\b.*src\\',
    '(?im)^\s*Add-Content\b.*src\\',
    '(?im)^\s*Copy-Item\b.*plugins\\bink2\\nihav-tool\.exe'
)){
    if([regex]::IsMatch($runner,$pattern)){
        throw "[NIHAV-RAW] Forbidden source/build/runtime mutation: $pattern"
    }
}

Write-Host (
    "[NIHAV-RAW 26.0.16.0.1] PACKAGE VALIDATION PASSED (" +
    $count +
    " hashed files + parser + direct-raw-frame capture + no-source-change audit).")
