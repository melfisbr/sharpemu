$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "common.ps1")


foreach($helper in @(
    'Get-NativeWorkerMaxDeclaration',
    'Convert-NativeWorkerMaxDeclarationTo16'
)){
    if(-not (Get-Command $helper -CommandType Function -ErrorAction SilentlyContinue)){
        throw "Shared helper not loaded: $helper"
    }
}
Write-Host "[DBFZ-BOOT-18175] OFFLINE COMMON-HELPER LOAD PASSED."

$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
$pre=Get-Content -LiteralPath (Join-Path $PSScriptRoot "precheck.ps1") -Raw
$diag=Get-Content -LiteralPath (Join-Path $PSScriptRoot "diagnostic.ps1") -Raw

foreach($x in @(
 'SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17',
 'ComputeImportSetupFingerprint',
 'exec_setup_cache.v1817 hit',
 'PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'
)){
 if(-not $apply.Contains($x)){throw "Patch payload regression missing: $x"}
}
foreach($x in @(
 'Get-FileHash -Algorithm SHA256 -LiteralPath $Game',
 '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018',
 '$elfOffset=-1',
 'loader-validated inner ELF type=0xFE10 machine=0x003E class=2 abi=9 phnum=14'
)){
 if(-not $pre.Contains($x)){throw "Eboot audit regression missing: $x"}
}
foreach($x in @('SplashObservedMs','ImportSetupFullCount','RenderThreadRunCount','RHIThreadRunCount','AgcSubmissionRunCount','RenderThreadTimeoutCount','MaxObservedImportNumber')){
 if(-not $diag.Contains($x)){throw "Diagnostic regression missing: $x"}
}

# Ensure replacement scope starts at SetupImportStubs and ends at PatchTlsPatterns,
# not at ExecuteEntry or surrounding try/finally.
if(-not ($apply.Contains('$start=$mt.IndexOf("`t`t`tif (!SetupImportStubs(importStubs))"') -and
         $apply.Contains('$endToken="`t`t`tPatchTlsPatterns();"'))){
 throw "Structural replacement boundary regression."
}
Write-Host "[DBFZ-BOOT-18175] OFFLINE PATCH/EBOOT/DIAGNOSTIC REGRESSION PASSED."

$forms=@(
 'private const int NativeWorkerMaxConcurrent = 2;',
 'private static readonly int NativeWorkerMaxConcurrent = 2;',
 'private static int NativeWorkerMaxConcurrent => 2;'
)
foreach($form in $forms){
    $d=Get-NativeWorkerMaxDeclaration -Text $form
    if($null -eq $d){throw "worker declaration regression locator failed: $form"}
    $n=Convert-NativeWorkerMaxDeclarationTo16 -Declaration $d.Text
    if($n -notmatch 'NativeWorkerMaxConcurrent\s*(?:=|=>)\s*16\b'){
        throw "worker declaration regression rewrite failed: $form => $n"
    }
}
$currentApplied='private static readonly int NativeWorkerMaxConcurrent = 16;'
$d=Get-NativeWorkerMaxDeclaration -Text $currentApplied
if($null -eq $d -or $d.Text -notmatch 'NativeWorkerMaxConcurrent\s*=\s*16\s*;'){
    throw "current applied worker declaration regression failed"
}
Write-Host "[DBFZ-BOOT-18175] OFFLINE WORKER DECLARATION SHAPES PASSED."


$applyText=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
if(-not $applyText.Contains('Source already applied; rebuilding only.')){
    throw "Continuation build-only guard missing."
}
Write-Host "[DBFZ-BOOT-18175] OFFLINE CONTINUATION REGRESSION PASSED."
