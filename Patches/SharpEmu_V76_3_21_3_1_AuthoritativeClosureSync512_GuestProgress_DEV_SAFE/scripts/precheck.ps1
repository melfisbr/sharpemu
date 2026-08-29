param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$cli = [IO.File]::ReadAllText($CliPath)
$presenter = [IO.File]::ReadAllText($PresenterPath)
$agc = [IO.File]::ReadAllText($AgcPath)
$backend = [IO.File]::ReadAllText($BackendPath)

foreach ($m in @(
    '[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]',
    '[V76.3.21.3][GUEST_PROGRESS_RECOVERY]',
    'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN", "512");',
    'Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");'
)) {
    if (-not $cli.Contains($m)) { Fail "V21.3 corrigido precisa estar aplicado antes desta revisao: $m" }
}

foreach ($m in @(
    'V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS',
    '[V76.3.21.2][GLOBAL_SNAPSHOT_REPAIR]',
    '_producerDependencyClosureSyncScanCapV76383',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN'
)) {
    if (-not $presenter.Contains($m)) { Fail "Presenter baseline/consumer ausente: $m" }
}

foreach ($m in @(
    'SHARPEMU_TRACE_SCENE_PIPELINE_GAPS',
    'SHARPEMU_TRACE_GEOMETRY_DRAWS',
    'sceAgcCreatePrimState'
)) {
    if (-not $agc.Contains($m)) { Fail "AGC probe contract ausente: $m" }
}

foreach ($m in @(
    'StartReadyThreadDispatcher()',
    'HasNativeGuestExecutionProgress(out string detail)',
    'SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS'
)) {
    if (-not $backend.Contains($m)) { Fail "guest progress diagnostic contract ausente: $m" }
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source }
if (-not $dotnet) { Fail 'dotnet nao encontrado' }

$already = $presenter.Contains('V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_BEGIN')
Write-Host ("[$Tag] PRECHECK PASSED V21.3=1 V21.2_snapshot=1 consumer_binding=1 already_applied=$([int]$already) presenter_sha256=$(Get-HashLower $PresenterPath)")
