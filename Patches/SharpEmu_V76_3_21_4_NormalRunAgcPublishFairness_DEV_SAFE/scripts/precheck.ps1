param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$agc = [IO.File]::ReadAllText($AgcPath)
$presenter = [IO.File]::ReadAllText($PresenterPath)

foreach ($m in @(
    'V76.3.21.3.1.1.2_AUTHORITATIVE_CLOSURE_SYNC_BEGIN',
    '[V76.3.21.3.1.1.2][AUTHORITATIVE_GUEST_PROGRESS]',
    '_producerDependencyClosureSyncScanCapV76383',
    '? 512'
)) {
    if (-not $presenter.Contains($m)) { Fail "baseline Sync512 ausente no Presenter: $m" }
}

foreach ($m in @(
    'public static int DcbWriteData(CpuContext ctx)',
    'public static int CbReleaseMem(CpuContext ctx)',
    'public static int DriverSubmitDcb(CpuContext ctx)',
    'public static int DriverSubmitAcb(CpuContext ctx)',
    'public static int DriverSubmitMultiDcbs(CpuContext ctx)'
)) {
    if (-not $agc.Contains($m)) { Fail "AGC anchor ausente: $m" }
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source }
if (-not $dotnet) { Fail 'dotnet nao encontrado' }

$already = $agc.Contains('V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN')
Write-Host "[$Tag] PRECHECK PASSED sync512=1 agc_builder_anchors=2 submit_anchors=3 already_applied=$([int]$already) agc_sha256=$(Get-HashLower $AgcPath)"
