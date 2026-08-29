param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$presenterHash = Get-HashLower $PresenterPath
if ($presenterHash -eq $ExpectedPresenterResult) {
    Write-Host "[$Tag] Presenter state=already-applied hash=$presenterHash"
}
elseif ($presenterHash -eq $ExpectedPresenterBaseline) {
    Write-Host "[$Tag] Presenter state=V17.1-baseline hash=$presenterHash"
}
else {
    Fail (
        "Presenter baseline divergente " +
        "expected=$ExpectedPresenterBaseline actual=$presenterHash"
    )
}

$agc = [IO.File]::ReadAllText($AgcPath)
foreach ($m in @(
    'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
    'QueueAsyncAgcSubmissionV763170',
    'AsyncCommandProcessorIngressV763170',
    'RunAsyncAgcCommandProcessorV763170'
)) {
    if (-not $agc.Contains($m)) {
        Fail "Async AGC V17.0.1 nao encontrado: $m"
    }
}

$cli = [IO.File]::ReadAllText($CliPath)
foreach ($m in @(
    '[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE]',
    '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
    '[V76.3.16.1.1][DEPENDENCY_SLICED_PRODUCER]',
    '[V76.3.16.0.1][SIDEBAND_REGRESSION_ROLLBACK]',
    '[V76.3.15.1][BOOT_LANE6_SAFE_MEMCPY]',
    'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
    'Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
    'Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
    'Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
    'Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
    'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
    'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
    'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");'
)) {
    if (-not $cli.Contains($m)) {
        Fail "baseline merged contract ausente: $m"
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
    "base=V17.1+V17.0.1 merge=dual-physical-resource-safe"
)
