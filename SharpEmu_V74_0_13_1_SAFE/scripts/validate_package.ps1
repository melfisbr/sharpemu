$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.13.1] SHA256SUMS.txt missing."
}

$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "[V74.0.13.1] Invalid hash manifest line: $line"
    }
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.13.1] Package file missing: $relative"
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual-ne$expected){
        throw "[V74.0.13.1] Hash mismatch: $relative expected=$expected actual=$actual"
    }
    $checked++
}

$required=@(
    "scripts\common.ps1",
    "scripts\precheck.ps1",
    "scripts\apply_build.ps1",
    "scripts\run_fastboot.ps1",
    "RUN_1_VALIDATE_PACKAGE.cmd",
    "RUN_2_PRECHECK.cmd",
    "RUN_3_APPLY_BUILD.cmd",
    "RUN_4_DEMONS_FASTBOOT_PERF_HANDOFF.cmd"
)
foreach($relative in $required){
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.13.1] Required package component missing: $relative"
    }
}

Write-Host "[V74.0.13.1] PACKAGE VALIDATION PASSED ($checked hashed files)."
