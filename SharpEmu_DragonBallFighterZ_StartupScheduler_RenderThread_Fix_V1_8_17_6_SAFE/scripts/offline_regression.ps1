$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "common.ps1")

foreach($helper in @(
    'Get-NativeWorkerMaxDeclaration'
)){
    if(-not (Get-Command $helper -CommandType Function -ErrorAction SilentlyContinue)){
        throw "Shared helper not loaded: $helper"
    }
}
Write-Host "[DBFZ-BOOT-18176] OFFLINE COMMON-HELPER LOAD PASSED."

$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
$pre=Get-Content -LiteralPath (Join-Path $PSScriptRoot "precheck.ps1") -Raw
$post=Get-Content -LiteralPath (Join-Path $PSScriptRoot "post_audit.ps1") -Raw
$diag=Get-Content -LiteralPath (Join-Path $PSScriptRoot "diagnostic.ps1") -Raw

foreach($x in @(
 'Source already applied; rebuilding only.',
 'SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17',
 'NativeWorkerMaxConcurrent'
)){
    if(-not $apply.Contains($x)){throw "Continuation build regression missing: $x"}
}

foreach($x in @(
 'Get-FileHash -Algorithm SHA256 -LiteralPath $Game',
 '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018',
 '$elfOffset=-1',
 'SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17',
 'ComputeImportSetupFingerprint',
 'exec_setup_cache.v1817 hit',
 'exec_setup_cache.v1817 primed',
 'PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));',
 'Expected already-applied V1.8.17 source state'
)){
    if(-not $pre.Contains($x)){throw "Applied-state precheck regression missing: $x"}
}

foreach($x in @(
 'setup_cache_marker',
 'worker_cap_16',
 'prewarm_bounded'
)){
    if(-not $post.Contains($x)){throw "Post-audit regression missing: $x"}
}

foreach($x in @(
 'SplashObservedMs',
 'ImportSetupFullCount',
 'ExecSetupCachePrimeCount',
 'ExecSetupCacheHitCount',
 'RenderThreadRunCount',
 'RHIThreadRunCount',
 'AgcSubmissionRunCount',
 'RTHeartBeatRunCount',
 'RenderThreadTimeoutCount',
 'MaxObservedImportNumber',
 '$prewarmLine = if(',
 '$warmLine = if(',
 '$preloadLine = if('
)){
    if(-not $diag.Contains($x)){throw "Diagnostic regression missing: $x"}
}
if($diag.Contains('$((if(')){
    throw "Diagnostic contains invalid statement-form if subexpression."
}

$currentApplied='private static readonly int NativeWorkerMaxConcurrent = 16;'
$d=Get-NativeWorkerMaxDeclaration -Text $currentApplied
if($null -eq $d -or $d.Text -notmatch 'NativeWorkerMaxConcurrent\s*=\s*16\s*;'){
    throw "Applied worker declaration locator regression failed."
}

Write-Host "[DBFZ-BOOT-18176] OFFLINE APPLIED-SOURCE/DIAGNOSTIC REGRESSION PASSED."
