$ErrorActionPreference="Stop"
$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
$pre=Get-Content -LiteralPath (Join-Path $PSScriptRoot "precheck.ps1") -Raw
$diag=Get-Content -LiteralPath (Join-Path $PSScriptRoot "diagnostic.ps1") -Raw

foreach($x in @(
 'SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17',
 'ComputeImportSetupFingerprint',
 'exec_setup_cache.v1817 hit',
 'NativeWorkerMaxConcurrent = 16;',
 'PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'
)){
 if(-not $apply.Contains($x)){throw "Patch payload regression missing: $x"}
}
foreach($x in @(
 'Get-FileHash -Algorithm SHA256 -LiteralPath $Game',
 '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018',
 '$etype -ne 0xFE10',
 '$machine -ne 0x003E'
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
Write-Host "[DBFZ-BOOT-1817] OFFLINE PATCH/EBOOT/DIAGNOSTIC REGRESSION PASSED."
