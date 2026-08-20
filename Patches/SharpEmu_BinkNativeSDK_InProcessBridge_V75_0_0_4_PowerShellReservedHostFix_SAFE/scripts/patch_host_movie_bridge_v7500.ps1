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
    'private static void AttachMovieLocked(string hostPath, MovieMode mode)',
    'private static bool AttachRadMovieLocked(string hostPath)',
    'private static MovieMode ResolveMode()',
    'private enum MovieMode',
    'case MovieMode.Rad:',
    'BinkHostAudioBridgeV7241.TryStart(hostPath);',
    'return MovieMode.Rad;'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge baseline marker missing: $required"
    }
}

# Native RAD owns embedded Bink audio. Only the Demon's Souls attract zero-track
# movie keeps the existing external AT9 sidecar, started after native open.
$audioPattern =
    '(?ms)(?<indent>^[ \t]*)if[ \t]*\([ \t]*mode[ \t]*!=[ \t]*MovieMode\.Rad[ \t]*\)[ \t\r\n]*\{[ \t\r\n]*BinkHostAudioBridgeV7241\.TryStart\(hostPath\);[ \t\r\n]*\}'

$audioMatch = [regex]::Match(
    $text,
    $audioPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
if (-not $audioMatch.Success) {
    throw "$script:Tag Host audio mode gate not found."
}

$indent = $audioMatch.Groups['indent'].Value
$audioReplacement =
    $indent + 'if (mode != MovieMode.Rad &&' + [Environment]::NewLine +
    $indent + '    mode != MovieMode.NativeRad)' + [Environment]::NewLine +
    $indent + '{' + [Environment]::NewLine +
    $indent + '    BinkHostAudioBridgeV7241.TryStart(hostPath);' + [Environment]::NewLine +
    $indent + '}'

$text = $text.Remove(
    $audioMatch.Index,
    $audioMatch.Length)
$text = $text.Insert(
    $audioMatch.Index,
    $audioReplacement)

# Add switch case before external RAD.
$radCasePattern =
    '(?m)^(?<indent>[ \t]*)case[ \t]+MovieMode\.Rad:'
$radCaseMatch = [regex]::Match(
    $text,
    $radCasePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
if (-not $radCaseMatch.Success) {
    throw "$script:Tag MovieMode.Rad switch case not found."
}

$caseIndent = $radCaseMatch.Groups['indent'].Value
$nativeCase = @'
            // SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0
            case MovieMode.NativeRad:
                if (AttachRadNativeMovieLocked(hostPath))
                {
                    return;
                }

                if (Environment.GetEnvironmentVariable(
                        "SHARPEMU_BINK_NATIVE_FALLBACK") != "0" &&
                    AttachRadMovieLocked(hostPath))
                {
                    Console.Error.WriteLine(
                        "[BINK-NATIVE][V75.0.0] fallback_external_rad " +
                        $"file='{Path.GetFileName(hostPath)}'");
                    return;
                }

                Console.Error.WriteLine(
                    "[BINK-NATIVE][V75.0.0] attach_failed " +
                    $"file='{Path.GetFileName(hostPath)}' " +
                    "fallback_external_rad=False");
                return;

'@
$text = $text.Insert(
    $radCaseMatch.Index,
    $nativeCase)

# Add native attach method before external RAD method.
$radMethod =
    '    private static bool AttachRadMovieLocked(string hostPath)'
$radMethodIndex = $text.IndexOf(
    $radMethod,
    [StringComparison]::Ordinal)
if ($radMethodIndex -lt 0) {
    throw "$script:Tag AttachRadMovieLocked method anchor missing."
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
$text = $text.Insert(
    $radMethodIndex,
    $nativeMethod)

# Replace the existing configured RAD branch with native-preference logic.
$resolvePattern =
    '(?ms)^[ \t]*if[ \t]*\([ \t]*string\.Equals\(configured,[ \t]*"rad",[ \t]*StringComparison\.OrdinalIgnoreCase\)[ \t]*\|\|[ \t\r\n]*string\.Equals\(configured,[ \t]*"binkplay",[ \t]*StringComparison\.OrdinalIgnoreCase\)[ \t]*\|\|[ \t\r\n]*string\.Equals\(configured,[ \t]*"radvideo",[ \t]*StringComparison\.OrdinalIgnoreCase\)[ \t]*\)[ \t\r\n]*\{[ \t\r\n]*return[ \t]+MovieMode\.Rad;[ \t\r\n]*\}'

$resolveMatch = [regex]::Match(
    $text,
    $resolvePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
if (-not $resolveMatch.Success) {
    throw "$script:Tag Existing configured RAD ResolveMode block not found."
}

$resolveReplacement = @'
        if (string.Equals(
                configured,
                "native-rad",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                configured,
                "rad-native",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                configured,
                "sdk-rad",
                StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.NativeRad;
        }

        if (string.Equals(
                configured,
                "external-rad",
                StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Rad;
        }

        if (string.Equals(configured, "rad", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "binkplay", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "radvideo", StringComparison.OrdinalIgnoreCase))
        {
            if (Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_NATIVE_PREFER") != "0" &&
                RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable)
            {
                Console.Error.WriteLine(
                    "[BINK-NATIVE][V75.0.0] auto_selected " +
                    "requested=rad resolved=native-rad " +
                    $"dll='{RadBinkNativeSdkDecoderV7500.RuntimeLibraryPath}'");
                return MovieMode.NativeRad;
            }

            return MovieMode.Rad;
        }
'@

$text = $text.Remove(
    $resolveMatch.Index,
    $resolveMatch.Length)
$text = $text.Insert(
    $resolveMatch.Index,
    $resolveReplacement)

# Enum.
$enumAnchor =
    '        Native,'
$enumIndex = $text.IndexOf(
    $enumAnchor,
    [StringComparison]::Ordinal)
if ($enumIndex -lt 0) {
    throw "$script:Tag MovieMode.Native enum member missing."
}

$text = $text.Insert(
    $enumIndex + $enumAnchor.Length,
    [Environment]::NewLine +
    '        NativeRad,')

foreach ($required in @(
    'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0',
    'MovieMode.NativeRad',
    'AttachRadNativeMovieLocked',
    'RadBinkNativeSdkDecoderV7500.TryOpen',
    'SHARPEMU_BINK_NATIVE_PREFER',
    'SHARPEMU_BINK_NATIVE_FALLBACK',
    '"native-rad"',
    '"external-rad"',
    '[BINK-NATIVE][V75.0.0] bridge_attached'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag HostMovieBridge post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "HostMovieBridge native-rad mode + external fallback installed."
