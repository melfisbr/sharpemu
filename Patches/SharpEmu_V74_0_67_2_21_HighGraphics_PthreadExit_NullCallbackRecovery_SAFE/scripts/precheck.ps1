. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$kernel=Join-Path $repo 'src\SharpEmu.Libs\Kernel\KernelExports.cs'
$pthread=Join-Path $repo 'src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs'
$memory=Join-Path $repo 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

foreach($path in @($exceptions,$kernel,$pthread,$memory,$bridge,$csproj)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$k=Normalize-Lf ([IO.File]::ReadAllText($kernel))
$p=Normalize-Lf ([IO.File]::ReadAllText($pthread))
$m=Normalize-Lf ([IO.File]::ReadAllText($memory))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$c=Normalize-Lf ([IO.File]::ReadAllText($csproj))

$checks=[ordered]@{
    sce_pthread_exit_nid=$k.Contains('Nid = "3kg7rT0NQIs"')
    sce_pthread_exit_name=$k.Contains('ExportName = "scePthreadExit"')
    pthread_exit_requests_entry_exit=$k.Contains('GuestThreadExecution.RequestCurrentEntryExit("scePthreadExit", value);')
    pthread_tls_cleanup=$k.Contains('KernelPthreadExtendedCompatExports.RunThreadLocalDestructors(ctx);')
    runtime_thread_cleanup=$k.Contains('KernelMemoryCompatExports.RunThreadDtors(ctx);')
    tls_cleanup_guest_callback=$p.Contains('scheduler.TryCallGuestFunction(')
    runtime_cleanup_guest_callback=$m.Contains('GuestThreadExecution.Scheduler?.TryCallGuestFunction(')
    veh_handler=$e.Contains('private unsafe int VectoredHandler(void* exceptionInfo)')
    generic_execute_recovery=$e.Contains('TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip)')
    host_exit=$e.Contains('ActiveEntryReturnSentinelRip')
    active_return_slot=$e.Contains('TryPatchActiveGuestReturnSlot(')
    v211_bpe=$e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')
    v212_bpe=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    v218_bpe=$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')
    v219_quality=$b.Contains('V74.0.67.2.19 strict requested quality profile passthrough')
    v220_deployment=$c.Contains('V74.0.67.2.20 DLSS dual-config runtime deployment')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.21] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$already=$e.Contains('V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery')
Write-Host "[V74.0.67.2.21] recovery_already=$($already.ToString().ToLowerInvariant())"

if(!$already){
    $counterCount=Count-Ordinal -Text $e -Needle '	private static int _auxiliaryThreadExecuteFaultSkips;'
    $callCount=Count-Ordinal -Text $e -Needle @'
			if (TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip))
			{
				return -1;
			}
'@
    $methodCount=Count-Ordinal -Text $e -Needle '	private unsafe bool TryRecoverAuxiliaryThreadExecuteFault('

    Write-Host "[V74.0.67.2.21] counter_anchor_count=$counterCount"
    Write-Host "[V74.0.67.2.21] handler_anchor_count=$callCount"
    Write-Host "[V74.0.67.2.21] method_anchor_count=$methodCount"

    if($counterCount-ne 1 -or $callCount-ne 1 -or $methodCount-ne 1){
        $failed=$true
    }
}

Write-Host '[V74.0.67.2.21] crash_contract=HighGraphics+scePthreadExit-in-progress+execute-null'
Write-Host '[V74.0.67.2.21] cleanup_contract=nested-callback-return-only;pthread-exit-remains-owner'
Write-Host '[V74.0.67.2.21] generic_null_execute_recovery=false'
Write-Host '[V74.0.67.2.21] dlss_change=false'
Write-Host '[V74.0.67.2.21] provider_deployment_change=false'

if($failed){throw '[V74.0.67.2.21] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.21] PRECHECK PASSED.'
