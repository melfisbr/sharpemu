param()
. (Join-Path $PSScriptRoot 'common.ps1')

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

$apply = [IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot 'apply_build.ps1'))

foreach ($m in @(
    'V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS',
    'partialSnapshotV763212',
    '_v763212PartialGlobalSnapshotCount',
    'guestBuffer.Data.Length < guestBuffer.Length',
    '[V76.3.21.2][GLOBAL_SNAPSHOT_REPAIR]'
)) {
    if (-not $apply.Contains($m)) {
        Fail "transform contract ausente: $m"
    }
}

Write-Host (
    "[$Tag] VALIDATE PASSED " +
    "mode=adaptive-in-place crash=ArgumentOutOfRange-global-snapshot"
)
