. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw
$d=Get-NativeWorkerDeclaration -Text $wt

$checks=[ordered]@{
 startup_cache_preserved=$mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')
 import_cache_preserved=$mt.Contains('ComputeImportSetupFingerprint')
 worker_cap_32=($null -ne $d -and $d.Value -eq 32)
 prewarm_12=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 12));')
 old_prewarm_8_removed=(-not $mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'))
 guest_runner_preserved=$mt.Contains('new GuestExecutionRunner(')
 ready_dispatch_preserved=$mt.Contains('ScheduleGuestThreadExecution(thread, "ready-dispatch")')
}
foreach($kv in $checks.GetEnumerator()){
    Write-Host "[DBFZ-WORKER-1818] $($kv.Key)=$($kv.Value)"
    if(-not $kv.Value){ throw "Post-audit failed: $($kv.Key)" }
}
Write-Host "[DBFZ-WORKER-1818] POST-AUDIT PASSED."
