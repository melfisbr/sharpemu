param()
. (Join-Path $PSScriptRoot 'common.ps1')

# V18.1 is intentionally a consolidation/profile merge. It does not ship a
# complete Presenter or AGC source and therefore cannot overwrite later fixes.
if (Test-Path -LiteralPath (Join-Path $PackageRoot 'files')) {
    Fail 'V18.1 nao deve conter source completo'
}

$apply = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'apply_build.ps1'))
foreach ($m in @(
    '[V76.3.18.1][MAX_THROUGHPUT_PROFILE]',
    'SHARPEMU_V763181_SAFE_MODE',
    'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH',
    'SHARPEMU_SHADER_GLOBAL_RESIDENCY',
    'SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180',
    'SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716',
    'SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX',
    'SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX',
    'SHARPEMU_VK_DEVICE_LOCAL_GLOBALS',
    'SHARPEMU_REBAR_GLOBAL_DIRECT_V1190',
    'SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633',
    'SHARPEMU_DRAW_COMMAND_BUFFER_MAX',
    'SHARPEMU_WAIT_FULL_SCAN_MIN_MS'
)) {
    if (-not $apply.Contains($m)) {
        Fail "profile contract ausente: $m"
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
    "mode=authoritative-profile source_replacement=0 fallbacks=1"
)
