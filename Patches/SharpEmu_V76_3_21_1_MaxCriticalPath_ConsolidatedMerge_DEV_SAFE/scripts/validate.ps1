param()
. (Join-Path $PSScriptRoot 'common.ps1')

$expected = @(
    'RUN_1_VALIDATE_PACKAGE.cmd',
    'RUN_2_PRECHECK.cmd',
    'RUN_3_APPLY_BUILD.cmd',
    'RUN_4_DIAGNOSTIC.cmd',
    'RUN_5_ROLLBACK_LAST.cmd',
    'README_PT-BR.txt',
    'ARCHITECTURE_MERGE.txt',
    'PACKAGE_REPORT.txt'
)

foreach ($name in $expected) {
    $p = Join-Path $PackageRoot $name
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Fail "arquivo do pacote ausente: $name"
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
    "mode=adaptive-in-place changed=Agc+CLI presenter=preserved"
)
