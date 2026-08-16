. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw
$d=Get-WorkerCap -Text $wt
$checks=[ordered]@{
 startup_cache_preserved=$mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')
 worker_cap_16=($null -ne $d -and $d.Value -eq 16)
 prewarm_8=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));')
 prewarm_12_removed=(-not $mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 12));'))
 snapshot_facility_preserved=$mt.Contains('guest_thread.snapshot')
 ready_dispatch_preserved=$mt.Contains('DispatchReadyGuestThreads();')
}
foreach($kv in $checks.GetEnumerator()){
    Write-Host "[DBFZ-OWN-1819] $($kv.Key)=$($kv.Value)"
    if(-not $kv.Value){ throw "Post-audit failed: $($kv.Key)" }
}
Write-Host "[DBFZ-OWN-1819] POST-AUDIT PASSED."
