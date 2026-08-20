. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

if($e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')){
    Write-Host '[V74.0.67.2.12] Secondary BPE caller recovery already applied.'
    return
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
        throw "[V74.0.67.2.12] Anchor '$Label' count=$count expected=1"
    }
    return $Text.Replace($Old,$New)
}

if(!$e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')){
    throw '[V74.0.67.2.12] Required V2.11 BPE return repair is missing.'
}

$oldThreadGuard=@'
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
'@

$newThreadGuard=@'
		GuestThreadState? activeThread = _activeGuestThreadState;
		if (activeThread is null ||
			!activeThread.Name.StartsWith(
				"BPE JobWorkerThread",
				StringComparison.Ordinal))
		{
			return false;
		}

		// V74.0.67.2.12 BPE secondary-caller sentinel recovery.
		string? lastImportNid =
			Volatile.Read(ref activeThread.LastImportNid);
		bool primaryImport = string.Equals(
			lastImportNid,
			"tcVi5SivF7Q",
			StringComparison.Ordinal);
		bool secondaryImport = string.Equals(
			lastImportNid,
			"GuchCTefuZw",
			StringComparison.Ordinal);

		if (!primaryImport && !secondaryImport)
		{
			return false;
		}
'@
$e=Replace-One $e $oldThreadGuard $newThreadGuard 'BPE import-path guard'

$oldRegisters=@'
		ulong rcx = ReadCtxU64(ctx, CTX_RCX);
		ulong rax = ReadCtxU64(ctx, CTX_RAX);
		ulong rdi = ReadCtxU64(ctx, CTX_RDI);
		ulong r14 = ReadCtxU64(ctx, CTX_R14);
		if (rcx != 1 ||
			rax != 1 ||
			rdi != r14 ||
			!IsCanonicalUserPointer(rdi))
		{
			return false;
		}
'@

$newRegisters=@'
		ulong rcx = ReadCtxU64(ctx, CTX_RCX);
		ulong rax = ReadCtxU64(ctx, CTX_RAX);
		ulong rdi = ReadCtxU64(ctx, CTX_RDI);
		ulong r13 = ReadCtxU64(ctx, CTX_R13);
		ulong r14 = ReadCtxU64(ctx, CTX_R14);
		ulong r15 = ReadCtxU64(ctx, CTX_R15);
		ulong rsp = ReadCtxU64(ctx, CTX_RSP);

		if (rcx != 1 ||
			rax != 1 ||
			!IsCanonicalUserPointer(rdi))
		{
			return false;
		}

		bool primaryCaller = primaryImport && rdi == r14;
		bool secondaryCaller = secondaryImport && rdi == r13;
		if (!primaryCaller && !secondaryCaller)
		{
			return false;
		}
'@
$e=Replace-One $e $oldRegisters $newRegisters 'BPE caller-register shape'

$oldPayloadEnd=@'
		if (!TryReadHostQword(rdi, out ulong head) ||
			head != 1 ||
			!TryReadHostQword(rdi + 8, out ulong adjacent) ||
			adjacent != 0 ||
			!TryReadHostQword(rdi + 0x10, out ulong payload) ||
			!IsCanonicalUserPointer(payload))
		{
			return false;
		}

		// V74.0.67.2.11 BPE end-sentinel return repair.
'@

$newPayloadEnd=@'
		if (!TryReadHostQword(rdi, out ulong head) ||
			head != 1 ||
			!TryReadHostQword(rdi + 8, out ulong adjacent) ||
			adjacent != 0 ||
			!TryReadHostQword(rdi + 0x10, out ulong payload) ||
			!IsCanonicalUserPointer(payload))
		{
			return false;
		}

		string callerVariant = "primary-r14";

		if (secondaryCaller)
		{
			// Exact observed post-call shape:
			// mov r13,rax; cmp rax,r15; je <rel8>; mov eax,[r13+0x20].
			// Validate it through the guest return address, without embedding
			// an absolute RIP/caller address.
			if (r15 != payload ||
				!TryReadHostQword(rsp, out ulong returnAddress) ||
				!IsCanonicalUserPointer(returnAddress) ||
				!TryReadHostQword(returnAddress, out ulong callerBytes0) ||
				!TryReadHostQword(returnAddress + 8, out ulong callerBytes1) ||
				callerBytes0 != 0x8374F8394CC58949UL ||
				(callerBytes1 & 0xFFFFFFFFUL) != 0x20458B41UL)
			{
				return false;
			}

			callerVariant = "secondary-r13-r15";
		}

		// V74.0.67.2.11 BPE end-sentinel return repair.
'@
$e=Replace-One $e $oldPayloadEnd $newPayloadEnd 'BPE secondary caller exact validation'

$oldTelemetry=@'
				$"count={recovery} worker='{activeThread.Name}' " +
				$"rip=0x{rip:X16} target=0x9 " +
				$"head=0x{head:X} adjacent=0x{adjacent:X} " +
				$"payload=0x{payload:X16} -> rax=payload rcx=0 next=0x{rip + 4:X16}");
'@

$newTelemetry=@'
				$"count={recovery} worker='{activeThread.Name}' " +
				$"rip=0x{rip:X16} target=0x9 " +
				$"variant={callerVariant} last_import={lastImportNid} " +
				$"head=0x{head:X} adjacent=0x{adjacent:X} " +
				$"payload=0x{payload:X16} -> rax=payload rcx=0 next=0x{rip + 4:X16}");
'@
$e=Replace-One $e $oldTelemetry $newTelemetry 'BPE caller-variant telemetry'

[IO.File]::WriteAllText(
    $exceptionsPath,
    (Restore-Newlines $e),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.12] BPE SECONDARY-CALLER SENTINEL RECOVERY APPLIED.'
