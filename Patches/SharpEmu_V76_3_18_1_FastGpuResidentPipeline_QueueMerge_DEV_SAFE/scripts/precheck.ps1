param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$cli=[IO.File]::ReadAllText($CliPath)
$presenter=[IO.File]::ReadAllText($PresenterPath)
$agc=[IO.File]::ReadAllText($AgcPath)

foreach($m in @(
 '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
 '[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE]',
 '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
 '[V76.3.16.1.1][DEPENDENCY_SLICED_PRODUCER]',
 'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
 'Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
 'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");'
)){
 if(-not$cli.Contains($m)){Fail "CLI V18 baseline ausente: $m"}
}

foreach($m in @(
 '[V76.3.18.0][QUEUE_ARCHITECTURE]',
 'MaxRecycledGuestCommandBuffers = 256',
 'ResolveCrossQueueWaitV7615(',
 '_computeQueueTimelineSemaphoreV1131',
 'SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX',
 'SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX',
 'SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716',
 'SHARPEMU_VK_DEVICE_LOCAL_GLOBALS',
 'SHARPEMU_REBAR_GLOBAL_DIRECT_V1190',
 'SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633'
)){
 if(-not$presenter.Contains($m)){Fail "Presenter capability ausente: $m"}
}

foreach($m in @(
 'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
 'QueueAsyncAgcSubmissionV763170',
 'AsyncCommandProcessorIngressV763170'
)){
 if(-not$agc.Contains($m)){Fail "Async AGC ausente: $m"}
}

$dotnet=(Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if(-not$dotnet){$dotnet=(Get-Command dotnet -ErrorAction SilentlyContinue).Source}
if(-not$dotnet){Fail 'dotnet nao encontrado'}

Write-Host "[$Tag] PRECHECK PASSED base=V18.0 asyncAGC=1 dualQueue=capability chain4=1"
