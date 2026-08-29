param()
. (Join-Path $PSScriptRoot 'common.ps1')

$requiredPackageFiles = @(
    'README_PT-BR.txt',
    'PACKAGE_REPORT.txt',
    'scripts\common.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1',
    'scripts\rollback.ps1'
)
foreach ($rel in $requiredPackageFiles) {
    $p = Join-Path $PackageRoot $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Fail "arquivo do pacote ausente: $rel"
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

Write-Host "[$Tag] VALIDATE PASSED mode=adaptive-cli-only source_files=1"
