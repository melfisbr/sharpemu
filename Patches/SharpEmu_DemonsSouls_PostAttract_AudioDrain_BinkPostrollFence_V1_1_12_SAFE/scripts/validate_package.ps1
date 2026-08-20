. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-PackageRoot
$manifest = Join-Path $root 'MANIFEST.sha256'

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "$script:Tag MANIFEST.sha256 missing."
}

$count = 0
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw "$script:Tag Invalid manifest line: $line"
    }

    $expected = $Matches[1].ToUpperInvariant()
    $relative = $Matches[2].Replace('/', '\')
    $path = Join-Path $root $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$script:Tag Manifest file missing: $relative"
    }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($actual -ne $expected) {
        throw "$script:Tag Hash mismatch: $relative"
    }

    $count++
}

# Parse every executable PowerShell script.
$parseFailures = New-Object System.Collections.Generic.List[string]

foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors)

    foreach ($parseError in @($parseErrors)) {
        $parseFailures.Add(
            ("{0}:{1}:{2}: {3} :: {4}" -f
                $scriptFile.Name,
                $parseError.Extent.StartLineNumber,
                $parseError.Extent.StartColumnNumber,
                $parseError.Message,
                $parseError.Extent.Text))
    }
}

if ($parseFailures.Count -gt 0) {
    $parseFailures | ForEach-Object { Write-Host $_ }
    throw "$script:Tag PowerShell parsing failed."
}

# Guard common PowerShell mistakes seen in prior package iterations.
foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $scriptText = Get-Content -LiteralPath $scriptFile.FullName -Raw

    if ($scriptText -match '(?im)^[ \t]*\$host[ \t]*=') {
        throw "$script:Tag Reserved `$Host assignment detected in $($scriptFile.Name)."
    }

    if ($scriptText -match '(?im)foreach\s*\(\s*\$error\s+in\s+') {
        throw "$script:Tag Reserved `$Error iterator detected in $($scriptFile.Name)."
    }
}

Write-Step "PowerShell51Guards=True"

# Full-source transform regression with accumulated-like fixtures.
$temp = Join-Path ([IO.Path]::GetTempPath()) (
    'SharpEmu_V1112_' +
    [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
    $introFixture = Join-Path $temp 'BinkDemonSoulsIntroAudioV7243227.cs'
    $radFixture = Join-Path $temp 'RadBinkEmbeddedHostApiV724323171.cs'

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\BinkDemonSoulsIntroAudioV7243227.cs') `
        -Destination $introFixture -Force

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\RadBinkEmbeddedHostApiV724323171.cs') `
        -Destination $radFixture -Force

    & (Join-Path $PSScriptRoot 'patch_intro_post_attract_fence_v1112.ps1') `
        -Path $introFixture

    & (Join-Path $PSScriptRoot 'patch_rad_attract_postroll_fence_v1112.ps1') `
        -Path $radFixture

    $introHash1 = Get-HashSafe $introFixture
    $radHash1 = Get-HashSafe $radFixture

    # Idempotence.
    & (Join-Path $PSScriptRoot 'patch_intro_post_attract_fence_v1112.ps1') `
        -Path $introFixture

    & (Join-Path $PSScriptRoot 'patch_rad_attract_postroll_fence_v1112.ps1') `
        -Path $radFixture

    $introHash2 = Get-HashSafe $introFixture
    $radHash2 = Get-HashSafe $radFixture

    if ($introHash1 -ne $introHash2 -or
        $radHash1 -ne $radHash2) {
        throw "$script:Tag Source transforms are not idempotent."
    }

    $intro = Get-Content -LiteralPath $introFixture -Raw
    $rad = Get-Content -LiteralPath $radFixture -Raw

    foreach ($required in @(
        'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12',
        'post_attract_guest_drain_armed',
        'post_attract_guest_drain_released',
        'post_attract_host_audio_blocked',
        'SHARPEMU_DS_POST_ATTRACT_GUEST_DRAIN_MS',
        'TryConsumePostAttractHostAudioBlockV1112',
        'guest_pacing_preserved=True'
    )) {
        if ($intro.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag Intro fixture regression missing: $required"
        }
    }

    foreach ($required in @(
        'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12',
        'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_LEAD_MS',
        'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_MS',
        'ArmAttractPostrollFenceV1112',
        'EnforceAttractPostrollHiddenV1112',
        'rehide_period_ms=10',
        'attract_nominal_end',
        '_v1112MoviePath',
        'moviePath,'
    )) {
        if ($rad.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag RAD fixture regression missing: $required"
        }
    }

    if ($rad -notmatch 'anchorMs\s*,\s*moviePath\s*,\s*nominalDurationMilliseconds') {
        throw "$script:Tag RAD fixture constructor call does not pass moviePath."
    }

    if ($rad -notmatch 'string\s+moviePath\s*,\s*double\s+nominalDurationMilliseconds') {
        throw "$script:Tag RAD fixture constructor signature does not receive moviePath."
    }

    Write-Step "REAL_SOURCE_TRANSFORM_REGRESSION=PASSED"
    Write-Step "Idempotence=True"
    Write-Step "PostAttractGuestDrain=True"
    Write-Step "PostAttractHostAudioBlock=True"
    Write-Step "PersistentRadPostrollFence=True"
    Write-Step "AttractNominalAudioStop=True"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; accumulated source regression passed)."
