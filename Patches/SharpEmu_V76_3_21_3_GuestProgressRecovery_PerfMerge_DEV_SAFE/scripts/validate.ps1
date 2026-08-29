param()
. (Join-Path $PSScriptRoot 'common.ps1')

$files = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File |
    Where-Object { $_.Name -ne 'validate.ps1' }

$bad = Select-String -Path $files.FullName `
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
    '[V76.3.21.3][GUEST_PROGRESS_RECOVERY]',
    'SHARPEMU_MAX_GUEST_WORK_PER_RENDER',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES',
    'SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US',
    'SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH',
    'SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX',
    'SHARPEMU_COMPUTE_CHAIN_MAX_V763171',
    'SHARPEMU_DRAW_COMMAND_BUFFER_MAX',
    'SHARPEMU_WAIT_FULL_SCAN_MIN_MS'
)) {
    if (-not $apply.Contains($m)) {
        Fail "contract ausente: $m"
    }
}

Write-Host (
    "[$Tag] VALIDATE PASSED " +
    "merge=V21.2-preserved + V17.1-progress-contract"
)
