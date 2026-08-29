param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$p = [IO.File]::ReadAllText($PresenterPath)
$already =
    $p.Contains('V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS') -and
    $p.Contains('_v763212PartialGlobalSnapshotCount')

if ($already) {
    Write-Host "[$Tag] Presenter state=already-applied sha256=$(Get-HashLower $PresenterPath)"
}
else {
    foreach ($m in @(
        'private static long _v74051GlobalRefreshDeferTraceCount;',
        'private bool TryPrepareWritableGlobalRefreshV74051(',
        'var sourceV74051 =',
        'guestBuffer.Data.AsSpan(',
        'var deferredLiveReadV11712 =',
        'guestBuffer.Data.Length == 0 &&',
        'CreateVersionedReadOnlyGlobalBufferResource(',
        'CreateGlobalBufferResource(',
        'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH'
    )) {
        if (-not $p.Contains($m)) {
            Fail "Presenter anchor ausente: $m"
        }
    }
}

$cli = [IO.File]::ReadAllText($CliPath)
foreach ($m in @(
    '[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]',
    '[V76.3.21.0][FORWARD_MAX_MERGE]',
    '[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536]',
    'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
    'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
    'Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");'
)) {
    if (-not $cli.Contains($m)) {
        Fail "V21.1 baseline contract ausente: $m"
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
    "V21.1=preserved nonblocking-refresh=preserved " +
    "snapshot-contract=partial-is-deferred"
)
