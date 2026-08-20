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
# V75.0.0.3: locate the assignment structurally. Do not compare an entire
# multiline C# block byte-for-byte because CRLF/LF differences are irrelevant.
$followPattern =
    '(?ms)^(?<indent>[ \t]*)_followGuestAudioClock[ \t]*=[ \t\r\n]*' +
    'string\.Equals[ \t]*\([ \t]*configuredClock[ \t]*,[ \t]*"audio"[ \t]*,[ \t]*StringComparison\.OrdinalIgnoreCase[ \t]*\)[ \t]*\|\|[ \t\r\n]*' +
    '\([ \t]*string\.IsNullOrWhiteSpace[ \t]*\([ \t]*configuredClock[ \t]*\)[ \t]*&&[ \t]*decoder[ \t]+is[ \t]+not[ \t]+NihavBink2Decoder[ \t]*\)[ \t]*;'

$followMatch = [regex]::Match(
    $text,
    $followPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $followMatch.Success) {
    throw "$script:Tag Structural guest-audio clock assignment not found."
}

$followIndent = $followMatch.Groups['indent'].Value
$followNew =
    $followIndent + '_followGuestAudioClock =' + [Environment]::NewLine +
    $followIndent + '    _playbackClockSource is null &&' + [Environment]::NewLine +
    $followIndent + '    (string.Equals(' + [Environment]::NewLine +
    $followIndent + '         configuredClock,' + [Environment]::NewLine +
    $followIndent + '         "audio",' + [Environment]::NewLine +
    $followIndent + '         StringComparison.OrdinalIgnoreCase) ||' + [Environment]::NewLine +
    $followIndent + '     (string.IsNullOrWhiteSpace(configuredClock) &&' + [Environment]::NewLine +
    $followIndent + '      decoder is not NihavBink2Decoder));'

$text = $text.Remove(
    $followMatch.Index,
    $followMatch.Length)
$text = $text.Insert(
    $followMatch.Index,
    $followNew)

# Bounded buffer count.
$bufferLoopPattern =
    '(?m)^(?<indent>[ \t]*)for[ \t]*\([ \t]*var[ \t]+index[ \t]*=[ \t]*0[ \t]*;[ \t]*index[ \t]*<[ \t]*BufferCount[ \t]*;[ \t]*index\+\+[ \t]*\)'

$bufferLoopMatch = [regex]::Match(
    $text,
    $bufferLoopPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $bufferLoopMatch.Success) {
    throw "$script:Tag Structural BufferCount allocation loop not found."
}

$bufferIndent = $bufferLoopMatch.Groups['indent'].Value
$bufferReplacement =
    $bufferIndent + 'var bufferCount = Math.Clamp(' + [Environment]::NewLine +
    $bufferIndent + '    _bufferPolicy?.PreferredBufferCount ?? BufferCount,' + [Environment]::NewLine +
    $bufferIndent + '    2,' + [Environment]::NewLine +
    $bufferIndent + '    8);' + [Environment]::NewLine +
    [Environment]::NewLine +
    $bufferIndent + 'Console.Error.WriteLine(' + [Environment]::NewLine +
    $bufferIndent + '    "[BINK-NATIVE][V75.0.0] playback_buffers " +' + [Environment]::NewLine +
    $bufferIndent + '    $"decoder={decoder.GetType().Name} count={bufferCount}");' + [Environment]::NewLine +
    [Environment]::NewLine +
    $bufferIndent + 'for (var index = 0; index < bufferCount; index++)'

$text = $text.Remove(
    $bufferLoopMatch.Index,
    $bufferLoopMatch.Length)
$text = $text.Insert(
    $bufferLoopMatch.Index,
    $bufferReplacement)

# Prime native first frame just like NIHAV.
$primePattern =
    '(?m)^(?<indent>[ \t]*)if[ \t]*\([ \t]*decoder[ \t]+is[ \t]+NihavBink2Decoder[ \t]*&&[ \t]*_freeBuffers\.Count[ \t]*>[ \t]*0[ \t]*\)'

$primeMatch = [regex]::Match(
    $text,
    $primePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $primeMatch.Success) {
    throw "$script:Tag Structural first-frame prime condition not found."
}

$primeIndent = $primeMatch.Groups['indent'].Value
$primeNew =
    $primeIndent + 'if ((decoder is NihavBink2Decoder ||' + [Environment]::NewLine +
    $primeIndent + '     _bufferPolicy?.PrimeFirstFrameSynchronously == true) &&' + [Environment]::NewLine +
    $primeIndent + '    _freeBuffers.Count > 0)'

$text = $text.Remove(
    $primeMatch.Index,
    $primeMatch.Length)
$text = $text.Insert(
    $primeMatch.Index,
    $primeNew)

# PlaybackProgress should expose the authoritative playback clock.
$progressPattern =
    '(?ms)^(?<indent>[ \t]*)_playbackClockStarted[ \t\r\n]*\?[ \t]*Stopwatch\.GetElapsedTime[ \t]*\([ \t]*_playbackStartTimestamp[ \t]*\)\.TotalSeconds[ \t\r\n]*:[ \t]*0[ \t]*,'

$progressMatch = [regex]::Match(
    $text,
    $progressPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $progressMatch.Success) {
    throw "$script:Tag Structural PlaybackProgress clock expression not found."
}

$progressIndent = $progressMatch.Groups['indent'].Value
$progressNew =
    $progressIndent + '_playbackClockStarted' + [Environment]::NewLine +
    $progressIndent + '    ? CurrentPlaybackSecondsLocked()' + [Environment]::NewLine +
    $progressIndent + '    : 0,'

$text = $text.Remove(
    $progressMatch.Index,
    $progressMatch.Length)
$text = $text.Insert(
    $progressMatch.Index,
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

$clockGuardPattern =
    '(?ms)^(?<indent>[ \t]*)if[ \t]*\([ \t]*!_playbackClockStarted[ \t]*\)[ \t\r\n]*\{[ \t\r\n]*return[ \t]+0[ \t]*;[ \t\r\n]*\}'

$clockGuardMatch = [regex]::Match(
    $currentRegion,
    $clockGuardPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $clockGuardMatch.Success) {
    throw "$script:Tag Structural CurrentPlaybackSecondsLocked startup guard not found."
}

$clockAbsolute =
    $currentMatch.Index +
    $clockGuardMatch.Index +
    $clockGuardMatch.Length

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
