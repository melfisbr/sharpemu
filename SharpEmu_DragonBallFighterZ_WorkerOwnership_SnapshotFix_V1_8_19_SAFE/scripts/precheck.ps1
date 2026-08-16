param(
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw

if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){ throw "DBFZ eboot missing: $Game" }
$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $Game).Hash.ToLowerInvariant()
if($sha -ne '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018'){
    throw "Unexpected DBFZ eboot SHA256: $sha"
}
foreach($x in @(
 'SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17',
 'ComputeImportSetupFingerprint',
 'guest_thread.snapshot',
 'StartReadyThreadDispatcher()',
 'DispatchReadyGuestThreads();'
)){
    if(-not $mt.Contains($x)){ throw "Required scheduler/source evidence missing: $x" }
}
$d=Get-WorkerCap -Text $wt
if($null -eq $d){ throw "NativeWorkerMaxConcurrent literal declaration not found." }
if($d.Value -notin @(16,32)){ throw "Unexpected worker cap: $($d.Value)" }

$pre8=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));')
$pre12=$mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 12));')
if($d.Value -eq 32 -and $pre12){ $state='NeedsRollbackTo16' }
elseif($d.Value -eq 16 -and $pre8){ $state='AlreadyNormalized' }
else{ throw "Inconsistent worker/prewarm state." }

Write-Host "[DBFZ-OWN-1819] EBOOT SHA256=$sha"
Write-Host "[DBFZ-OWN-1819] WorkerCap=$($d.Value)"
Write-Host "[DBFZ-OWN-1819] Prewarm8=$pre8 Prewarm12=$pre12"
Write-Host "[DBFZ-OWN-1819] State=$state"
Write-Host "[DBFZ-OWN-1819] PRECHECK PASSED."
