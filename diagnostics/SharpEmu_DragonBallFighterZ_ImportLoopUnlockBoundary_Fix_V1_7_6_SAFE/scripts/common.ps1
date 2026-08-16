$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Script:PackageRoot = Split-Path -Parent $PSScriptRoot
$Script:GamePath = 'F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
$Script:ExpectedEbootSha = "106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018"

$Script:ImportsRelative = "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs"
$Script:TraceRelative = "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.DragonBallFighterZAprReadTrace.cs"
$Script:V173Relative = "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.DBFZGetdentsBatch.cs"
$Script:Marker = "SHARPEMU_IMPORT_LOOP_UNLOCK_BOUNDARY_V1_7_6"

$Script:OldBoundary = @'
	private static bool IsImportLoopGuardBoundary(string nid) =>
		nid is
			"1jfXLRVzisc" or // sceKernelUsleep
			"WKAXJ4XBPQ4" or // scePthreadCondWait
			"BmMjYxmew1w" or // scePthreadCondTimedwait
			"Op8TBGY5KHg" or // pthread_cond_wait
			"27bAgiJmOh0";   // pthread_cond_timedwait
'@

$Script:NewBoundary = @'
	// SHARPEMU_IMPORT_LOOP_UNLOCK_BOUNDARY_V1_7_6
	// A successful unlock is proof that guest synchronization is making
	// forward progress. Treat it like sleep/cond-wait for loop-guard history:
	// reset the synthetic import-pattern detector rather than mistaking a
	// healthy lock/use/unlock worker for a stuck unresolved-import loop.
	private static bool IsImportLoopGuardBoundary(string nid) =>
		nid is
			"tn3VlD0hG60" or // scePthreadMutexUnlock
			"2Z+PpY6CaJg" or // pthread_mutex_unlock
			"EgmLo6EWgso" or // scePthreadRwlockUnlock
			"+L98PIbGttk" or // pthread_rwlock_unlock
			"1jfXLRVzisc" or // sceKernelUsleep
			"WKAXJ4XBPQ4" or // scePthreadCondWait
			"BmMjYxmew1w" or // scePthreadCondTimedwait
			"Op8TBGY5KHg" or // pthread_cond_wait
			"27bAgiJmOh0";   // pthread_cond_timedwait
'@

function Get-RepoRoot {
    $repo = (Get-Location).Path
    if (-not (Test-Path -LiteralPath (Join-Path $repo "src\SharpEmu.CLI\SharpEmu.CLI.csproj"))) {
        throw "Run from SharpEmu repository root."
    }
    return $repo
}

function Get-Utf8NoBom {
    return [System.Text.UTF8Encoding]::new($false)
}
