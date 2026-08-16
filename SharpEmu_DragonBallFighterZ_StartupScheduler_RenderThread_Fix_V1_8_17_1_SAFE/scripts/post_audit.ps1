. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw

$checks=[ordered]@{
 setup_cache_marker=$mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')
 setup_cache_hit=$mt.Contains('exec_setup_cache.v1817 hit')
 setup_cache_primed=$mt.Contains('exec_setup_cache.v1817 primed')
 import_fingerprint=$mt.Contains('ComputeImportSetupFingerprint')
 setup_still_preserved=$mt.Contains('SetupImportStubs(importStubs)')
 tls_create_preserved=$mt.Contains('CreateTlsHandler();')
 tls_patch_preserved=$mt.Contains('PatchTlsPatterns();')
 prewarm_bounded=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));')
 worker_cap_16=([regex]::IsMatch($wt,'NativeWorkerMaxConcurrent\s*=\s*16\s*;'))
 worker_cap_2_removed=(-not [regex]::IsMatch($wt,'NativeWorkerMaxConcurrent\s*=\s*2\s*;'))
}
foreach($kv in $checks.GetEnumerator()){
    Write-Host "[DBFZ-BOOT-18171] $($kv.Key)=$($kv.Value)"
    if(-not $kv.Value){throw "Post-audit failed: $($kv.Key)"}
}
Write-Host "[DBFZ-BOOT-18171] POST-AUDIT PASSED."
