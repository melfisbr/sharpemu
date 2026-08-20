. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$path=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontendPath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

foreach($p in @($path,$bridgePath,$frontendPath)){
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing source: $p"}
}

$a=Normalize-Lf ([IO.File]::ReadAllText($path))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontendPath))

$checks=[ordered]@{
    v215_ttl=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    v213_content_key=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    v74064_store=$a.Contains('private static void StoreLargeArraySnapshotV74064(')
    v74064_evict=$a.Contains('[V74.0.64][ARRAY_CACHE_EVICT]')
    submit_side_effect=$a.Contains('private static void SubmitOrderedGpuSideEffect(')
    packet_position=$a.Contains('var packetPositionWriteV74025 =')
    small_write_ordered_path=$a.Contains('SubmitOrderedGuestActionWithVisibility(')
    slow_wait_trace=$a.Contains('private static void TraceSlowWaitProducerV74027(')
    gate_owner_wait=$a.Contains('[V74.0.72][GATE_OWNER_WAIT_DRAIN]')
    v214_dlss=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    v215_frontend=$f.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.17] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$alreadyCache=$a.Contains('V74.0.67.2.17 size-aware large-array admission')
$alreadyWrite=$a.Contains('V74.0.67.2.17 small WRITE_DATA packet position')
$alreadyLatency=$a.Contains('V74.0.67.2.17 producer completion latency')

Write-Host "[V74.0.67.2.17] cache_already=$($alreadyCache.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.17] small_write_already=$($alreadyWrite.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.17] latency_telemetry_already=$($alreadyLatency.ToString().ToLowerInvariant())"

if(!$alreadyCache){
    $fieldAnchor='    private static int _v74064LargeArraySnapshotEvictionTraceCount;'
    $storeStart='    private static void StoreLargeArraySnapshotV74064('
    $storeEnd='    private static readonly object _softwarePresenterGate = new();'
    $fieldCount=Count-Ordinal -Text $a -Needle $fieldAnchor
    $start=$a.IndexOf($storeStart,[StringComparison]::Ordinal)
    $end=if($start-ge 0){$a.IndexOf($storeEnd,$start,[StringComparison]::Ordinal)}else{-1}
    $storeOk=$start-ge 0 -and $end-gt $start
    Write-Host "[V74.0.67.2.17] cache_field_anchor_count=$fieldCount"
    Write-Host "[V74.0.67.2.17] cache_store_method_isolated=$($storeOk.ToString().ToLowerInvariant())"
    if($fieldCount-ne 1 -or !$storeOk){$failed=$true}
}

if(!$alreadyWrite){
    $packet=@'
        var packetPositionWriteV74025 =
            !requiresGpuBufferReadback &&
            (_writeDataPacketPositionV74025 ||
             watchedWritePacketPositionV7405613);
'@
    $packetCount=Count-Ordinal -Text $a -Needle $packet
    $submitCount=Count-Ordinal -Text $a -Needle '    private static void SubmitOrderedGpuSideEffect('
    Write-Host "[V74.0.67.2.17] small_write_packet_anchor_count=$packetCount"
    Write-Host "[V74.0.67.2.17] small_write_method_anchor_count=$submitCount"
    if($packetCount-ne 1 -or $submitCount-ne 1){$failed=$true}
}

if(!$alreadyLatency){
    $latency=@'
        var waitKind = waiter.RetryDeadlineTicks != 0
            ? "indirect-dims-retry"
            : "wait-reg-mem";
        Console.Error.WriteLine(
'@
    $latencyCount=Count-Ordinal -Text $a -Needle $latency
    Write-Host "[V74.0.67.2.17] latency_anchor_count=$latencyCount"
    if($latencyCount-ne 1){$failed=$true}
}

Write-Host '[V74.0.67.2.17] cache_strategy=bounded-entry-count+protect-larger-snapshots+bypass-smaller'
Write-Host '[V74.0.67.2.17] wait_strategy=small-write-data-only+packet-position+existing-ordered-queue'
Write-Host '[V74.0.67.2.17] submission_hard_cap_change=false'
Write-Host '[V74.0.67.2.17] dlss_source_change=false'
Write-Host '[V74.0.67.2.17] hardcoded_guest_resource_address=false'

if($failed){throw '[V74.0.67.2.17] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.17] PRECHECK PASSED.'
