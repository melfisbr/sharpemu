param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "HostMovieBridge native-rad mode already installed."
    exit 0
}

foreach ($required in @(
    'AttachMovieLocked',
    'AttachRadMovieLocked',
    'ResolveMode',
    'private enum MovieMode',
    'case MovieMode.Rad:',
    'BinkHostAudioBridgeV7241.TryStart',
    'return MovieMode.Rad;'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge baseline marker missing: $required"
    }
}

function Find-MethodRegion(
    [string]$Source,
    [string]$Pattern,
    [string]$Name)
{
    $match = [regex]::Match(
        $Source,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    if (-not $match.Success) {
        throw "$script:Tag Structural method declaration not found: $Name"
    }

    $openBrace = $Source.IndexOf(
        '{',
        $match.Index,
        [StringComparison]::Ordinal)

    if ($openBrace -lt 0) {
        throw "$script:Tag Opening brace missing for method: $Name"
    }

    $closeBrace = Find-MatchingBraceIndex `
        -Text $Source `
        -OpenBraceIndex $openBrace

    return [ordered]@{
        Match = $match
        OpenBrace = $openBrace
        CloseBrace = $closeBrace
        Length = $closeBrace - $match.Index + 1
    }
}

# ---------------------------------------------------------------------------
# 1. Host audio ownership
# ---------------------------------------------------------------------------
# Do not replace the accumulated outer if-condition.  Previous SharpEmu media
# fixes may legitimately add title/lifecycle conditions there.
#
# Instead locate the actual TryStart(hostPath) statement *inside
# AttachMovieLocked* and add one narrow nested guard:
#
#     if (mode != MovieMode.NativeRad)
#         BinkHostAudioBridgeV7241.TryStart(hostPath);
#
# Existing outer semantics are preserved byte-for-byte. NativeRad alone is
# prevented from invoking the generic host-audio bridge, because embedded Bink
# audio belongs to the SDK adapter; attract_movie explicitly starts its AT9
# sidecar later inside AttachRadNativeMovieLocked.
$attachPattern =
    '(?ms)^[ \t]*private[ \t]+static[ \t]+void[ \t]+AttachMovieLocked[ \t]*\([ \t\r\n]*string[ \t]+hostPath[ \t]*,[ \t\r\n]*MovieMode[ \t]+mode[ \t\r\n]*\)[ \t\r\n]*\{'

$attach = Find-MethodRegion `
    -Source $text `
    -Pattern $attachPattern `
    -Name 'AttachMovieLocked'

$attachRegion = $text.Substring(
    $attach.Match.Index,
    $attach.Length)

$audioCallPattern =
    '(?ms)^(?<indent>[ \t]*)BinkHostAudioBridgeV7241\.TryStart[ \t]*\([ \t\r\n]*hostPath[ \t\r\n]*\)[ \t]*;'

$audioCalls = @(
    [regex]::Matches(
        $attachRegion,
        $audioCallPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
)

if ($audioCalls.Count -ne 1) {
    throw "$script:Tag Expected exactly one generic BinkHostAudioBridge.TryStart(hostPath) inside AttachMovieLocked; found $($audioCalls.Count)."
}

$audioCall = $audioCalls[0]
$audioIndent = $audioCall.Groups['indent'].Value
$audioReplacement =
    $audioIndent + '// V75.0.0 native SDK owns embedded Bink audio.' + [Environment]::NewLine +
    $audioIndent + 'if (mode != MovieMode.NativeRad)' + [Environment]::NewLine +
    $audioIndent + '{' + [Environment]::NewLine +
    $audioIndent + '    BinkHostAudioBridgeV7241.TryStart(hostPath);' + [Environment]::NewLine +
    $audioIndent + '}'

$audioAbsolute = $attach.Match.Index + $audioCall.Index
$text = $text.Remove(
    $audioAbsolute,
    $audioCall.Length)
$text = $text.Insert(
    $audioAbsolute,
    $audioReplacement)

Write-Step "HostAudioCallMethodBound=True"

# Re-resolve AttachMovieLocked after the insertion because all later offsets
# must be based on the current text.
$attach = Find-MethodRegion `
    -Source $text `
    -Pattern $attachPattern `
    -Name 'AttachMovieLocked'

$attachRegion = $text.Substring(
    $attach.Match.Index,
    $attach.Length)

# ---------------------------------------------------------------------------
# 2. NativeRad switch case
# ---------------------------------------------------------------------------
$radCasePattern =
    '(?m)^(?<indent>[ \t]*)case[ \t]+MovieMode\.Rad[ \t]*:'

$radCases = @(
    [regex]::Matches(
        $attachRegion,
        $radCasePattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
)

if ($radCases.Count -ne 1) {
    throw "$script:Tag Expected exactly one MovieMode.Rad case inside AttachMovieLocked; found $($radCases.Count)."
}

$radCase = $radCases[0]
$caseIndent = $radCase.Groups['indent'].Value

$nativeCase =
    $caseIndent + '// SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0' + [Environment]::NewLine +
    $caseIndent + 'case MovieMode.NativeRad:' + [Environment]::NewLine +
    $caseIndent + '    if (AttachRadNativeMovieLocked(hostPath))' + [Environment]::NewLine +
    $caseIndent + '    {' + [Environment]::NewLine +
    $caseIndent + '        return;' + [Environment]::NewLine +
    $caseIndent + '    }' + [Environment]::NewLine +
    [Environment]::NewLine +
    $caseIndent + '    if (Environment.GetEnvironmentVariable(' + [Environment]::NewLine +
    $caseIndent + '            "SHARPEMU_BINK_NATIVE_FALLBACK") != "0" &&' + [Environment]::NewLine +
    $caseIndent + '        AttachRadMovieLocked(hostPath))' + [Environment]::NewLine +
    $caseIndent + '    {' + [Environment]::NewLine +
    $caseIndent + '        Console.Error.WriteLine(' + [Environment]::NewLine +
    $caseIndent + '            "[BINK-NATIVE][V75.0.0] fallback_external_rad " +' + [Environment]::NewLine +
    $caseIndent + '            $"file=''{Path.GetFileName(hostPath)}''");' + [Environment]::NewLine +
    $caseIndent + '        return;' + [Environment]::NewLine +
    $caseIndent + '    }' + [Environment]::NewLine +
    [Environment]::NewLine +
    $caseIndent + '    Console.Error.WriteLine(' + [Environment]::NewLine +
    $caseIndent + '        "[BINK-NATIVE][V75.0.0] attach_failed " +' + [Environment]::NewLine +
    $caseIndent + '        $"file=''{Path.GetFileName(hostPath)}'' " +' + [Environment]::NewLine +
    $caseIndent + '        "fallback_external_rad=False");' + [Environment]::NewLine +
    $caseIndent + '    return;' + [Environment]::NewLine +
    [Environment]::NewLine

$radCaseAbsolute = $attach.Match.Index + $radCase.Index
$text = $text.Insert(
    $radCaseAbsolute,
    $nativeCase)

Write-Step "NativeRadSwitchCaseMethodBound=True"

# ---------------------------------------------------------------------------
# 3. Native attach method
# ---------------------------------------------------------------------------
$radMethodPattern =
    '(?ms)^[ \t]*private[ \t]+static[ \t]+bool[ \t]+AttachRadMovieLocked[ \t]*\([ \t\r\n]*string[ \t]+hostPath[ \t\r\n]*\)[ \t\r\n]*\{'

$radMethodMatch = [regex]::Match(
    $text,
    $radMethodPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $radMethodMatch.Success) {
    throw "$script:Tag Structural AttachRadMovieLocked declaration not found."
}

$radMethodLineStart = $text.LastIndexOf(
    [Environment]::NewLine,
    $radMethodMatch.Index,
    [StringComparison]::Ordinal)

if ($radMethodLineStart -lt 0) {
    $radMethodLineStart = 0
}
else {
    $radMethodLineStart += [Environment]::NewLine.Length
}

$radMethodIndentMatch = [regex]::Match(
    $text.Substring(
        $radMethodLineStart,
        $radMethodMatch.Index - $radMethodLineStart),
    '^[ \t]*$')

$methodIndent = if ($radMethodIndentMatch.Success) {
    $radMethodIndentMatch.Value
}
else {
    '    '
}

$nativeMethod = @'
    private static bool AttachRadNativeMovieLocked(
        string hostPath)
    {
        if (!RadBinkNativeSdkDecoderV7500.TryOpen(
                hostPath,
                out var source) ||
            source is null)
        {
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);

        if (!IsValid(info))
        {
            source.Dispose();
            return false;
        }

        // Demon's Souls attract_movie is video-only in Bink. Its AT9 stems
        // remain SharpEmu-owned and become MediaFramePlayback's master clock.
        if (string.Equals(
                Path.GetFileName(hostPath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            BinkHostAudioBridgeV7241.TryStart(
                hostPath);
        }

        AttachPlaybackLocked(
            hostPath,
            info,
            source);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.0] bridge_attached " +
            $"file='{Path.GetFileName(hostPath)}' " +
            $"size={info.Width}x{info.Height} " +
            $"fps={info.FramesPerSecondNumerator}/" +
            $"{info.FramesPerSecondDenominator} " +
            $"tracks={source.AudioTrackCount} " +
            $"embedded_audio_active={source.EmbeddedAudioActive} " +
            $"decoder=in-process-sdk " +
            $"dll='{RadBinkNativeSdkDecoderV7500.RuntimeLibraryPath}'");
        return true;
    }

'@

# Current SharpEmu source uses four-space member indentation. Preserve the
# source-derived indentation if it differs.
if ($methodIndent -ne '    ') {
    $nativeLines = $nativeMethod -split "`r?`n"
    for ($i = 0; $i -lt $nativeLines.Count; $i++) {
        if ($nativeLines[$i].StartsWith('    ')) {
            $nativeLines[$i] =
                $methodIndent +
                $nativeLines[$i].Substring(4)
        }
    }
    $nativeMethod = $nativeLines -join [Environment]::NewLine
}

$text = $text.Insert(
    $radMethodLineStart,
    $nativeMethod)

Write-Step "StructuralAttachRadMethodLocator=True"

# ---------------------------------------------------------------------------
# 4. ResolveMode: prepend V75 policy instead of replacing accumulated logic
# ---------------------------------------------------------------------------
# Do not rewrite the existing RAD branch. Existing branches may already carry
# title-specific policy from other patches. A V75 prefix handles only:
#   native-rad/rad-native/sdk-rad
#   external-rad
#   native preference for existing rad/binkplay/radvideo requests
# and otherwise falls through untouched.
$resolvePattern =
    '(?ms)^[ \t]*private[ \t]+static[ \t]+MovieMode[ \t]+ResolveMode[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$resolve = Find-MethodRegion `
    -Source $text `
    -Pattern $resolvePattern `
    -Name 'ResolveMode'

$resolvePrefix = @'

        var v7500Configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_MODE");

        if (string.Equals(
                v7500Configured,
                "native-rad",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                v7500Configured,
                "rad-native",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                v7500Configured,
                "sdk-rad",
                StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.NativeRad;
        }

        if (string.Equals(
                v7500Configured,
                "external-rad",
                StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Rad;
        }

        if ((string.Equals(
                 v7500Configured,
                 "rad",
                 StringComparison.OrdinalIgnoreCase) ||
             string.Equals(
                 v7500Configured,
                 "binkplay",
                 StringComparison.OrdinalIgnoreCase) ||
             string.Equals(
                 v7500Configured,
                 "radvideo",
                 StringComparison.OrdinalIgnoreCase)) &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_NATIVE_PREFER") != "0" &&
            RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable)
        {
            Console.Error.WriteLine(
                "[BINK-NATIVE][V75.0.0] auto_selected " +
                "requested=rad resolved=native-rad " +
                $"dll='{RadBinkNativeSdkDecoderV7500.RuntimeLibraryPath}'");
            return MovieMode.NativeRad;
        }
'@

$text = $text.Insert(
    $resolve.OpenBrace + 1,
    $resolvePrefix)

Write-Step "ResolveModePrefixPolicy=True"

# ---------------------------------------------------------------------------
# 5. MovieMode enum
# ---------------------------------------------------------------------------
$enumPattern =
    '(?ms)^[ \t]*private[ \t]+enum[ \t]+MovieMode[ \t\r\n]*\{'

$enumMatch = [regex]::Match(
    $text,
    $enumPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $enumMatch.Success) {
    throw "$script:Tag Structural MovieMode enum declaration not found."
}

$enumOpen = $text.IndexOf(
    '{',
    $enumMatch.Index,
    [StringComparison]::Ordinal)

$enumClose = Find-MatchingBraceIndex `
    -Text $text `
    -OpenBraceIndex $enumOpen

$enumRegion = $text.Substring(
    $enumOpen,
    $enumClose - $enumOpen + 1)

$nativeEnumPattern =
    '(?m)^(?<indent>[ \t]*)Native[ \t]*,'

$nativeEnumMatches = @(
    [regex]::Matches(
        $enumRegion,
        $nativeEnumPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
)

if ($nativeEnumMatches.Count -ne 1) {
    throw "$script:Tag Expected exactly one Native member in MovieMode enum; found $($nativeEnumMatches.Count)."
}

$nativeEnum = $nativeEnumMatches[0]
$enumIndent = $nativeEnum.Groups['indent'].Value
$enumInsertAbsolute =
    $enumOpen +
    $nativeEnum.Index +
    $nativeEnum.Length

$text = $text.Insert(
    $enumInsertAbsolute,
    [Environment]::NewLine +
    $enumIndent +
    'NativeRad,')

Write-Step "StructuralMovieModeEnumLocator=True"

foreach ($required in @(
    'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0',
    'MovieMode.NativeRad',
    'AttachRadNativeMovieLocked',
    'RadBinkNativeSdkDecoderV7500.TryOpen',
    'SHARPEMU_BINK_NATIVE_PREFER',
    'SHARPEMU_BINK_NATIVE_FALLBACK',
    '"native-rad"',
    '"external-rad"',
    '[BINK-NATIVE][V75.0.0] bridge_attached',
    'v7500Configured',
    'if (mode != MovieMode.NativeRad)'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "HostMovieBridge native-rad mode + external fallback installed."
