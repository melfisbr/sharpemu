param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$presenterHash = Get-HashLower $PresenterPath
$presenter = [IO.File]::ReadAllText($PresenterPath)
$alreadyApplied =
    $presenter.Contains('V76.3.18.5_ADAPTIVE_FULL_PERFORMANCE_MERGE')

if (-not $alreadyApplied -and $presenterHash -ne $RequiredPresenterBaseline) {
    Fail (
        "Presenter baseline divergente. " +
        "expected-current=$RequiredPresenterBaseline actual=$presenterHash"
    )
}

foreach ($m in @(
    'MaxRecycledGuestCommandBuffers',
    'MaxRecycledGuestFences',
    'SHARPEMU_DUAL_PHYSICAL_QUEUE',
    'selectedFamilyQueueCountV1131',
    '_computeQueueTimelineSemaphoreV1131',
    'ResolveCrossQueueWaitV7615(',
    'CommitCrossQueueAccessV7615(',
    'ResolvePhysicalCrossQueueWaitV76383(',
    'ResolvePresentComputeWaitV76383(',
    'RecordComputeBatchDependencyV74099();',
    'SHARPEMU_COMPUTE_CHAIN_MAX_V763171'
)) {
    if (-not $presenter.Contains($m)) {
        Fail "Presenter capability/anchor ausente: $m"
    }
}

$agc = [IO.File]::ReadAllText($AgcPath)
foreach ($m in @(
    'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
    'QueueAsyncAgcSubmissionV763170',
    'AsyncCommandProcessorIngressV763170',
    'RunAsyncAgcCommandProcessorV763170',
    'SHARPEMU_AGC_DEDICATED_FAST_ONLY',
    'SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN'
)) {
    if (-not $agc.Contains($m)) {
        Fail "AGC contract ausente: $m"
    }
}

$cli = [IO.File]::ReadAllText($CliPath)
foreach ($m in @(
    'internal static void Apply()',
    'private static bool IsDemonsSoulsLaunch()',
    'private static void Set(',
    'private static void SetDefault(',
    'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS"',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND"',
    'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH"'
)) {
    if (-not $cli.Contains($m)) {
        Fail "CLI contract/anchor ausente: $m"
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
    "presenter_sha=$presenterHash async_agc=1 chain4=1 dual_capability=1"
)
