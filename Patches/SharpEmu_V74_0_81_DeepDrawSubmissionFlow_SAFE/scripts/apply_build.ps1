param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$p=Assert-StructuralContracts
$nl=if($p.Contains("`r`n")){"`r`n"}else{"`n"}
$changed=$false

# Overall marker, intentionally placed beside queue accounting fields.
if(-not $p.Contains('SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW')){
    $anchor='    private static ulong _pendingGuestWorkBytes;'
    $pos=$p.IndexOf($anchor,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag pending-byte field anchor missing."}
    $mark="    // SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW"+$nl
    $p=$p.Insert($pos,$mark);$changed=$true
}

# 1) Bounded same-guest-submission burst. Existing producer/control-lane priority
# runs before the ordinary RR scheduler, so this does not bypass live WAIT producers.
if(-not $p.Contains('SHARPEMU_V74_0_81_BOUNDED_QUEUE_BURST')){
    $start=$p.IndexOf('    private static readonly int _queueSubmissionBurstV74043 =',[System.StringComparison]::Ordinal)
    if($start -lt 0){throw "$script:Tag queue burst declaration missing."}
    $semi=$p.IndexOf(';',$start,[System.StringComparison]::Ordinal)
    if($semi -lt 0){throw "$script:Tag queue burst declaration terminator missing."}
    $seg=$p.Substring($start,$semi-$start+1)
    # Accept explicit env=1 as rollback/A-B. Default becomes 8, matching the proven batch ceiling.
    $seg2=[regex]::Replace($seg,'out\s+var\s+queueSubmissionBurstV74043\)\s*&&\s*queueSubmissionBurstV74043\s*>\s*1','out var queueSubmissionBurstV74043) && queueSubmissionBurstV74043 >= 1')
    $seg2=[regex]::Replace($seg2,'Math\.Clamp\(queueSubmissionBurstV74043,\s*2,\s*64\)','Math.Clamp(queueSubmissionBurstV74043, 1, 64)')
    $seg2=[regex]::Replace($seg2,':\s*1\s*;',': 8;')
    if($seg2 -eq $seg){
        if(-not($seg -match ':\s*8\s*;')){throw "$script:Tag queue burst declaration shape changed; refusing unsafe rewrite."}
    }else{
        $p=$p.Remove($start,$seg.Length).Insert($start,$seg2);$changed=$true
    }
    $p=$p.Insert($start,"    // SHARPEMU_V74_0_81_BOUNDED_QUEUE_BURST default=8 env_1_restores_legacy"+$nl);$changed=$true
}

# 2) Split bytes that are actually waiting in the software queue from the one
# item currently executing on the renderer. Blocking the parser on an already-
# dequeued 129-342 MiB payload cannot release that memory and delays WRITE_DATA.
if(-not $p.Contains('SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')){
    $field='    private static ulong _pendingGuestWorkBytes;'
    $pos=$p.IndexOf($field,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag pending byte field missing for split."}
    $after=$pos+$field.Length
    $block=$nl+
'    // SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT'+$nl+
'    private static ulong _inFlightGuestWorkBytesV74081;'+$nl+
'    private static long _v74081QueueToInFlightTraceCount;'+$nl+
'    private static readonly bool _separateInFlightGuestWorkBytesV74081 ='+$nl+
'        !string.Equals('+$nl+
'            Environment.GetEnvironmentVariable("SHARPEMU_QUEUE_SEPARATE_INFLIGHT_BYTES"),'+$nl+
'            "0",'+$nl+
'            StringComparison.Ordinal);'
    $p=$p.Insert($after,$block);$changed=$true

    # Reset lifecycle.
    $reset='_pendingGuestWorkBytes = 0;'
    $rpos=$p.IndexOf($reset,[System.StringComparison]::Ordinal)
    if($rpos -lt 0){throw "$script:Tag pending byte reset anchor missing."}
    $p=$p.Insert($rpos+$reset.Length,$nl+'        _inFlightGuestWorkBytesV74081 = 0;');$changed=$true

    # Take: queue -> in-flight accounting.
    $takeStart=$p.IndexOf('    private static void RemoveTakenGuestWorkLocked(',[System.StringComparison]::Ordinal)
    $takeEnd=$p.IndexOf('    private static bool RequeueGuestWorkFront(', $takeStart,[System.StringComparison]::Ordinal)
    if($takeStart -lt 0 -or $takeEnd -lt 0){throw "$script:Tag RemoveTakenGuestWorkLocked bounds missing."}
    $schedule=$p.IndexOf('        var scheduleIndex =', $takeStart,[System.StringComparison]::Ordinal)
    if($schedule -lt 0 -or $schedule -ge $takeEnd){throw "$script:Tag take-work schedule anchor missing."}
    $takeBlock=@'
        // SHARPEMU_V74_0_81_QUEUE_TO_INFLIGHT
        if (_separateInFlightGuestWorkBytesV74081 && work.PayloadBytes != 0)
        {
            _pendingGuestWorkBytes = work.PayloadBytes >= _pendingGuestWorkBytes
                ? 0
                : _pendingGuestWorkBytes - work.PayloadBytes;
            _inFlightGuestWorkBytesV74081 =
                SaturatingAdd(_inFlightGuestWorkBytesV74081, work.PayloadBytes);

            if (work.PayloadBytes >= 32UL * 1024UL * 1024UL)
            {
                var traceV74081 = Interlocked.Increment(
                    ref _v74081QueueToInFlightTraceCount);
                if (traceV74081 <= 64 || (traceV74081 & (traceV74081 - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.81][QUEUE_TO_INFLIGHT] count={traceV74081} " +
                        $"payload_mb={work.PayloadBytes / (1024 * 1024)} " +
                        $"queued_mb={_pendingGuestWorkBytes / (1024 * 1024)} " +
                        $"inflight_mb={_inFlightGuestWorkBytesV74081 / (1024 * 1024)} " +
                        $"work={work.Work.GetType().Name} queue={work.Queue.Name} " +
                        $"submission={work.Queue.SubmissionId}");
                }
            }
        }

'@
    $takeBlock=$takeBlock.Replace("`n",$nl)
    $p=$p.Insert($schedule,$takeBlock);$changed=$true

    # Requeue: move the accounting back to queued bytes exactly once.
    $rqStart=$p.IndexOf('    private static bool RequeueGuestWorkFront(',[System.StringComparison]::Ordinal)
    $rqEnd=$p.IndexOf('    private static bool WaitForFollowupGuestWork(', $rqStart,[System.StringComparison]::Ordinal)
    if($rqStart -lt 0 -or $rqEnd -lt 0){throw "$script:Tag RequeueGuestWorkFront bounds missing."}
    $pulse=$p.IndexOf('            System.Threading.Monitor.PulseAll(_gate);',$rqStart,[System.StringComparison]::Ordinal)
    if($pulse -lt 0 -or $pulse -ge $rqEnd){throw "$script:Tag requeue pulse anchor missing."}
    $rqBlock=@'
            // SHARPEMU_V74_0_81_INFLIGHT_TO_QUEUE_ON_REQUEUE
            if (_separateInFlightGuestWorkBytesV74081 && work.PayloadBytes != 0)
            {
                _inFlightGuestWorkBytesV74081 =
                    work.PayloadBytes >= _inFlightGuestWorkBytesV74081
                        ? 0
                        : _inFlightGuestWorkBytesV74081 - work.PayloadBytes;
                _pendingGuestWorkBytes =
                    SaturatingAdd(_pendingGuestWorkBytes, work.PayloadBytes);
            }

'@
    $rqBlock=$rqBlock.Replace("`n",$nl)
    $p=$p.Insert($pulse,$rqBlock);$changed=$true

    # Completion: in split mode the payload left queued accounting at dequeue.
    $cStart=$p.IndexOf('    private static void CompleteGuestWork(',[System.StringComparison]::Ordinal)
    if($cStart -lt 0){throw "$script:Tag CompleteGuestWork missing."}
    $cEnd=$p.IndexOf("`n    private static ",$cStart+8,[System.StringComparison]::Ordinal)
    if($cEnd -lt 0){$cEnd=$p.Length}
    $old='_pendingGuestWorkBytes = pending.PayloadBytes >= _pendingGuestWorkBytes'+$nl+'                ? 0'+$nl+'                : _pendingGuestWorkBytes - pending.PayloadBytes;'
    $oldPos=$p.IndexOf($old,$cStart,[System.StringComparison]::Ordinal)
    if($oldPos -lt 0 -or $oldPos -ge $cEnd){throw "$script:Tag CompleteGuestWork pending-byte subtraction anchor missing."}
    $new=@'
if (_separateInFlightGuestWorkBytesV74081)
            {
                _inFlightGuestWorkBytesV74081 =
                    pending.PayloadBytes >= _inFlightGuestWorkBytesV74081
                        ? 0
                        : _inFlightGuestWorkBytesV74081 - pending.PayloadBytes;
            }
            else
            {
                _pendingGuestWorkBytes = pending.PayloadBytes >= _pendingGuestWorkBytes
                    ? 0
                    : _pendingGuestWorkBytes - pending.PayloadBytes;
            }
'@
    $new=$new.Replace("`n",$nl)
    $p=$p.Remove($oldPos,$old.Length).Insert($oldPos,$new);$changed=$true
}

# 3) Compute shared-batch repair. V56.20 removed RenderCore's per-payload flush,
# but ExecuteComputeDispatchCore still had two unconditional flushes. The first
# compute in every run therefore submitted the previous draw/compute batch and
# the next compute immediately submitted that one: measured avg=1.05 work/submit.
if(-not $p.Contains('SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR')){
    $mStart=$p.IndexOf('        private void ExecuteComputeDispatchCore(VulkanComputeGuestDispatch work)',[System.StringComparison]::Ordinal)
    $mEnd=$p.IndexOf('        private void TraceDeviceLostCandidateV74056(', $mStart,[System.StringComparison]::Ordinal)
    if($mStart -lt 0 -or $mEnd -lt 0){throw "$script:Tag ExecuteComputeDispatchCore bounds missing."}
    $seg=$p.Substring($mStart,$mEnd-$mStart)
    $first='        private void ExecuteComputeDispatchCore(VulkanComputeGuestDispatch work)'+$nl+'        {'+$nl+'            FlushBatchedGuestCommands();'
    if(-not $seg.Contains($first)){throw "$script:Tag first unconditional compute flush anchor missing."}
    $firstNew='        private void ExecuteComputeDispatchCore(VulkanComputeGuestDispatch work)'+$nl+'        {'+$nl+'            // SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR'+$nl+'            if (!_preservePayloadBatchV7405620)'+$nl+'            {'+$nl+'                FlushBatchedGuestCommands();'+$nl+'            }'
    $seg=$seg.Replace($first,$firstNew)

    $second='                resources = CreateComputeDispatchResources(work);'+$nl+$nl+'                FlushBatchedGuestCommands();'+$nl+$nl+'                var adaptiveUnifiedV7405616 ='
    if(-not $seg.Contains($second)){throw "$script:Tag second unconditional compute flush anchor missing."}
    $secondNew='                resources = CreateComputeDispatchResources(work);'+$nl+$nl+'                // V74.0.81: keep an already-open payload batch alive while'+$nl+'                // this dispatch is eligible for the shared command buffer.'+$nl+'                var adaptiveUnifiedV7405616 ='
    $seg=$seg.Replace($second,$secondNew)

    $ifShared='                if (useSharedComputeBatchV7405617)'
    $ifPos=$seg.IndexOf($ifShared,[System.StringComparison]::Ordinal)
    if($ifPos -lt 0){throw "$script:Tag shared-compute branch anchor missing."}
    $guard=@'
                // Standalone/indirect/multi-submit compute still requires a real
                // submit boundary. Only the proven shared path crosses payloads.
                if (!useSharedComputeBatchV7405617)
                {
                    FlushBatchedGuestCommands();
                }

'@
    $guard=$guard.Replace("`n",$nl)
    $seg=$seg.Insert($ifPos,$guard)
    $p=$p.Remove($mStart,$mEnd-$mStart).Insert($mStart,$seg);$changed=$true
}

if(-not $changed){Write-Host "$script:Tag State=AlreadyApplied"}
else{
    $backup=New-Backup
    try{
        Write-Utf8NoBom $script:PresenterPath $p
        $p2=Read-Utf8 $script:PresenterPath
        foreach($marker in @('SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW','SHARPEMU_V74_0_81_BOUNDED_QUEUE_BURST','SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT','SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR')){
            if(-not $p2.Contains($marker)){throw "$script:Tag marker missing after apply: $marker"}
        }
        if(-not $p2.Contains('SHARPEMU_V74_0_78_3_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER')){Write-Host "$script:Tag note=v74078_marker_not_present_in_this_checkout" -ForegroundColor Yellow}
        if($p.Contains('DCC_PROVENANCE_RECOVERY') -and -not $p2.Contains('DCC_PROVENANCE_RECOVERY')){throw "$script:Tag V74.0.80 DCC provenance marker was lost."}
        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY."
        Write-Host "$script:Tag queue_burst_default=8 legacy_env_override=1"
        Write-Host "$script:Tag queue_bytes=queued_only plus bounded_inflight"
        Write-Host "$script:Tag compute_batch_unconditional_flushes=repaired"
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
    }catch{Restore-Backup $backup;throw}
}
$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_81_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){
 if(Test-Path -LiteralPath $script:StateFile){$b=(Read-Utf8 $script:StateFile).Trim();if($b -and(Test-Path -LiteralPath $b)){Restore-Backup $b;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $b" -ForegroundColor Yellow}}
 throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
