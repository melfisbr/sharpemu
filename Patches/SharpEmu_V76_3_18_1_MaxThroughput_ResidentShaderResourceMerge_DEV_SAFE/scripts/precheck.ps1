param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$presenterHash = Get-HashLower $PresenterPath
if ($presenterHash -ne $ExpectedV18Presenter) {
    Fail (
        "V18 Presenter necessario. " +
        "expected=$ExpectedV18Presenter actual=$presenterHash"
    )
}

$p = [IO.File]::ReadAllText($PresenterPath)
foreach ($m in @(
    'V76.3.18.0_RPCS3_INSPIRED_ASYNC_CB_POOL',
    'MaxRecycledGuestCommandBuffers = 256',
    '[V76.3.18.0][QUEUE_ARCHITECTURE]',
    'SHARPEMU_SHADER_GLOBAL_RESIDENCY',
    'SHARPEMU_DESCRIPTOR_SET_CACHE_V11716',
    'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH',
    'SHARPEMU_VK_DEVICE_LOCAL_GLOBALS',
    'SHARPEMU_REBAR_GLOBAL_DIRECT_V1190',
    'SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633',
    'SHARPEMU_DRAW_COMMAND_BUFFER_MAX',
    'SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE'
)) {
    if (-not $p.Contains($m)) {
        Fail "Presenter feature ausente: $m"
    }
}

$agc = [IO.File]::ReadAllText($AgcPath)
foreach ($m in @(
    'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
    'QueueAsyncAgcSubmissionV763170'
)) {
    if (-not $agc.Contains($m)) {
        Fail "Async AGC ausente: $m"
    }
}

$cli = [IO.File]::ReadAllText($CliPath)
foreach ($m in @(
    '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
    '[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE]',
    '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
    'Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
    'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
    'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");'
)) {
    if (-not $cli.Contains($m)) {
        Fail "V18 merged baseline ausente: $m"
    }
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) {
    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
}
if (-not $dotnet) {
    Fail 'dotnet nao encontrado'
}

Write-Host (
    "[$Tag] PRECHECK PASSED " +
    "base=V18 max_profile=cache+residency+nonblocking+trace-prune"
)
