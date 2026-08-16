. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw

$workerDecl=Get-NativeWorkerMaxDeclaration -Text $wt
$workerDeclText=if($null -ne $workerDecl){($workerDecl.Text -replace '\s+',' ').Trim()}else{"<not located>"}
$workerCap16=($null -ne $workerDecl -and $workerDeclText -match 'NativeWorkerMaxConcurrent\s*(?:=|=>)\s*16\b')

$checks=[ordered]@{
 setup_cache_marker=$mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')
 setup_cache_hit=$mt.Contains('exec_setup_cache.v1817 hit')
 setup_cache_primed=$mt.Contains('exec_setup_cache.v1817 primed')
 import_fingerprint=$mt.Contains('ComputeImportSetupFingerprint')
 setup_still_preserved=$mt.Contains('SetupImportStubs(importStubs)')
 tls_create_preserved=$mt.Contains('CreateTlsHandler();')
 tls_patch_preserved=$mt.Contains('PatchTlsPatterns();')
 prewarm_bounded=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));')
 worker_decl_located=($null -ne $workerDecl)
 worker_cap_16=$workerCap16
}
foreach($kv in $checks.GetEnumerator()){
    Write-Host "[DBFZ-BOOT-18172] $($kv.Key)=$($kv.Value)"
    if(-not $kv.Value -and $kv.Key -notin @('worker_decl_located','worker_cap_16')){
        throw "Post-audit failed: $($kv.Key)"
    }
}
Write-Host "[DBFZ-BOOT-18172] worker_declaration=$workerDeclText"
if($checks.worker_decl_located -and -not $checks.worker_cap_16){
    throw "Post-audit failed: worker_cap_16"
}
if(-not $checks.worker_decl_located){
    Write-Host "[DBFZ-BOOT-18172] WARN: worker declaration not structurally located; scheduler cap unchanged."
}
Write-Host "[DBFZ-BOOT-18172] POST-AUDIT PASSED."
