. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach($path in @($bridgePath,$presenterPath,$exceptionsPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing required source: $path"}
}

$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))
$already=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')

$checks=[ordered]@{
    dlss_v2102=$b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')
    provider_init_telemetry_owner_v2102=$b.Contains('[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT]')
    v6729_source_identity=$b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v6728_strict_extension=$b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    v6725_depth=$b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion=$b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    bpe_base_recovery=$e.Contains('V74.0.67.2.4.1 BPE low-sentinel list recovery')
    bpe_v211_payload_return=
        $e.Contains('V74.0.67.2.11 BPE end-sentinel return repair') -and
        $e.Contains('WriteCtxU64(ctx, CTX_RAX, payload);')
    bpe_original_import=$e.Contains('"tcVi5SivF7Q"')
    bpe_helper_signature=
        $e.Contains('0x48, 0x8B, 0x49, 0x08') -and
        $e.Contains('0x48, 0x85, 0xC9') -and
        $e.Contains('0x75, 0xF4')
    bpe_container_shape=
        $e.Contains('head != 1') -and
        $e.Contains('adjacent != 0') -and
        $e.Contains('rdi + 0x10, out ulong payload')
    v73_hotpath=
        $p.Contains('[V74.0.73][SAMPLER_IMAGE_ALIAS]') -or
        ($p.Contains('sampler') -and $p.Contains('alias'))
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.12] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host "[V74.0.67.2.12] already_applied=$($already.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.12] crash_root_cause=second-exact-caller-of-same-bpe-helper'
Write-Host '[V74.0.67.2.12] secondary_import=GuchCTefuZw'
Write-Host '[V74.0.67.2.12] secondary_register_shape=RDI==R13-and-R15==payload'
Write-Host '[V74.0.67.2.12] recovery_result=RAX=payload'
Write-Host '[V74.0.67.2.12] hardcoded_guest_address=false'

if(!$already){
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
    $oldTelemetry=@'
				$"count={recovery} worker='{activeThread.Name}' " +
				$"rip=0x{rip:X16} target=0x9 " +
				$"head=0x{head:X} adjacent=0x{adjacent:X} " +
				$"payload=0x{payload:X16} -> rax=payload rcx=0 next=0x{rip + 4:X16}");
'@

    $a=Count-Ordinal -Text $e -Needle $oldThreadGuard
    $b1=Count-Ordinal -Text $e -Needle $oldRegisters
    $c=Count-Ordinal -Text $e -Needle $oldPayloadEnd
    $d=Count-Ordinal -Text $e -Needle $oldTelemetry

    Write-Host "[V74.0.67.2.12] anchor_thread_guard=$a"
    Write-Host "[V74.0.67.2.12] anchor_register_shape=$b1"
    Write-Host "[V74.0.67.2.12] anchor_payload_boundary=$c"
    Write-Host "[V74.0.67.2.12] anchor_variant_telemetry=$d"

    if($a-ne 1 -or $b1-ne 1 -or $c-ne 1 -or $d-ne 1){$failed=$true}
}

if($failed){throw '[V74.0.67.2.12] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.12] PRECHECK PASSED.'
