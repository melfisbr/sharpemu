param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$agc = [IO.File]::ReadAllText($AgcPath)
$presenter = [IO.File]::ReadAllText($PresenterPath)
$cli = [IO.File]::ReadAllText($CliProfilePath)

foreach ($m in @(
    'V76.3.21.3.1.1.2_AUTHORITATIVE_CLOSURE_SYNC_BEGIN',
    '[V76.3.21.3.1.1.2][AUTHORITATIVE_GUEST_PROGRESS]',
    '_producerDependencyClosureSyncScanCapV76383',
    '? 512'
)) {
    if (-not $presenter.Contains($m)) {
        Fail "baseline Sync512 ausente no Presenter: $m"
    }
}

foreach ($m in @(
    '[V76.3.21.3][GUEST_PROGRESS_RECOVERY]',
    'SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH',
    '"512"',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES',
    '"8"',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US',
    '"1000"'
)) {
    if (-not $cli.Contains($m)) {
        Fail "baseline V21.3 ausente no CLI profile: $m"
    }
}

foreach ($m in @(
    'public static int DcbWriteData(CpuContext ctx)',
    'public static int CbReleaseMem(CpuContext ctx)',
    'public static int DriverSubmitDcb(CpuContext ctx)',
    'public static int DriverSubmitAcb(CpuContext ctx)',
    'private static void EnqueueSubmittedDcb('
)) {
    if (-not $agc.Contains($m)) {
        Fail "AGC anchor ausente: $m"
    }
}

$hasBlock = $agc.Contains('V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN')
$hasBuilderHook = $agc.Contains('NoteAgcBuilderV763214(')
$hasSubmitHook = $agc.Contains('NoteAgcDriverSubmitV763214(')
$hasYield = $agc.Contains('System.Threading.Thread.Yield()')

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source }
if (-not $dotnet) { Fail 'dotnet nao encontrado' }

Write-Host "[$Tag] PRECHECK PASSED sync512=1 v213=1 fairness_block=$([int]$hasBlock) builder_hook=$([int]$hasBuilderHook) submit_hook=$([int]$hasSubmitHook) yield=$([int]$hasYield) agc_sha256=$(Get-HashLower $AgcPath)"
