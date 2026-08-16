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
 'PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'
)){
    if(-not $mt.Contains($x)){ throw "V1.8.17 prerequisite missing: $x" }
}

$d=Get-NativeWorkerDeclaration -Text $wt
if($null -eq $d){ throw "NativeWorkerMaxConcurrent literal declaration not found." }
if($d.Value -notin @(16,32)){ throw "Unexpected NativeWorkerMaxConcurrent=$($d.Value)" }

$state=if($d.Value -eq 32 -and $mt.Contains('PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 12));')){
    'AlreadyApplied'
} elseif($d.Value -eq 16) {
    'ReadyToApply'
} else {
    'Inconsistent'
}
if($state -eq 'Inconsistent'){ throw "Inconsistent V1.8.18 source state." }

Write-Host "[DBFZ-WORKER-1818] RepoRoot=$repo"
Write-Host "[DBFZ-WORKER-1818] EBOOT SHA256=$sha"
Write-Host "[DBFZ-WORKER-1818] WorkerDeclaration=$($d.Text.Trim())"
Write-Host "[DBFZ-WORKER-1818] State=$state"
Write-Host "[DBFZ-WORKER-1818] PRECHECK PASSED."
