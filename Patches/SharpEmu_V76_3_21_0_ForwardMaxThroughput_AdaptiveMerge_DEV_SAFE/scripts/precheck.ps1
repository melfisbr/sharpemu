param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$presenterHash = Get-HashLower $PresenterPath
$presenter = [IO.File]::ReadAllText($PresenterPath)

$modernPresenterMarkers = @(
    'MaxRecycledGuestCommandBuffers',
    'MaxRecycledGuestFences',
    'MaxFramesInFlight',
    'SHARPEMU_DUAL_PHYSICAL_QUEUE',
    'SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC',
    '_computeQueueTimelineSemaphoreV1131',
    'ResolveCrossQueueWaitV7615(',
    'SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION',
    'SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE',
    'SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE',
    'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH',
    'SHARPEMU_VK_DEVICE_LOCAL_GLOBALS',
    'SHARPEMU_SHADER_GLOBAL_RESIDENCY',
    'SHARPEMU_DESCRIPTOR_SET_CACHE_V11716',
    'SHARPEMU_GPU_RESIDENT_SHADER_V1180',
    'SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX',
    'SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX'
)

foreach ($m in $modernPresenterMarkers) {
    Require-Marker $presenter $m 'Presenter contract'
}

$agc = [IO.File]::ReadAllText($AgcPath)
foreach ($m in @(
    'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
    'QueueAsyncAgcSubmissionV763170',
    'AsyncCommandProcessorIngressV763170',
    'SnapshotWatchedLabelsInRange(',
    'RecordProducedLabelsInRange('
)) {
    Require-Marker $agc $m 'AGC contract'
}

$cli = [IO.File]::ReadAllText($CliPath)

$hasModernProfile =
    $cli.Contains('[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536]') -or
    $cli.Contains('[V76.3.18.5][ADAPTIVE_FULL_MERGE]') -or
    $cli.Contains('[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH]')

if (-not $hasModernProfile) {
    Fail (
        'CLI nao contem V20.4/V20.5/V18.5. ' +
        'Este pacote e forward-only e nao faz downgrade.'
    )
}

foreach ($m in @(
    'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE"',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR"',
    'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171"',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND"',
    'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH"',
    'Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151"'
)) {
    Require-Marker $cli $m 'CLI contract'
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) {
    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
}
if (-not $dotnet) {
    Fail 'dotnet nao encontrado no PATH'
}

$state = if ($presenterHash -eq $ObservedPresenterHash) {
    'observed-current-25b4794b'
} else {
    'newer-compatible-marker-base'
}

Write-Host "[$Tag] PresenterSHA256=$presenterHash state=$state"
Write-Host (
    "[$Tag] PRECHECK PASSED " +
    "forward_merge=1 async_agc=1 dual_queue=1 " +
    "watched_producer=available residency=available"
)
