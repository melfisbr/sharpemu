. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$path=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$e=Normalize-Lf ([IO.File]::ReadAllText($path))

$marker='V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery'
if($e.Contains($marker)){
    Write-Host '[V74.0.67.2.21] HighGraphics pthread-exit recovery already applied.'
    return
}

foreach($required in @(
    'private unsafe int VectoredHandler(void* exceptionInfo)',
    'TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip)',
    'private unsafe bool TryRecoverAuxiliaryThreadExecuteFault(',
    'ActiveEntryReturnSentinelRip',
    'TryPatchActiveGuestReturnSlot(',
    'V74.0.67.2.11 BPE end-sentinel return repair',
    'V74.0.67.2.12 BPE secondary-caller sentinel recovery',
    'V74.0.67.2.18 BPE head2 end-sentinel recovery'))
{
    if(!$e.Contains($required)){
        throw "[V74.0.67.2.21] Required accumulated source marker missing: $required"
    }
}

# Counter near existing execute-fault counters.
$counterAnchor='	private static int _auxiliaryThreadExecuteFaultSkips;'
$counterCount=Count-Ordinal -Text $e -Needle $counterAnchor
if($counterCount-ne 1){
    throw "[V74.0.67.2.21] Counter anchor count=$counterCount expected=1"
}
$counterInsert=@'

	// V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery.
	private static int _highGraphicsPthreadExitNullCallbackRecoveriesV74067221;
'@
$e=$e.Replace($counterAnchor,$counterAnchor+$counterInsert)

# The exact recovery must run before generic TBB/auxiliary execute recovery.
$handlerAnchor=@'
			if (TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip))
			{
				return -1;
			}
'@
$handlerCount=Count-Ordinal -Text $e -Needle $handlerAnchor
if($handlerCount-ne 1){
    throw "[V74.0.67.2.21] VEH execute-recovery anchor count=$handlerCount expected=1"
}

$handlerInsert=@'
			// V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery.
			if (TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(
					exceptionRecord,
					contextRecord,
					rip))
			{
				return -1;
			}

'@
$e=$e.Replace($handlerAnchor,$handlerInsert+$handlerAnchor)

# Insert helper immediately before the existing auxiliary execute-fault recovery.
$methodAnchor=@'
	private unsafe bool TryRecoverAuxiliaryThreadExecuteFault(
'@
$methodCount=Count-Ordinal -Text $e -Needle $methodAnchor
if($methodCount-ne 1){
    throw "[V74.0.67.2.21] Auxiliary recovery method anchor count=$methodCount expected=1"
}

$method=@'
	// V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery.
	//
	// Runtime proof:
	//   AV code      = 0xC0000005
	//   AV kind      = execute
	//   RIP/target   = 0
	//   guest thread = HighGraphics
	//   active import= scePthreadExit (3kg7rT0NQIs)
	//   import result_valid = false
	//
	// scePthreadExit is a noreturn operation. SharpEmu intentionally runs
	// guest TLS/runtime cleanup callbacks before RequestCurrentEntryExit.
	// A null indirect call inside that cleanup must terminate only the
	// failing cleanup callback, not the whole emulator process. Redirect
	// the nested guest callback to its active host-return sentinel. Control
	// then returns to managed pthread-exit cleanup, which continues and
	// requests the normal guest-thread exit itself.
	//
	// This is deliberately NOT a generic RIP=0 recovery. Every gate below
	// must match the captured HighGraphics pthread-exit-in-progress case.
	private unsafe bool TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(
		EXCEPTION_RECORD* exceptionRecord,
		void* contextRecord,
		ulong rip)
	{
		if (string.Equals(
				Environment.GetEnvironmentVariable(
					"SHARPEMU_DISABLE_HIGHGRAPHICS_PTHREAD_EXIT_NULL_RECOVERY"),
				"1",
				StringComparison.Ordinal) ||
			exceptionRecord == null ||
			contextRecord == null ||
			exceptionRecord->ExceptionCode != 3221225477u ||
			exceptionRecord->NumberParameters < 2 ||
			exceptionRecord->ExceptionInformation[0] != 8 ||
			exceptionRecord->ExceptionInformation[1] != 0 ||
			rip != 0)
		{
			return false;
		}

		var activeThread = _activeGuestThreadState;
		if (activeThread is null ||
			!string.Equals(
				activeThread.Name,
				"HighGraphics",
				StringComparison.Ordinal) ||
			!string.Equals(
				Volatile.Read(ref activeThread.LastImportNid),
				"3kg7rT0NQIs",
				StringComparison.Ordinal) ||
			Volatile.Read(ref activeThread.LastImportResultValid) != 0 ||
			activeThread.LastImportRdi != 0 ||
			activeThread.LastReturnRip < 0x10000)
		{
			return false;
		}

		var hostExit = ActiveEntryReturnSentinelRip;
		if (hostExit < 0x10000 ||
			!TryPatchActiveGuestReturnSlot(hostExit))
		{
			return false;
		}

		// Match the already-established auxiliary callback-return strategy:
		// return a neutral callback value and resume at the active host exit.
		// Do not abort/abandon HighGraphics; scePthreadExit still owns the
		// thread's clean termination after this nested callback unwinds.
		WriteCtxU64(contextRecord, 120, 0);
		WriteCtxU64(contextRecord, 248, hostExit);

		var recovery = Interlocked.Increment(
			ref _highGraphicsPthreadExitNullCallbackRecoveriesV74067221);

		if (recovery <= 32 || (recovery & (recovery - 1)) == 0)
		{
			Console.Error.WriteLine(
				$"[V74.0.67.2.21][PTHREAD_EXIT_NULL_CALLBACK] " +
				$"count={recovery} thread=HighGraphics " +
				$"nid=3kg7rT0NQIs result_valid=0 " +
				$"av=execute-null return=host-exit " +
				$"host_exit=0x{hostExit:X16}");
			Console.Error.Flush();
		}

		return true;
	}

'@
$idx=$e.IndexOf($methodAnchor,[StringComparison]::Ordinal)
$e=$e.Substring(0,$idx)+$method+$e.Substring($idx)

foreach($proof in @(
    'V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery',
    'TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(',
    'exceptionRecord->ExceptionInformation[0] != 8',
    'exceptionRecord->ExceptionInformation[1] != 0',
    'rip != 0',
    '"HighGraphics"',
    '"3kg7rT0NQIs"',
    'LastImportResultValid) != 0',
    'activeThread.LastImportRdi != 0',
    'TryPatchActiveGuestReturnSlot(hostExit)',
    'WriteCtxU64(contextRecord, 120, 0);',
    'WriteCtxU64(contextRecord, 248, hostExit);',
    '[V74.0.67.2.21][PTHREAD_EXIT_NULL_CALLBACK]',
    'V74.0.67.2.18 BPE head2 end-sentinel recovery'))
{
    if(!$e.Contains($proof)){
        throw "[V74.0.67.2.21] Post-transform proof missing: $proof"
    }
}

# Prove call ordering in the final in-memory source.
$newCall=$e.IndexOf(
    'TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(',
    [StringComparison]::Ordinal)
$auxCall=$e.IndexOf(
    'TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip)',
    [StringComparison]::Ordinal)
if($newCall-lt 0 -or $auxCall-lt 0 -or $newCall-ge $auxCall){
    throw '[V74.0.67.2.21] Recovery call is not before generic auxiliary execute recovery.'
}

[IO.File]::WriteAllText(
    $path,
    (Restore-Newlines $e),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.21] HIGHGRAPHICS PTHREAD-EXIT NULL-CALLBACK RECOVERY APPLIED.'
