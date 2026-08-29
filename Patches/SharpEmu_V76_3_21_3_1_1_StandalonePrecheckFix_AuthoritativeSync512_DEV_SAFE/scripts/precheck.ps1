param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$cli = [IO.File]::ReadAllText($CliPath)
$presenter = [IO.File]::ReadAllText($PresenterPath)
$agc = [IO.File]::ReadAllText($AgcPath)
$backend = [IO.File]::ReadAllText($BackendPath)

# V76.3.21.3.1.1 is intentionally standalone with respect to the failed V21.3
# environment assignment. The source only needs the real weighted-closure
# consumer plus the V21.2 snapshot repair that this branch already carries.
foreach ($m in @(
    'V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS',
    '[V76.3.21.2][GLOBAL_SNAPSHOT_REPAIR]',
    '_producerDependencyClosureSyncScanCapV76383',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN',
    'private static int _producerDependencyClosureSyncRemainingV76383;'
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

$hasV213Marker = $cli.Contains('[V76.3.21.3][GUEST_PROGRESS_RECOVERY]')
$hasLegacySync512 = $cli.Contains('Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN", "512");')
$already = $presenter.Contains('V76.3.21.3.1.1_AUTHORITATIVE_CLOSURE_SYNC_BEGIN')

Write-Host ("[$Tag] PRECHECK PASSED standalone=1 V21.3_marker=$([int]$hasV213Marker) V21.3_env512=$([int]$hasLegacySync512) V21.2_snapshot=1 consumer_binding=1 already_applied=$([int]$already) presenter_sha256=$(Get-HashLower $PresenterPath)")
