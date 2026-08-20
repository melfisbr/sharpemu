. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$marker='V74.0.67.2.18 BPE head2 end-sentinel recovery'
if($e.Contains($marker)){
    Write-Host '[V74.0.67.2.18] BPE head2 recovery already applied.'
    return
}

foreach($required in @(
    'V74.0.67.2.11 BPE end-sentinel return repair',
    'V74.0.67.2.12 BPE secondary-caller sentinel recovery',
    'TryRecoverDemonBpeLowSentinelListFaultV74067241'))
{
    if(!$e.Contains($required)){
        throw "[V74.0.67.2.18] Required accumulated BPE marker missing: $required"
    }
}

function Replace-One {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $count=Count-Ordinal -Text $Text -Needle $Old
    if($count-ne 1){
        throw "[V74.0.67.2.18] Anchor '$Label' count=$count expected=1"
    }
    return $Text.Replace($Old,$New)
}

function Insert-Before-One {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Anchor,
        [Parameter(Mandatory=$true)][string]$Insertion,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $count=Count-Ordinal -Text $Text -Needle $Anchor
    if($count-ne 1){
        throw "[V74.0.67.2.18] Anchor '$Label' count=$count expected=1"
    }
    $index=$Text.IndexOf($Anchor,[StringComparison]::Ordinal)
    return $Text.Substring(0,$index)+$Insertion+$Text.Substring($index)
}

# Counter.
$counterOld=@'
	private static int _demonBpeLowSentinelRecoveriesV74067241; // V74.0.67.2.4.1 BPE low-sentinel list recovery
'@

$counterNew=@'
	private static int _demonBpeLowSentinelRecoveriesV74067241; // V74.0.67.2.4.1 BPE low-sentinel list recovery
	private static int _demonBpeHead2SentinelRecoveriesV74067218; // V74.0.67.2.18 BPE head2 end-sentinel recovery
'@

$e=Replace-One $e $counterOld $counterNew 'BPE head2 counter'

# Handler call. It runs before the older target=0x9 recovery and therefore
# cannot weaken any existing V2.11/V2.12 gate.
$callOld=@'
			// V74.0.67.2.4.1 BPE low-sentinel list recovery
			if (exceptionCode == 3221225477u &&
				TryRecoverDemonBpeLowSentinelListFaultV74067241(
					exceptionRecord,
					contextRecord,
					rip))
			{
				return -1;
			}
'@

$callNew=@'
			// V74.0.67.2.18 BPE head2 end-sentinel recovery.
			if (exceptionCode == 3221225477u &&
				TryRecoverDemonBpeHead2EndSentinelFaultV74067218(
					exceptionRecord,
					contextRecord,
					rip))
			{
				return -1;
			}

			// V74.0.67.2.4.1 BPE low-sentinel list recovery
			if (exceptionCode == 3221225477u &&
				TryRecoverDemonBpeLowSentinelListFaultV74067241(
					exceptionRecord,
					contextRecord,
					rip))
			{
				return -1;
			}
'@

$e=Replace-One $e $callOld $callNew 'BPE head2 handler call'

$methodAnchor='	// V74.0.67.2.4.1 BPE low-sentinel linked-list recovery.'

$method=@'
	// V74.0.67.2.18 BPE head2 end-sentinel recovery.
	//
	// Exact semantic variant only:
	// - read AV at low target 0xA;
	// - RCX=RAX=2 at the linked-list traversal;
	// - BPE JobWorkerThread;
	// - primary tcVi5SivF7Q caller with RDI==R14;
	// - exact helper instruction signature;
	// - container [0]=2, [8]=0, [0x10]=canonical payload;
	// - exact primary post-call shape:
	//     mov r14,rax
	//     cmp rax,[rbp-0xC70]
	//     je ...
	//     mov eax,[r14+0x20]
	// - caller [rbp-0xC70] must equal the same canonical payload.
	//
	// No absolute guest RIP, caller address, container address or payload
	// address is embedded. Unrelated AVs continue to the normal handler.
	private unsafe static bool TryRecoverDemonBpeHead2EndSentinelFaultV74067218(
		EXCEPTION_RECORD* er,
		void* ctx,
		ulong rip)
	{
		if (string.Equals(
				Environment.GetEnvironmentVariable(
					"SHARPEMU_DISABLE_DEMON_BPE_HEAD2_SENTINEL_RECOVERY"),
				"1",
				StringComparison.Ordinal) ||
			er == null ||
			ctx == null ||
			er->NumberParameters < 2 ||
			er->ExceptionInformation[0] != 0 ||
			er->ExceptionInformation[1] != 0xA ||
			rip < 0x10013)
		{
			return false;
		}

		GuestThreadState? activeThread = _activeGuestThreadState;
		if (activeThread is null ||
			!activeThread.Name.StartsWith(
				"BPE JobWorkerThread",
				StringComparison.Ordinal) ||
			!string.Equals(
				Volatile.Read(ref activeThread.LastImportNid),
				"tcVi5SivF7Q",
				StringComparison.Ordinal))
		{
			return false;
		}

		ulong rcx = ReadCtxU64(ctx, CTX_RCX);
		ulong rax = ReadCtxU64(ctx, CTX_RAX);
		ulong rdi = ReadCtxU64(ctx, CTX_RDI);
		ulong rbp = ReadCtxU64(ctx, CTX_RBP);
		ulong rsp = ReadCtxU64(ctx, CTX_RSP);
		ulong r14 = ReadCtxU64(ctx, CTX_R14);

		if (rcx != 2 ||
			rax != 2 ||
			rdi != r14 ||
			!IsCanonicalUserPointer(rdi) ||
			!IsCanonicalUserPointer(rbp) ||
			!IsCanonicalUserPointer(rsp) ||
			rbp < 0xC70)
		{
			return false;
		}

		// Exact linked-list traversal helper:
		// mov rcx,[rcx+8]; test rcx,rcx; jne -12; ret
		byte* code = (byte*)rip;
		byte[] signature =
		{
			0x48, 0x8B, 0x49, 0x08,
			0x48, 0x85, 0xC9,
			0x75, 0xF4,
			0xC3
		};
		for (int i = 0; i < signature.Length; i++)
		{
			if (code[i] != signature[i])
			{
				return false;
			}
		}

		if (!TryReadHostQword(rdi, out ulong head) ||
			head != 2 ||
			!TryReadHostQword(rdi + 8, out ulong adjacent) ||
			adjacent != 0 ||
			!TryReadHostQword(rdi + 0x10, out ulong payload) ||
			!IsCanonicalUserPointer(payload))
		{
			return false;
		}

		// Validate the actual primary caller structurally through its return
		// address. The JE displacement is intentionally ignored; the opcodes,
		// rbp displacement and r14 dereference are exact.
		if (!TryReadHostQword(rsp, out ulong returnAddress) ||
			!IsCanonicalUserPointer(returnAddress) ||
			!TryReadHostQword(returnAddress, out ulong callerBytes0) ||
			!TryReadHostQword(returnAddress + 8, out ulong callerBytes1) ||
			!TryReadHostQword(returnAddress + 16, out ulong callerBytes2) ||
			callerBytes0 != 0xF390853B48C68949UL ||
			(callerBytes1 & 0xFFFFFFFFUL) != 0x840FFFFFUL ||
			(callerBytes2 & 0xFFFFFFFFUL) != 0x20468B41UL)
		{
			return false;
		}

		ulong callerEndSlot = rbp - 0xC70;
		if (!TryReadHostQword(
				callerEndSlot,
				out ulong callerEndSentinel) ||
			callerEndSentinel != payload)
		{
			return false;
		}

		// Same caller contract already proven by V2.11: the end iterator is
		// the canonical payload pointer, not null. Resume after the faulting
		// mov rcx,[rcx+8], clear RCX so the helper's test/jne/ret exits, and
		// return payload in RAX. The guest caller then takes its own equality
		// branch and remains in control.
		WriteCtxU64(ctx, CTX_RAX, payload);
		WriteCtxU64(ctx, CTX_RCX, 0);
		WriteCtxU64(ctx, CTX_RIP, rip + 4);

		int recovery = Interlocked.Increment(
			ref _demonBpeHead2SentinelRecoveriesV74067218);
		if (recovery <= 32 || (recovery & (recovery - 1)) == 0)
		{
			Console.Error.WriteLine(
				$"[V74.0.67.2.18][BPE_HEAD2_SENTINEL_RECOVERY] " +
				$"count={recovery} worker='{activeThread.Name}' " +
				$"target=0xA variant=primary-r14 " +
				$"last_import={activeThread.LastImportNid} " +
				$"head=0x{head:X} adjacent=0x{adjacent:X} " +
				$"caller_end_matches_payload=1 " +
				$"payload=0x{payload:X16} " +
				$"-> rax=payload rcx=0 next=0x{rip + 4:X16}");
			Console.Error.Flush();
		}

		return true;
	}

'@

$e=Insert-Before-One $e $methodAnchor $method 'BPE head2 exact method insertion'

# Final transformation proof.
foreach($proof in @(
    'V74.0.67.2.18 BPE head2 end-sentinel recovery',
    'TryRecoverDemonBpeHead2EndSentinelFaultV74067218',
    'er->ExceptionInformation[1] != 0xA',
    'rcx != 2',
    'rax != 2',
    'rdi != r14',
    'head != 2',
    'callerBytes0 != 0xF390853B48C68949UL',
    '(callerBytes1 & 0xFFFFFFFFUL) != 0x840FFFFFUL',
    '(callerBytes2 & 0xFFFFFFFFUL) != 0x20468B41UL',
    'callerEndSlot = rbp - 0xC70',
    'callerEndSentinel != payload',
    'WriteCtxU64(ctx, CTX_RAX, payload);',
    'WriteCtxU64(ctx, CTX_RCX, 0);',
    'WriteCtxU64(ctx, CTX_RIP, rip + 4);',
    '[V74.0.67.2.18][BPE_HEAD2_SENTINEL_RECOVERY]',
    'V74.0.67.2.12 BPE secondary-caller sentinel recovery'))
{
    if(!$e.Contains($proof)){
        throw "[V74.0.67.2.18] Post-transform proof missing: $proof"
    }
}

[IO.File]::WriteAllText(
    $exceptionsPath,
    (Restore-Newlines $e),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.18] BPE HEAD2 END-SENTINEL EXACT-CALLER RECOVERY APPLIED.'
