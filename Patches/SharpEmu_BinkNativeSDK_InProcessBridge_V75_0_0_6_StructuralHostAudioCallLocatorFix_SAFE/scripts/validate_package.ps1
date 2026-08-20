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


$mediaPatchText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'patch_media_frame_playback_v7500.ps1') -Raw

foreach ($requiredLocator in @(
    '(?ms)^[ \t]*internal[ \t]+interface',
    'IDisposable[ \t\r\n]*\{',
    '(?ms)^[ \t]*private[ \t]+double',
    'CurrentPlaybackSecondsLocked[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'
)) {
    if ($mediaPatchText.IndexOf(
            $requiredLocator,
            [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Multiline MediaFramePlayback locator marker missing: $requiredLocator"
    }
}

$obsoleteInterfaceLocator =
    "(?m)^[ \t]*internal[ \t]+interface[ \t]+IMediaFrameDecoder"

$obsoleteCurrentLocator =
    "(?m)^[ \t]*private[ \t]+double[ \t]+CurrentPlaybackSecondsLocked"

if ($mediaPatchText.IndexOf(
        $obsoleteInterfaceLocator,
        [StringComparison]::Ordinal) -ge 0) {
    throw "$script:Tag Same-line-only IMediaFrameDecoder locator was reintroduced."
}

if ($mediaPatchText.IndexOf(
        $obsoleteCurrentLocator,
        [StringComparison]::Ordinal) -ge 0) {
    throw "$script:Tag Same-line-only CurrentPlaybackSecondsLocked locator was reintroduced."
}

Write-Step "MultilineMediaInterfaceLocator=True"
Write-Step "MultilinePlaybackClockLocator=True"


$mediaPatchBody = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'patch_media_frame_playback_v7500.ps1') -Raw

foreach ($requiredBodyLocator in @(
    '$followPattern',
    '$bufferLoopPattern',
    '$primePattern',
    '$progressPattern',
    '$clockGuardPattern',
    'Structural guest-audio clock assignment',
    'Structural BufferCount allocation loop',
    'Structural first-frame prime condition',
    'Structural PlaybackProgress clock expression',
    'Structural CurrentPlaybackSecondsLocked startup guard'
)) {
    if ($mediaPatchBody.IndexOf(
            $requiredBodyLocator,
            [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Structural MediaFramePlayback body locator missing: $requiredBodyLocator"
    }
}

foreach ($obsoleteBodyLocator in @(
    '$followOld = @',
    '$progressOld = @',
    '$clockAnchor = @'
)) {
    if ($mediaPatchBody.IndexOf(
            $obsoleteBodyLocator,
            [StringComparison]::Ordinal) -ge 0) {
        throw "$script:Tag Brittle MediaFramePlayback exact-block locator reintroduced: $obsoleteBodyLocator"
    }
}

Write-Step "StructuralGuestClockLocator=True"
Write-Step "StructuralBufferLoopLocator=True"
Write-Step "StructuralPrimeLocator=True"
Write-Step "StructuralPlaybackProgressLocator=True"
Write-Step "StructuralPlaybackStartupGuard=True"


# V75.0.0.4: PowerShell variable names are case-insensitive.  Names such as
# $Host, $PID and $PSVersionTable are automatic/read-only variables, so local
# aliases like $host are not safe.
$reservedAssignmentPattern =
    '(?im)^[ \t]*\$(host|pid|psversiontable|psscriptroot|pscommandpath|pwd|shellid)[ \t]*='

$reservedForeachPattern =
    '(?im)foreach[ \t]*\([ \t]*\$(host|pid|psversiontable|psscriptroot|pscommandpath|pwd|shellid|error)[ \t]+in[ \t]+'

foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $scriptText = Get-Content -LiteralPath $scriptFile.FullName -Raw

    $assignmentMatch = [regex]::Match(
        $scriptText,
        $reservedAssignmentPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    if ($assignmentMatch.Success) {
        throw "$script:Tag Reserved PowerShell automatic-variable assignment detected in $($scriptFile.Name): $($assignmentMatch.Value.Trim())"
    }

    $foreachMatch = [regex]::Match(
        $scriptText,
        $reservedForeachPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    if ($foreachMatch.Success) {
        throw "$script:Tag Reserved PowerShell automatic-variable foreach iterator detected in $($scriptFile.Name): $($foreachMatch.Value.Trim())"
    }
}

Write-Step "PowerShellReservedAutomaticVariableGuard=True"


# V75.0.0.5: use the PowerShell AST rather than raw-text scanning. This
# catches an executable C#-style call:
#
#   Environment.GetEnvironmentVariable(...)
#
# while correctly ignoring that same text when it is merely C# source stored
# inside a PowerShell here-string for HostMovieBridge patching.
foreach ($scriptFile in Get-ChildItem -LiteralPath (
        Join-Path $root 'scripts') -Filter '*.ps1' -File) {
    $astTokens = $null
    $astParseErrors = $null
    $scriptAst =
        [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$astTokens,
            [ref]$astParseErrors)

    $invalidStaticCommands = @(
        $scriptAst.FindAll(
            {
                param($node)

                if ($node -isnot
                    [System.Management.Automation.Language.CommandAst]) {
                    return $false
                }

                $commandName = $node.GetCommandName()
                return
                    -not [string]::IsNullOrWhiteSpace($commandName) -and
                    $commandName.Equals(
                        'Environment.GetEnvironmentVariable',
                        [StringComparison]::OrdinalIgnoreCase)
            },
            $true)
    )

    if ($invalidStaticCommands.Count -gt 0) {
        $firstInvalid = $invalidStaticCommands[0]
        throw "$script:Tag C#-style executable static .NET call detected in $($scriptFile.Name) at line $($firstInvalid.Extent.StartLineNumber): $($firstInvalid.Extent.Text)"
    }
}

Write-Step "PowerShellStaticDotNetAstGuard=True"


$hostPatchText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'patch_host_movie_bridge_v7500.ps1') -Raw

foreach ($requiredHostLocator in @(
    'Find-MethodRegion',
    '$audioCallPattern',
    'HostAudioCallMethodBound=True',
    'NativeRadSwitchCaseMethodBound=True',
    'StructuralAttachRadMethodLocator=True',
    'ResolveModePrefixPolicy=True',
    'StructuralMovieModeEnumLocator=True'
)) {
    if ($hostPatchText.IndexOf(
            $requiredHostLocator,
            [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Structural HostMovieBridge locator marker missing: $requiredHostLocator"
    }
}

if ($hostPatchText.IndexOf(
        '$audioPattern =',
        [StringComparison]::Ordinal) -ge 0) {
    throw "$script:Tag Obsolete full host-audio if-block locator was reintroduced."
}

Write-Step "StructuralHostAudioCallLocator=True"
Write-Step "MethodBoundHostSwitchLocator=True"
Write-Step "ResolveModePrefixPolicy=True"
Write-Step "StructuralHostEnumLocator=True"

Write-Step "PowerShell51RawSourceGuard=True"

# Execute actual source transforms against full archived fixtures.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) (
    'SharpEmuNativeRadV7500_' +
    [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $hostFixture = Join-Path $temp 'HostMovieBridge.cs'
    $hostAccumulatedFixture =
        Join-Path $temp 'HostMovieBridge_AccumulatedAudioGate.cs'
    $playbackFixture = Join-Path $temp 'MediaFramePlayback.cs'

    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\HostMovieBridge.cs') `
        -Destination $hostFixture -Force
    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\HostMovieBridge_AccumulatedAudioGate.cs') `
        -Destination $hostAccumulatedFixture -Force
    Copy-Item -LiteralPath (
        Join-Path $root 'tests\fixtures\MediaFramePlayback.cs') `
        -Destination $playbackFixture -Force

    & (Join-Path $PSScriptRoot 'patch_host_movie_bridge_v7500.ps1') `
        -Path $hostFixture
    & (Join-Path $PSScriptRoot 'patch_host_movie_bridge_v7500.ps1') `
        -Path $hostAccumulatedFixture
    & (Join-Path $PSScriptRoot 'patch_media_frame_playback_v7500.ps1') `
        -Path $playbackFixture

    $hostText = Get-Content -LiteralPath $hostFixture -Raw
    $hostAccumulatedText =
        Get-Content -LiteralPath $hostAccumulatedFixture -Raw
    $playbackText = Get-Content -LiteralPath $playbackFixture -Raw

    foreach ($hostVariant in @(
        [ordered]@{
            Name = 'archived'
            Text = $hostText
        },
        [ordered]@{
            Name = 'accumulated-audio-gate'
            Text = $hostAccumulatedText
        }
    )) {
        foreach ($required in @(
            'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0',
            'MovieMode.NativeRad',
            'AttachRadNativeMovieLocked',
            'SHARPEMU_BINK_NATIVE_PREFER',
            'SHARPEMU_BINK_NATIVE_FALLBACK',
            'if (mode != MovieMode.NativeRad)',
            'v7500Configured'
        )) {
            if ($hostVariant.Text.IndexOf(
                    $required,
                    [StringComparison]::Ordinal) -lt 0) {
                throw "$script:Tag Host fixture '$($hostVariant.Name)' regression missing: $required"
            }
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
Write-Step "PACKAGE VALIDATION PASSED ($count hashed files; PowerShell51 guards + archived/accumulated HostMovieBridge regressions + structural source transforms passed)."
