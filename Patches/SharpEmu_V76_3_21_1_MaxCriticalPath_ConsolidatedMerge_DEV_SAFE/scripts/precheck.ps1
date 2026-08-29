param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$cli = [IO.File]::ReadAllText($CliPath)
foreach ($m in @(
    '[V76.3.21.0][FORWARD_MAX_MERGE]',
    '[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536]',
    '[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH]',
    '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
    '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
    '[V76.3.16.0.1][SIDEBAND_REGRESSION_ROLLBACK]',
    'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS",',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR",',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND",',
    'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH",'
)) {
    if (-not $cli.Contains($m)) {
        Fail "CLI baseline/merge ausente: $m"
    }
}

$agc = [IO.File]::ReadAllText($AgcPath)
foreach ($m in @(
    'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
    'public static bool HasLivePlannedWaitProducerV11714(',
    'public static bool TryGetAgedLivePlannedWaitProducerV76380(',
    'public static long V11714PlannedProducerQueryCount;',
    'GpuWaitRegistry.CountWatchedAddressesInRange('
)) {
    if (-not $agc.Contains($m)) {
        Fail "Agc contract ausente: $m"
    }
}

if (-not $agc.Contains('V76.3.21.1_PLANNED_PRODUCER_QUERY_DEPTH')) {
    foreach ($signature in @(
        'public static bool HasLivePlannedWaitProducerV11714(',
        'public static bool TryGetAgedLivePlannedWaitProducerV76380('
    )) {
        $range = Find-MethodRange $agc $signature $signature
        $segment = $agc.Substring(
            $range.Start,
            $range.End - $range.Start)
        if (-not $segment.Contains(
                'for (var probe = 0; probe < 64; probe++)')) {
            Fail "loop producer-query baseline divergente: $signature"
        }
    }
}

$presenter = [IO.File]::ReadAllText($PresenterPath)
foreach ($m in @(
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN',
    'SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH',
    'SHARPEMU_DRAW_COMMAND_BUFFER_MAX',
    'SHARPEMU_COMPUTE_CHAIN_MAX_V763171',
    'SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX',
    'SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC',
    'ResolveCrossQueueWaitV7615(',
    'CommitCrossQueueAccessV7615('
)) {
    if (-not $presenter.Contains($m)) {
        Fail "Presenter capability ausente: $m"
    }
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) {
    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
}
if (-not $dotnet) {
    Fail 'dotnet nao encontrado no PATH'
}

Write-Host (
    "[$Tag] PRECHECK PASSED " +
    "baseline=V21.0 producer-query=adaptive critical-path=max-safe"
)
