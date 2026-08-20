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

$temp = Join-Path ([IO.Path]::GetTempPath()) (
    'SharpEmu_V1114_' +
    [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
    $fixturePath = Join-Path $temp 'BinkDemonSoulsIntroAudioV7243227.cs'

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\BinkDemonSoulsIntroAudioV7243227_PostV1113.cs') `
        -Destination $fixturePath -Force

    & (Join-Path $PSScriptRoot 'patch_title_loop_audio_release_v1114.ps1') `
        -Path $fixturePath

    $hash1 = Get-HashSafe $fixturePath

    & (Join-Path $PSScriptRoot 'patch_title_loop_audio_release_v1114.ps1') `
        -Path $fixturePath

    $hash2 = Get-HashSafe $fixturePath

    if ($hash1 -ne $hash2) {
        throw "$script:Tag V1.1.14 transform is not idempotent."
    }

    $fixtureText = Get-Content -LiteralPath $fixturePath -Raw

    foreach ($required in @(
        'SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14',
        'title_intro_guest_drain_hold',
        'title_loop_guest_audio_release',
        'residual_v1112_drain_ms=',
        'guest_audio_release_requested=True'
    )) {
        if ($fixtureText.IndexOf(
                $required,
                [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag Regression missing: $required"
        }
    }

    if ($fixtureText -match '\[BINK-AUDIO-OWNER\]\[V1\.1\.13\] title_chain_guest_mute_hold') {
        throw "$script:Tag Obsolete V1.1.13 loop-hold body survived replacement."
    }

    Write-Step "REAL_SOURCE_TRANSFORM_REGRESSION=PASSED"
    Write-Step "Idempotence=True"
    Write-Step "LogoIntroDrainHold=True"
    Write-Step "LogoIntroLoopGuestRelease=True"
    Write-Step "ResidualV1112MinimumDrainPreserved=True"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; post-V1.1.13 transform regression passed)."
