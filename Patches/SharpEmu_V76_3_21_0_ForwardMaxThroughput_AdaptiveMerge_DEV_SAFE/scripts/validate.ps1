param()
. (Join-Path $PSScriptRoot 'common.ps1')

# This package intentionally ships no complete source replacement.
# It is a forward merge against the installed checkout.
if (Test-Path -LiteralPath (Join-Path $PackageRoot 'files')) {
    Fail 'forward merge nao deve conter source completo'
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

$apply = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'apply_build.ps1'))
foreach ($m in @(
    'SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210',
    'SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION',
    'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH',
    'SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION',
    'SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES',
    'SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716',
    'SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180',
    'SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX',
    'SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX',
    '[V76.3.21.0][FORWARD_MAX_MERGE]'
)) {
    if (-not $apply.Contains($m)) {
        Fail "package contract ausente: $m"
    }
}

Write-Host (
    "[$Tag] VALIDATE PASSED " +
    "mode=forward-structural source_replacement=0 " +
    "safe_fallback=1 max_profile=1"
)
