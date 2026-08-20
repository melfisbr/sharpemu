param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tag = '[V74.0.56.36.1]'

$root = [IO.Path]::GetFullPath(
    ($PackageRoot.Trim().Trim('"') -replace '[\r\n]+$', '')
)

$manifestPath = Join-Path $root 'SHA256SUMS.txt'

$lines = Get-Content -LiteralPath $manifestPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($line in $lines) {
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw ('{0} invalid manifest line: {1}' -f $tag, $line)
    }

    $relative = $Matches[2]
    $path = Join-Path $root $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('{0} missing manifest target: {1}' -f $tag, $relative)
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    $expected = $Matches[1].ToUpperInvariant()

    if ($actual -ne $expected) {
        throw ('{0} hash mismatch: {1}' -f $tag, $relative)
    }
}

$failures = @()
$scriptDir = Join-Path $root 'scripts'

foreach ($ps in Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null

    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps.FullName,
        [ref]$tokens,
        [ref]$errors
    )

    foreach ($parseError in $errors) {
        $message = '{0}: line={1} {2}' -f `
            $ps.Name, `
            $parseError.Extent.StartLineNumber, `
            $parseError.Message

        $failures += $message
    }

    $body = [IO.File]::ReadAllText($ps.FullName)

    if ($body -match '(?im)^\s*\$host\s*=') {
        $failures += ('{0}: forbidden Host assignment' -f $ps.Name)
    }

    if ($body -match '\$[A-Za-z_][A-Za-z0-9_]*-PathType') {
        $failures += ('{0}: glued -PathType' -f $ps.Name)
    }

    if ($body -match '\b[0-9]+UL\b') {
        $failures += ('{0}: C# UL literal forbidden in PowerShell' -f $ps.Name)
    }
}

if ($failures.Count -ne 0) {
    throw ('{0} SCRIPT VALIDATION FAILED: {1}' -f $tag, ($failures -join ' | '))
}

$gbuffer = [IO.File]::ReadAllText(
    (Join-Path $root 'patch\AgcExports.gbuffer.replace.txt')
)

foreach ($guard in @(
    'pixelShaderAddress == 0x0000000448639500UL',
    'targetV7405636.Slot == 1',
    'targetV7405636.Address == 0x0000000460890000UL',
    'targetV7405636.Width == 2560',
    'targetV7405636.Height == 1440',
    'targetV7405636.Format == 10',
    'targetV7405636.NumberType == 0',
    'targetV7405636.TileMode == 27',
    '0x0000000486B13000UL'
)) {
    if ($gbuffer.IndexOf($guard, [StringComparison]::Ordinal) -lt 0) {
        throw ('{0} G-buffer contract guard missing: {1}' -f $tag, $guard)
    }
}

$presenterInsertion = [IO.File]::ReadAllText(
    (Join-Path $root 'patch\VulkanVideoPresenter.consider_insertion.txt')
)

foreach ($guard in @(
    'SHARPEMU_V74_0_56_36_1_DCC_INITIALIZED_ADDRESS_GUARD',
    'texture.GpuReferenceOnly',
    '!candidate.Initialized'
)) {
    if ($presenterInsertion.IndexOf($guard, [StringComparison]::Ordinal) -lt 0) {
        throw ('{0} Presenter guard missing: {1}' -f $tag, $guard)
    }
}

$run = [IO.File]::ReadAllText(
    (Join-Path $root 'scripts\run_test.ps1')
)

foreach ($pattern in @(
    "'SHARPEMU_DS_GBUFFER_LIGHTING_CONTRACT'\s*=\s*'1'",
    "'SHARPEMU_DCC_FASTCLEAR_IMMEDIATE_MATERIALIZE'\s*=\s*'1'",
    "'SHARPEMU_TRACE_GBUFFER_LIGHTING'\s*=\s*'1'",
    "'SHARPEMU_DEDICATED_WAIT_DRAIN'\s*=\s*'0'",
    "'SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN'\s*=\s*'0'"
)) {
    if (-not [regex]::IsMatch($run, $pattern)) {
        throw ('{0} runtime guard missing regex={1}' -f $tag, $pattern)
    }
}

Write-Host (
    ('{0} PACKAGE VALIDATION PASSED ({1} hashed files; PowerShell scripts parsed; structural Presenter guard enabled).' -f `
        $tag, `
        $lines.Count)
) -ForegroundColor Green
