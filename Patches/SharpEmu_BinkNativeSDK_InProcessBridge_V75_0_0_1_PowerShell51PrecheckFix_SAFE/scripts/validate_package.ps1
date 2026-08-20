. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-PackageRoot
$manifest = Join-Path $root 'MANIFEST.sha256'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "$script:Tag MANIFEST.sha256 missing."
}

$lines = @(
    Get-Content -LiteralPath $manifest |
        Where-Object { $_.Trim().Length -gt 0 }
)

$count = 0
foreach ($line in $lines) {
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

$escapeToken =
    ([char]96).ToString() +
    'r' +
    ([char]96).ToString() +
    'n'

foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $scriptText = Get-Content -LiteralPath $scriptFile.FullName -Raw

    if ($scriptText -match '(?im)foreach\s*\(\s*\$error\s+in\s+') {
        throw "$script:Tag Reserved automatic-variable iterator detected in $($scriptFile.Name)."
    }

    if ($scriptText.Contains($escapeToken)) {
        throw "$script:Tag Literal escaped-CRLF token detected in $($scriptFile.Name)."
    }
}

$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($path in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path.FullName,
        [ref]$tokens,
        [ref]$parseErrors)

    foreach ($parseError in @($parseErrors)) {
        $parseFailures.Add(
            ("{0}:{1}:{2}: {3} :: {4}" -f
                $path.Name,
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


# V75.0.0.1: PowerShell treats "-or" following an unparenthesized
# command invocation as part of the command argument list.  Reject:
#
#   if (Test-Path ... -or
#       Test-Path ...) {
#
# and require:
#
#   if ((Test-Path ...) -or
#       (Test-Path ...)) {
$invalidCmdletBooleanPattern =
    '(?ms)if[ \t]*\([ \t\r\n]*Test-Path\b[^)]*?-or[ \t\r\n]+Test-Path\b'

foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $scriptText = Get-Content -LiteralPath $scriptFile.FullName -Raw

    if ([regex]::IsMatch(
            $scriptText,
            $invalidCmdletBooleanPattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "$script:Tag Unparenthesized Test-Path boolean expression detected in $($scriptFile.Name)."
    }
}

Write-Step "PowerShell51CmdletBooleanGuard=True"

Write-Step "PowerShell51RawSourceGuard=True"

# Execute actual source transforms against full archived fixtures.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) (
    'SharpEmuNativeRadV7500_' +
    [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $hostFixture = Join-Path $temp 'HostMovieBridge.cs'
    $playbackFixture = Join-Path $temp 'MediaFramePlayback.cs'

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\HostMovieBridge.cs') `
        -Destination $hostFixture -Force
    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\MediaFramePlayback.cs') `
        -Destination $playbackFixture -Force

    & (Join-Path $PSScriptRoot 'patch_host_movie_bridge_v7500.ps1') `
        -Path $hostFixture
    & (Join-Path $PSScriptRoot 'patch_media_frame_playback_v7500.ps1') `
        -Path $playbackFixture

    $hostText = Get-Content -LiteralPath $hostFixture -Raw
    $playbackText = Get-Content -LiteralPath $playbackFixture -Raw

    foreach ($required in @(
        'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0',
        'MovieMode.NativeRad',
        'AttachRadNativeMovieLocked',
        'SHARPEMU_BINK_NATIVE_PREFER',
        'SHARPEMU_BINK_NATIVE_FALLBACK'
    )) {
        if ($hostText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag Host fixture regression missing: $required"
        }
    }

    foreach ($required in @(
        'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0',
        'IMediaPlaybackClockSource',
        'IMediaFrameBufferPolicy',
        'PrimeFirstFrameSynchronously',
        '[BINK-NATIVE][V75.0.0] playback_buffers'
    )) {
        if ($playbackText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
            throw "$script:Tag Playback fixture regression missing: $required"
        }
    }

    Write-Step "REAL_SOURCE_TRANSFORM_REGRESSION=PASSED"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($sourceFile in @(
    'source\managed\BinkNativeSdkAbiV7500.cs',
    'source\managed\RadBinkNativeSdkDecoderV7500.cs',
    'source\native\SharpEmu.BinkNative.cpp'
)) {
    $sourceText = Get-Content -LiteralPath (
        Join-Path $root $sourceFile) -Raw

    if ($sourceText.IndexOf(
            'V75.0.0',
            [StringComparison]::Ordinal) -lt 0 -and
        $sourceFile -notmatch '\.cpp$') {
        throw "$script:Tag Generated source version marker missing: $sourceFile"
    }
}

$cpp = Get-Content -LiteralPath (
    Join-Path $root 'source\native\SharpEmu.BinkNative.cpp') -Raw

foreach ($required in @(
    'se_bink_abi_version',
    'se_bink_open_utf8',
    'se_bink_decode_bgra',
    'se_bink_get_clock_us',
    'BinkOpen',
    'BinkWait',
    'BinkDoFrame',
    'BinkCopyToBuffer',
    'BinkNextFrame',
    'BinkClose'
)) {
    if ($cpp.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Native adapter source marker missing: $required"
    }
}

Write-Step "NativeStableAbi=True"
Write-Step "NativeAdapterSource=True"
Write-Step "ExternalRadFallback=True"
Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell51 cmdlet-boolean guard + parser + full-source transform regression passed)."
