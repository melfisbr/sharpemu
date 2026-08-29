param()
. (Join-Path $PSScriptRoot 'common.ps1')

$payload = Join-Path $PackageRoot `
    'files\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

if (-not (Test-Path -LiteralPath $payload -PathType Leaf)) {
    Fail 'payload VulkanVideoPresenter.cs ausente'
}

if ((Get-HashLower $payload) -ne $ExpectedPresenterResult) {
    Fail 'payload Presenter hash divergente'
}

$t = [IO.File]::ReadAllText($payload)
foreach ($m in @(
    'V76.3.18.0_RPCS3_INSPIRED_ASYNC_CB_POOL',
    'MaxRecycledGuestCommandBuffers = 256',
    'V76.3.18.0_RPCS3_INSPIRED_QUEUE_CAPABILITY',
    'SHARPEMU_V763180_FORCE_SINGLE',
    '[V76.3.18.0][QUEUE_ARCHITECTURE]',
    'selectedFamilyQueueCountV1131 >= 2',
    'timelineSupportedV1131',
    '_computeQueueTimelineSemaphoreV1131'
)) {
    if (-not $t.Contains($m)) {
        Fail "payload contract ausente: $m"
    }
}

foreach ($m in @(
    'ResolveCrossQueueWaitV7615(',
    'CommitCrossQueueAccessV7615(',
    'ResolvePhysicalCrossQueueWaitV76383(',
    'ResolvePresentComputeWaitV76383(',
    'RecordComputeBatchDependencyV74099();'
)) {
    if (-not $t.Contains($m)) {
        Fail "hazard/timeline contract ausente: $m"
    }
}

$scriptFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File |
    Where-Object { $_.Name -ne 'validate.ps1' }

$bad = Select-String -Path $scriptFiles.FullName `
    -Pattern @(
        'Invoke-WebRequest',
        'Invoke-RestMethod',
        'Start-BitsTransfer',
        'curl.exe',
        'wget.exe'
    ) `
    -SimpleMatch `
    -ErrorAction SilentlyContinue

if ($bad) {
    Fail 'downloader direto proibido'
}

Write-Host (
    "[$Tag] VALIDATE PASSED " +
    "presenter=V17.1+queue-capability cb_pool=256 cli=adaptive"
)
