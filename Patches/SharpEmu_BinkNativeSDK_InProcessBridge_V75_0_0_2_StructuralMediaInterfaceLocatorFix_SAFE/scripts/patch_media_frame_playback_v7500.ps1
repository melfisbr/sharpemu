param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "MediaFramePlayback native clock/buffer policy already installed."
    exit 0
}

foreach ($required in @(
    'internal interface IMediaFrameDecoder : IDisposable',
    'internal sealed class MediaFramePlayback : IDisposable',
    'private const int BufferCount = 5;',
    'private readonly IMediaFrameDecoder _decoder;',
    '_decoder = decoder;',
    'decoder is not NihavBink2Decoder',
    'for (var index = 0; index < BufferCount; index++)',
    'if (decoder is NihavBink2Decoder && _freeBuffers.Count > 0)',
    'private double CurrentPlaybackSecondsLocked()'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag MediaFramePlayback baseline marker missing: $required"
    }
}

# Add the two SharpEmu-owned optional decoder contracts after IMediaFrameDecoder.
# V75.0.0.2: the accumulated source places the opening brace on the
# following line. Accept either one-line or multiline declaration formatting.
$ifacePattern =
    '(?ms)^[ \t]*internal[ \t]+interface[ \t]+IMediaFrameDecoder[ \t]*:[ \t]*IDisposable[ \t\r\n]*\{'

$ifaceMatch = [regex]::Match(
    $text,
    $ifacePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $ifaceMatch.Success) {
    throw "$script:Tag Structural IMediaFrameDecoder : IDisposable declaration not found."
}

$ifaceOpen = $text.IndexOf(
    '{',
    $ifaceMatch.Index,
    [StringComparison]::Ordinal)
$ifaceEnd = Find-MatchingBraceIndex -Text $text -OpenBraceIndex $ifaceOpen

$contracts = @'

// SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0
internal interface IMediaPlaybackClockSource
{
    bool TryGetPlaybackSeconds(out double seconds);
}

internal interface IMediaFrameBufferPolicy
{
    int PreferredBufferCount { get; }

    bool PrimeFirstFrameSynchronously { get; }
}
'@

$text = $text.Insert(
    $ifaceEnd + 1,
    [Environment]::NewLine +
    $contracts)

# Add fields.
$decoderField =
    '    private readonly IMediaFrameDecoder _decoder;'
$fieldIndex = $text.IndexOf(
    $decoderField,
    [StringComparison]::Ordinal)
if ($fieldIndex -lt 0) {
    throw "$script:Tag _decoder field anchor missing."
}

$fieldInsert = @'

    private readonly IMediaPlaybackClockSource? _playbackClockSource;
    private readonly IMediaFrameBufferPolicy? _bufferPolicy;
'@
$text = $text.Insert(
    $fieldIndex + $decoderField.Length,
    $fieldInsert)

# Constructor captures optional contracts.
$assign =
    '        _decoder = decoder;'
$assignIndex = $text.IndexOf(
    $assign,
    [StringComparison]::Ordinal)
if ($assignIndex -lt 0) {
    throw "$script:Tag constructor decoder assignment anchor missing."
}

$assignInsert = @'

        _playbackClockSource =
            decoder as IMediaPlaybackClockSource;
        _bufferPolicy =
            decoder as IMediaFrameBufferPolicy;
'@
$text = $text.Insert(
    $assignIndex + $assign.Length,
    $assignInsert)

# Native/SDK clock owns timing before guest AudioOut.
$followOld = @'
        _followGuestAudioClock =
            string.Equals(configuredClock, "audio", StringComparison.OrdinalIgnoreCase) ||
            (string.IsNullOrWhiteSpace(configuredClock) && decoder is not NihavBink2Decoder);
'@

$followNew = @'
        _followGuestAudioClock =
            _playbackClockSource is null &&
            (string.Equals(
                 configuredClock,
                 "audio",
                 StringComparison.OrdinalIgnoreCase) ||
             (string.IsNullOrWhiteSpace(configuredClock) &&
              decoder is not NihavBink2Decoder));
'@

if ($text.IndexOf(
        $followOld,
        [StringComparison]::Ordinal) -lt 0) {
    throw "$script:Tag guest-audio clock assignment block missing."
}
$text = $text.Replace(
    $followOld,
    $followNew)

# Bounded buffer count.
$bufferLoop =
    '        for (var index = 0; index < BufferCount; index++)'
$bufferIndex = $text.IndexOf(
    $bufferLoop,
    [StringComparison]::Ordinal)
if ($bufferIndex -lt 0) {
    throw "$script:Tag BufferCount allocation loop missing."
}

$bufferReplacement = @'
        var bufferCount = Math.Clamp(
            _bufferPolicy?.PreferredBufferCount ?? BufferCount,
            2,
            8);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.0] playback_buffers " +
            $"decoder={decoder.GetType().Name} count={bufferCount}");

        for (var index = 0; index < bufferCount; index++)
'@
$text = $text.Replace(
    $bufferLoop,
    $bufferReplacement)

# Prime native first frame just like NIHAV.
$primeOld =
    '        if (decoder is NihavBink2Decoder && _freeBuffers.Count > 0)'
$primeNew = @'
        if ((decoder is NihavBink2Decoder ||
             _bufferPolicy?.PrimeFirstFrameSynchronously == true) &&
            _freeBuffers.Count > 0)
'@
if ($text.IndexOf(
        $primeOld,
        [StringComparison]::Ordinal) -lt 0) {
    throw "$script:Tag first-frame prime condition missing."
}
$text = $text.Replace(
    $primeOld,
    $primeNew)

# PlaybackProgress should expose the authoritative playback clock.
$progressOld = @'
                    _playbackClockStarted
                        ? Stopwatch.GetElapsedTime(_playbackStartTimestamp).TotalSeconds
                        : 0,
'@
$progressNew = @'
                    _playbackClockStarted
                        ? CurrentPlaybackSecondsLocked()
                        : 0,
'@
if ($text.IndexOf(
        $progressOld,
        [StringComparison]::Ordinal) -lt 0) {
    throw "$script:Tag PlaybackProgress clock expression missing."
}
$text = $text.Replace(
    $progressOld,
    $progressNew)

# Insert native clock before wall/guest fallback.
# CurrentPlaybackSecondsLocked uses the same brace-on-next-line style in
# the real source. Keep this locator formatting-independent as well.
$currentPattern =
    '(?ms)^[ \t]*private[ \t]+double[ \t]+CurrentPlaybackSecondsLocked[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$currentMatch = [regex]::Match(
    $text,
    $currentPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
if (-not $currentMatch.Success) {
    throw "$script:Tag Structural CurrentPlaybackSecondsLocked() declaration missing."
}

$currentOpen = $text.IndexOf(
    '{',
    $currentMatch.Index,
    [StringComparison]::Ordinal)
$currentEnd = Find-MatchingBraceIndex -Text $text -OpenBraceIndex $currentOpen
$currentRegion = $text.Substring(
    $currentMatch.Index,
    $currentEnd - $currentMatch.Index + 1)

$clockAnchor = @'
        if (!_playbackClockStarted)
        {
            return 0;
        }
'@
$clockRelative = $currentRegion.IndexOf(
    $clockAnchor,
    [StringComparison]::Ordinal)
if ($clockRelative -lt 0) {
    throw "$script:Tag CurrentPlaybackSecondsLocked startup guard missing."
}

$clockAbsolute =
    $currentMatch.Index +
    $clockRelative +
    $clockAnchor.Length

$clockInsert = @'

        if (_playbackClockSource is not null &&
            _playbackClockSource.TryGetPlaybackSeconds(
                out var sourceSeconds) &&
            double.IsFinite(sourceSeconds) &&
            sourceSeconds >= 0)
        {
            return sourceSeconds;
        }
'@
$text = $text.Insert(
    $clockAbsolute,
    $clockInsert)

foreach ($required in @(
    'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0',
    'IMediaPlaybackClockSource',
    'IMediaFrameBufferPolicy',
    '_playbackClockSource',
    'PrimeFirstFrameSynchronously',
    '[BINK-NATIVE][V75.0.0] playback_buffers'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag MediaFramePlayback post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "MediaFramePlayback native clock + bounded-buffer policy installed."
