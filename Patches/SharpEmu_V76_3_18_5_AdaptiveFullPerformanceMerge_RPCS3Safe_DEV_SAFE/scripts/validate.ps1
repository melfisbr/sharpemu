param()
. (Join-Path $PSScriptRoot 'common.ps1')

$required = @(
    'common.ps1',
    'precheck.ps1',
    'apply_build.ps1',
    'diagnostic.ps1',
    'normal_launch.ps1',
    'rollback.ps1'
)
foreach ($name in $required) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "script ausente: $name"
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
    "mode=adaptive-current-source full-presenter-replacement=0"
)
