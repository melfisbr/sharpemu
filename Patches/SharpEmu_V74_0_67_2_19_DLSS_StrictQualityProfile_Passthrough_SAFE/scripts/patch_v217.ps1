. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$path=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$a=Normalize-Lf ([IO.File]::ReadAllText($path))

$marker='V74.0.67.2.17 size-aware large-array admission'
$waitMarker='V74.0.67.2.17 small WRITE_DATA packet position'
$latencyMarker='V74.0.67.2.17 producer completion latency'

if($a.Contains($marker) -and $a.Contains($waitMarker) -and $a.Contains($latencyMarker)){
    Write-Host '[V74.0.67.2.17] Source already fully patched.'
    return
}

foreach($required in @(
    'V74.0.67.2.15 effective large-array TTL',
    'V74.0.67.2.13 large-array sparse-content reuse key',
    'private static void StoreLargeArraySnapshotV74064(',
    'private static void SubmitOrderedGpuSideEffect(',
    'private static void TraceSlowWaitProducerV74027(',
    'var packetPositionWriteV74025 =',
    'SubmitOrderedGuestActionWithVisibility(',
    '[V74.0.72][GATE_OWNER_WAIT_DRAIN]'))
{
    if(!$a.Contains($required)){
        throw "[V74.0.67.2.17] Required accumulated source marker missing: $required"
    }
}

# ----------------------------------------------------------------
# 1) Size-aware bounded admission for the existing 2-entry array cache.
# ----------------------------------------------------------------
if(!$a.Contains($marker)){
    $fieldAnchor='    private static int _v74064LargeArraySnapshotEvictionTraceCount;'
    $fieldCount=Count-Ordinal -Text $a -Needle $fieldAnchor
    if($fieldCount-ne 1){
        throw "[V74.0.67.2.17] Array cache field anchor count=$fieldCount expected=1"
    }

    $fields=@'

    // V74.0.67.2.17 size-aware large-array admission.
    // Keep the V74.0.64 entry-count bound, but stop 64/128 MiB bridge snapshots
    // from evicting hotter 256/320 MiB snapshots. Cache admission changes only
    // future reuse; the current upload still owns and consumes its byte[].
    private static readonly bool _v74067217SizeAwareLargeArrayAdmission =
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_LARGE_ARRAY_SIZE_AWARE_ADMISSION"),
            "0",
            StringComparison.Ordinal);
    private static long _v74067217ArrayAdmissionBypassCount;
    private static long _v74067217ArrayAdmissionBypassBytes;
    private static long _v74067217ArrayAdmissionReplaceCount;
'@
    $a=$a.Replace($fieldAnchor,$fieldAnchor+$fields)

    $methodStartToken='    private static void StoreLargeArraySnapshotV74064('
    $nextToken='    private static readonly object _softwarePresenterGate = new();'
    $start=$a.IndexOf($methodStartToken,[StringComparison]::Ordinal)
    $end=if($start-ge 0){$a.IndexOf($nextToken,$start,[StringComparison]::Ordinal)}else{-1}
    if($start-lt 0 -or $end-le $start){
        throw '[V74.0.67.2.17] Unable to isolate StoreLargeArraySnapshotV74064.'
    }

    $oldMethod=$a.Substring($start,$end-$start)
    foreach($requiredMethodToken in @(
        '_v74064LargeArraySnapshotCache.ContainsKey(key)',
        '_v74064LargeArraySnapshotCacheEntries',
        '[V74.0.64][ARRAY_CACHE_EVICT]',
        '_v74064LargeArraySnapshotCache[key] = (data, now);'))
    {
        if(!$oldMethod.Contains($requiredMethodToken)){
            throw "[V74.0.67.2.17] Store method shape mismatch: missing $requiredMethodToken"
        }
    }

    $newMethod=@'
    private static bool SameLargeArrayResourceIgnoringContentV74067217(
        V74015LargeArraySnapshotKey left,
        V74015LargeArraySnapshotKey right) =>
        left.Address == right.Address &&
        left.Width == right.Width &&
        left.Height == right.Height &&
        left.Format == right.Format &&
        left.NumberType == right.NumberType &&
        left.TileMode == right.TileMode &&
        left.Pitch == right.Pitch &&
        left.SliceBytes == right.SliceBytes &&
        left.ArrayLayers == right.ArrayLayers &&
        left.Tiled == right.Tiled;

    // Caller holds _v74015LargeArraySnapshotGate.
    private static void StoreLargeArraySnapshotV74064(
        V74015LargeArraySnapshotKey key,
        byte[] data,
        long now)
    {
        if (_v74067217SizeAwareLargeArrayAdmission)
        {
            // A content-generation change for the same resource makes the older
            // bridge snapshot useless. Remove that exact resource identity before
            // capacity admission so stale generations cannot pin a large slot.
            if (!_v74064LargeArraySnapshotCache.ContainsKey(key) &&
                _v74064LargeArraySnapshotCache.Count != 0)
            {
                var foundStale = false;
                var staleKey = default(V74015LargeArraySnapshotKey);
                foreach (var entry in _v74064LargeArraySnapshotCache)
                {
                    if (!entry.Key.Equals(key) &&
                        SameLargeArrayResourceIgnoringContentV74067217(
                            entry.Key,
                            key))
                    {
                        staleKey = entry.Key;
                        foundStale = true;
                        break;
                    }
                }

                if (foundStale)
                {
                    _v74064LargeArraySnapshotCache.Remove(staleKey);
                }
            }

            if (!_v74064LargeArraySnapshotCache.ContainsKey(key) &&
                _v74064LargeArraySnapshotCache.Count >=
                    _v74064LargeArraySnapshotCacheEntries)
            {
                var foundSmallest = false;
                var smallestKey = default(V74015LargeArraySnapshotKey);
                var smallestBytes = long.MaxValue;
                var smallestTick = long.MaxValue;

                foreach (var entry in _v74064LargeArraySnapshotCache)
                {
                    var candidateBytes = entry.Value.Data.LongLength;
                    if (!foundSmallest ||
                        candidateBytes < smallestBytes ||
                        (candidateBytes == smallestBytes &&
                         entry.Value.Tick < smallestTick))
                    {
                        foundSmallest = true;
                        smallestKey = entry.Key;
                        smallestBytes = candidateBytes;
                        smallestTick = entry.Value.Tick;
                    }
                }

                // Do not let a smaller/equal one-shot upload evict a larger
                // snapshot that saves more LOH traffic on a later reuse.
                if (foundSmallest && data.LongLength <= smallestBytes)
                {
                    var bypassCount = Interlocked.Increment(
                        ref _v74067217ArrayAdmissionBypassCount);
                    var bypassBytes = Interlocked.Add(
                        ref _v74067217ArrayAdmissionBypassBytes,
                        data.LongLength);
                    if (bypassCount <= 64 ||
                        (bypassCount & (bypassCount - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.2.17][ARRAY_CACHE_ADMISSION] " +
                            $"action=bypass-smaller count={bypassCount} " +
                            $"incoming_mb={data.LongLength / (1024 * 1024)} " +
                            $"protected_mb={smallestBytes / (1024 * 1024)} " +
                            $"bypassed_total_mb={bypassBytes / (1024 * 1024)} " +
                            $"cache={_v74064LargeArraySnapshotCache.Count}/" +
                            $"{_v74064LargeArraySnapshotCacheEntries}");
                    }

                    return;
                }

                if (foundSmallest &&
                    _v74064LargeArraySnapshotCache.Remove(smallestKey))
                {
                    var replaceCount = Interlocked.Increment(
                        ref _v74067217ArrayAdmissionReplaceCount);
                    if (replaceCount <= 64 ||
                        (replaceCount & (replaceCount - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.2.17][ARRAY_CACHE_ADMISSION] " +
                            $"action=replace-smaller count={replaceCount} " +
                            $"evicted_mb={smallestBytes / (1024 * 1024)} " +
                            $"incoming_mb={data.LongLength / (1024 * 1024)} " +
                            $"cache={_v74064LargeArraySnapshotCache.Count}/" +
                            $"{_v74064LargeArraySnapshotCacheEntries}");
                    }
                }
            }

            _v74064LargeArraySnapshotCache[key] = (data, now);
            return;
        }

        // Original V74.0.64 behavior for A/B rollback.
        if (!_v74064LargeArraySnapshotCache.ContainsKey(key) &&
            _v74064LargeArraySnapshotCache.Count >=
                _v74064LargeArraySnapshotCacheEntries)
        {
            var foundOldest = false;
            var oldestKey = default(V74015LargeArraySnapshotKey);
            var oldestTick = long.MaxValue;

            foreach (var entry in _v74064LargeArraySnapshotCache)
            {
                if (!foundOldest || entry.Value.Tick < oldestTick)
                {
                    foundOldest = true;
                    oldestKey = entry.Key;
                    oldestTick = entry.Value.Tick;
                }
            }

            if (foundOldest &&
                _v74064LargeArraySnapshotCache.Remove(oldestKey))
            {
                var evictCount = Interlocked.Increment(
                    ref _v74064LargeArraySnapshotEvictionTraceCount);
                if (evictCount <= 32 ||
                    (evictCount & (evictCount - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.64][ARRAY_CACHE_EVICT] count={evictCount} " +
                        $"addr=0x{oldestKey.Address:X16} " +
                        $"entries={_v74064LargeArraySnapshotCache.Count}/" +
                        $"{_v74064LargeArraySnapshotCacheEntries}");
                }
            }
        }

        _v74064LargeArraySnapshotCache[key] = (data, now);
    }

'@
    $a=$a.Substring(0,$start)+$newMethod+$a.Substring($end)
}

# ----------------------------------------------------------------
# 2) Small WRITE_DATA sync labels run at PM4 packet position.
# ----------------------------------------------------------------
if(!$a.Contains($waitMarker)){
    $methodAnchor='    private static void SubmitOrderedGpuSideEffect('
    $count=Count-Ordinal -Text $a -Needle $methodAnchor
    if($count-ne 1){
        throw "[V74.0.67.2.17] SubmitOrderedGpuSideEffect anchor count=$count expected=1"
    }

    $waitFields=@'
    // V74.0.67.2.17 small WRITE_DATA packet position.
    // WRITE_DATA is a command-processor memory packet. Restrict the normal
    // packet-position path to tiny non-readback/non-deferred writes that match
    // synchronization-label traffic; RELEASE_MEM/EOP remains unchanged.
    private static readonly bool _v74067217SmallWritePacketPosition =
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_SMALL_WRITE_DATA_PACKET_POSITION"),
            "0",
            StringComparison.Ordinal);
    private static long _v74067217SmallWritePacketPositionCount;

'@
    $a=$a.Replace($methodAnchor,$waitFields+$methodAnchor)

    $oldPacket=@'
        var packetPositionWriteV74025 =
            !requiresGpuBufferReadback &&
            (_writeDataPacketPositionV74025 ||
             watchedWritePacketPositionV7405613);
'@
    $packetCount=Count-Ordinal -Text $a -Needle $oldPacket
    if($packetCount-ne 1){
        throw "[V74.0.67.2.17] packetPositionWrite anchor count=$packetCount expected=1"
    }

    $newPacket=@'
        var smallWritePacketPositionV74067217 =
            _v74067217SmallWritePacketPosition &&
            !requiresGpuBufferReadback &&
            !deferLabelCompletion &&
            producerAddress != 0 &&
            producerLength > 0 &&
            producerLength <= 16 &&
            debugName.StartsWith("write_data ", StringComparison.Ordinal);

        var packetPositionWriteV74025 =
            !requiresGpuBufferReadback &&
            (_writeDataPacketPositionV74025 ||
             watchedWritePacketPositionV7405613 ||
             smallWritePacketPositionV74067217);

        if (smallWritePacketPositionV74067217)
        {
            var smallWriteCount = Interlocked.Increment(
                ref _v74067217SmallWritePacketPositionCount);
            if (smallWriteCount <= 128 ||
                (smallWriteCount & (smallWriteCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.17][SMALL_WRITE_PACKET_POSITION] " +
                    $"count={smallWriteCount} queue={state.QueueName} " +
                    $"submission={state.ActiveSubmissionId} " +
                    $"addr=0x{producerAddress:X16} bytes={producerLength} " +
                    $"watched_now={(watchedWritePacketPositionV7405613 ? 1 : 0)} " +
                    $"name='{debugName}'");
            }
        }
'@
    $a=$a.Replace($oldPacket,$newPacket)
}

# ----------------------------------------------------------------
# 3) Split slow-wait time into registration->producer-complete and
#    producer-complete->trace so the next run proves where latency remains.
# ----------------------------------------------------------------
if(!$a.Contains($latencyMarker)){
    $latencyAnchor=@'
        var waitKind = waiter.RetryDeadlineTicks != 0
            ? "indirect-dims-retry"
            : "wait-reg-mem";
        Console.Error.WriteLine(
'@
    $latencyCount=Count-Ordinal -Text $a -Needle $latencyAnchor
    if($latencyCount-ne 1){
        throw "[V74.0.67.2.17] slow-wait latency anchor count=$latencyCount expected=1"
    }

    $latencyInsert=@'
        var waitKind = waiter.RetryDeadlineTicks != 0
            ? "indirect-dims-retry"
            : "wait-reg-mem";

        // V74.0.67.2.17 producer completion latency.
        var nowTicksV74067217 =
            System.Diagnostics.Stopwatch.GetTimestamp();
        var producerCompleteAfterRegistrationMsV74067217 =
            producerCompletedTicks == 0 || waiter.RegisteredTicks == 0
                ? -1.0
                : (producerCompletedTicks - waiter.RegisteredTicks) *
                  1000.0 /
                  System.Diagnostics.Stopwatch.Frequency;
        var postProducerCompleteWaitMsV74067217 =
            producerCompletedTicks == 0
                ? -1.0
                : (nowTicksV74067217 - producerCompletedTicks) *
                  1000.0 /
                  System.Diagnostics.Stopwatch.Frequency;
        Console.Error.WriteLine(
'@
    $a=$a.Replace($latencyAnchor,$latencyInsert)

    $oldTail=@'
            $"producer_completed_after_wait={(producerCompletedTicks == 0 || waiter.RegisteredTicks == 0 ? -1 : producerCompletedTicks >= waiter.RegisteredTicks ? 1 : 0)} " +
            $"renderer_work_sequence={GuestGpu.Current.CurrentGuestWorkSequenceForDiagnostics} " +
'@
    $tailCount=Count-Ordinal -Text $a -Needle $oldTail
    if($tailCount-ne 1){
        throw "[V74.0.67.2.17] slow-wait telemetry tail count=$tailCount expected=1"
    }
    $newTail=@'
            $"producer_completed_after_wait={(producerCompletedTicks == 0 || waiter.RegisteredTicks == 0 ? -1 : producerCompletedTicks >= waiter.RegisteredTicks ? 1 : 0)} " +
            $"producer_complete_ms={producerCompleteAfterRegistrationMsV74067217:F3} " +
            $"post_complete_wait_ms={postProducerCompleteWaitMsV74067217:F3} " +
            $"renderer_work_sequence={GuestGpu.Current.CurrentGuestWorkSequenceForDiagnostics} " +
'@
    $a=$a.Replace($oldTail,$newTail)
}

# Final in-memory structural proof before writing.
foreach($proof in @(
    'V74.0.67.2.17 size-aware large-array admission',
    'SameLargeArrayResourceIgnoringContentV74067217',
    '[V74.0.67.2.17][ARRAY_CACHE_ADMISSION]',
    'V74.0.67.2.17 small WRITE_DATA packet position',
    '[V74.0.67.2.17][SMALL_WRITE_PACKET_POSITION]',
    'producer_complete_ms=',
    'post_complete_wait_ms=',
    'V74.0.67.2.15 effective large-array TTL',
    '[V74.0.72][GATE_OWNER_WAIT_DRAIN]'))
{
    if(!$a.Contains($proof)){
        throw "[V74.0.67.2.17] Post-transform proof missing: $proof"
    }
}

[IO.File]::WriteAllText(
    $path,
    (Restore-Newlines $a),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.17] AGC size-aware cache + small WRITE_DATA packet-position patch applied.'
