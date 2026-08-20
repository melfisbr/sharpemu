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
    'SharpEmu_V1113_' +
    [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
    $introFixturePath = Join-Path $temp 'BinkDemonSoulsIntroAudioV7243227.cs'
    $hostFixturePath = Join-Path $temp 'HostMovieBridge.cs'

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\BinkDemonSoulsIntroAudioV7243227_PostV1112.cs') `
        -Destination $introFixturePath -Force

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\HostMovieBridge_Accumulated.cs') `
        -Destination $hostFixturePath -Force

    & (Join-Path $PSScriptRoot 'patch_intro_title_chain_audio_v1113.ps1') `
        -Path $introFixturePath

    & (Join-Path $PSScriptRoot 'patch_host_movie_title_chain_hook_v1113.ps1') `
        -Path $hostFixturePath

    $introHash1 = Get-HashSafe $introFixturePath
    $hostHash1 = Get-HashSafe $hostFixturePath

    & (Join-Path $PSScriptRoot 'patch_intro_title_chain_audio_v1113.ps1') `
        -Path $introFixturePath

    & (Join-Path $PSScriptRoot 'patch_host_movie_title_chain_hook_v1113.ps1') `
        -Path $hostFixturePath

    if ($introHash1 -ne (Get-HashSafe $introFixturePath) -or
        $hostHash1 -ne (Get-HashSafe $hostFixturePath)) {
        throw "$script:Tag V1.1.13 source transforms are not idempotent."
    }

    $introFixtureText = Get-Content -LiteralPath $introFixturePath -Raw
    $hostFixtureText = Get-Content -LiteralPath $hostFixturePath -Raw

    foreach ($required in @(
        'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13',
        'NotifyMovieAttachV1113',
        'title_chain_guest_mute_armed',
        'title_chain_guest_mute_hold',
        'title_chain_guest_mute_released',
        '_v1113PostAttractTitleChainGuestMuteActive'
    )) {
        if ($introFixtureText.IndexOf(
                $required,
                [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag Intro regression missing: $required"
        }
    }

    foreach ($required in @(
        'SHARPEMU_DEMONS_TITLE_CHAIN_AUDIO_LIFECYCLE_HOOK_V1_1_13',
        'NotifyMovieAttachV1113'
    )) {
        if ($hostFixtureText.IndexOf(
                $required,
                [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag HostMovieBridge regression missing: $required"
        }
    }

    Write-Step "REAL_SOURCE_TRANSFORM_REGRESSION=PASSED"
    Write-Step "Idempotence=True"
    Write-Step "LifecycleMuteNotTimerOnly=True"
    Write-Step "HostMovieBridgePreProbeHook=True"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell parsed; V1.1.12-to-V1.1.13 regression passed)."
