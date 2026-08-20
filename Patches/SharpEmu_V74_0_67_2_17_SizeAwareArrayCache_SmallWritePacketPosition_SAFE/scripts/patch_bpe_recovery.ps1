. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

if($e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')){
    Write-Host '[V74.0.67.2.11] BPE end-sentinel return repair already applied.'
    return
}

$old=@'
		// Interpret the impossible low sentinel as an empty list, then let the
		// guest execute its own test/jne/ret sequence.
		WriteCtxU64(ctx, CTX_RAX, 0);
		WriteCtxU64(ctx, CTX_RCX, 0);
		WriteCtxU64(ctx, CTX_RIP, rip + 4);
'@

$new=@'
		// V74.0.67.2.11 BPE end-sentinel return repair.
		//
		// The low-sentinel traversal is an empty-list/end-iterator case, but
		// the caller does not use null as its end value. Runtime evidence
		// shows the caller compares the returned RAX against the same payload
		// pointer stored in this container. Returning zero made the caller
		// execute mov eax,[r14+0x20] with r14=0 and caused AV target 0x20.
		//
		// Return the container's canonical payload/end-sentinel pointer, clear
		// RCX so the guest executes test/jne/ret naturally, and keep the guest
		// in control of the caller's own equality branch.
		WriteCtxU64(ctx, CTX_RAX, payload);
		WriteCtxU64(ctx, CTX_RCX, 0);
		WriteCtxU64(ctx, CTX_RIP, rip + 4);
'@

$count=Count-Ordinal -Text $e -Needle $old
if($count-ne 1){
    throw "[V74.0.67.2.11] BPE return anchor count=$count expected=1"
}
$e=$e.Replace($old,$new)

$oldLog=@'
				$"payload=0x{payload:X16} -> rax=0 rcx=0 next=0x{rip + 4:X16}");
'@
$newLog=@'
				$"payload=0x{payload:X16} -> rax=payload rcx=0 next=0x{rip + 4:X16}");
'@
$countLog=Count-Ordinal -Text $e -Needle $oldLog
if($countLog-ne 1){
    throw "[V74.0.67.2.11] BPE telemetry anchor count=$countLog expected=1"
}
$e=$e.Replace($oldLog,$newLog)

[IO.File]::WriteAllText(
    $exceptionsPath,
    (Restore-Newlines $e),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.11] BPE END-SENTINEL RETURN REPAIR APPLIED.'
