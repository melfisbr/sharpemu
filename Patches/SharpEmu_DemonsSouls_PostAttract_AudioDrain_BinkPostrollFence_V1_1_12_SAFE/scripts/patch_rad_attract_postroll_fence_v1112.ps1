param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "RAD attract postroll fence already installed."
    exit 0
}

foreach ($required in @(
    'internal sealed class RadBinkEmbeddedHostApiV724323171',
    'private readonly Timer _resizeTimer;',
    'private readonly Timer _visualCutoffTimer;',
    'private readonly Timer _nominalEndTimer;',
    'private void SyncBounds()',
    'private void CutVisualBeforePostroll()',
    'private void EndAtNominalMovieBoundary()',
    'ShowWindow(PlayerWindow, SwHide)',
    'GetWindowThreadProcessId',
    'EnumWindows',
    'nominalDurationMilliseconds'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag RAD baseline marker missing: $required"
    }
}

# Fields: insert after nominal-end timer. This is stable across prior audio
# release patches because those modify TryAttach/reveal, not lifecycle fields.
$fieldAnchor = '    private readonly Timer _nominalEndTimer;'
$fieldIndex = $text.IndexOf(
    $fieldAnchor,
    [StringComparison]::Ordinal)

if ($fieldIndex -lt 0) {
    throw "$script:Tag RAD nominal-end timer field anchor missing."
}

$fieldInsertAt = $fieldIndex + $fieldAnchor.Length

$fields = @'

    // SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12
    private readonly Timer _v1112PostrollFenceTimer;
    private readonly string _v1112MoviePath;
    private readonly bool _v1112IsAttractMovie;
    private readonly int _v1112PostrollFenceDurationMilliseconds;
    private long _v1112PostrollFenceUntilTick;
    private int _v1112PostrollFenceActive;
'@

$text = $text.Insert(
    $fieldInsertAt,
    $fields)

# Constructor: add moviePath before nominal duration.
$ctorPattern =
    '(?ms)^[ \t]*private[ \t]+RadBinkEmbeddedHostApiV724323171[ \t]*\([ \t\r\n]*Process[ \t]+launcherProcess[ \t]*,[\s\S]*?double[ \t]+playbackAnchorMilliseconds[ \t]*,[ \t\r\n]*double[ \t]+nominalDurationMilliseconds[ \t\r\n]*\)[ \t\r\n]*\{'

$ctorRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $ctorPattern `
    -Name 'RadBinkEmbeddedHostApiV724323171 constructor'

$ctorText = $text.Substring(
    $ctorRegion.Match.Index,
    $ctorRegion.OpenBrace - $ctorRegion.Match.Index)

$durationSignature =
    'double playbackAnchorMilliseconds,' +
    [Environment]::NewLine +
    '        double nominalDurationMilliseconds)'

if ($ctorText.IndexOf(
        $durationSignature,
        [StringComparison]::Ordinal) -lt 0)
{
    # Formatting-independent fallback.
    $durationSigPattern =
        'double[ \t]+playbackAnchorMilliseconds[ \t]*,[ \t\r\n]*double[ \t]+nominalDurationMilliseconds[ \t]*\)'

    $sigMatch = [regex]::Match(
        $ctorText,
        $durationSigPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    if (-not $sigMatch.Success) {
        throw "$script:Tag RAD constructor duration signature not found."
    }

    $sigReplacement =
        'double playbackAnchorMilliseconds,' + [Environment]::NewLine +
        '        string moviePath,' + [Environment]::NewLine +
        '        double nominalDurationMilliseconds)'

    $ctorAbsolute =
        $ctorRegion.Match.Index +
        $sigMatch.Index

    $text = $text.Remove(
        $ctorAbsolute,
        $sigMatch.Length)

    $text = $text.Insert(
        $ctorAbsolute,
        $sigReplacement)
}
else {
    $text = $text.Replace(
        $durationSignature,
        'double playbackAnchorMilliseconds,' +
        [Environment]::NewLine +
        '        string moviePath,' +
        [Environment]::NewLine +
        '        double nominalDurationMilliseconds)')
}

# Re-resolve constructor after signature change.
$ctorRegion = Find-MethodRegion `
    -Text $text `
    -Pattern (
        '(?ms)^[ \t]*private[ \t]+RadBinkEmbeddedHostApiV724323171[ \t]*\([ \t\r\n]*Process[ \t]+launcherProcess[ \t]*,[\s\S]*?string[ \t]+moviePath[ \t]*,[ \t\r\n]*double[ \t]+nominalDurationMilliseconds[ \t\r\n]*\)[ \t\r\n]*\{'
    ) `
    -Name 'RadBinkEmbeddedHostApiV724323171 constructor V1.1.12'

# Assign movie identity immediately after nominal duration assignment.
$ctorCurrent = $text.Substring(
    $ctorRegion.OpenBrace,
    $ctorRegion.CloseBrace - $ctorRegion.OpenBrace + 1)

$durationAssignPattern =
    '(?m)^(?<indent>[ \t]*)_nominalDurationMilliseconds[ \t]*=[ \t]*nominalDurationMilliseconds[ \t]*;'

$durationAssign = [regex]::Match(
    $ctorCurrent,
    $durationAssignPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $durationAssign.Success) {
    throw "$script:Tag RAD constructor nominal duration assignment missing."
}

$assignIndent = $durationAssign.Groups['indent'].Value
$identity = [Environment]::NewLine +
    $assignIndent + '_v1112MoviePath = moviePath;' + [Environment]::NewLine +
    $assignIndent + '_v1112IsAttractMovie =' + [Environment]::NewLine +
    $assignIndent + '    string.Equals(' + [Environment]::NewLine +
    $assignIndent + '        Path.GetFileName(moviePath),' + [Environment]::NewLine +
    $assignIndent + '        "attract_movie.bk2",' + [Environment]::NewLine +
    $assignIndent + '        StringComparison.OrdinalIgnoreCase);'

$durationAbsolute =
    $ctorRegion.OpenBrace +
    $durationAssign.Index +
    $durationAssign.Length

$text = $text.Insert(
    $durationAbsolute,
    $identity)

# Replace the existing visual cutoff lead assignment with attract-specific,
# conservative early fence timing. Other movies retain existing behavior.
$leadPattern =
    '(?ms)^[ \t]*_visualCutoffLeadMilliseconds[ \t]*=[ \t]*ResolveIntEnvironment[ \t]*\([ \t\r\n]*"SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS"[ \t]*,[ \t\r\n]*defaultValue:[ \t]*120[ \t]*,[ \t\r\n]*minimum:[ \t]*0[ \t]*,[ \t\r\n]*maximum:[ \t]*750[ \t]*\)[ \t]*;'

$leadMatch = [regex]::Match(
    $text,
    $leadPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $leadMatch.Success) {
    throw "$script:Tag RAD visual cutoff lead assignment not found."
}

$leadIndent = [regex]::Match(
    $leadMatch.Value,
    '^[ \t]*').Value

$leadReplacement =
    $leadIndent + '_visualCutoffLeadMilliseconds = _v1112IsAttractMovie' + [Environment]::NewLine +
    $leadIndent + '    ? ResolveIntEnvironment(' + [Environment]::NewLine +
    $leadIndent + '        "SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_LEAD_MS",' + [Environment]::NewLine +
    $leadIndent + '        defaultValue: 350,' + [Environment]::NewLine +
    $leadIndent + '        minimum: 120,' + [Environment]::NewLine +
    $leadIndent + '        maximum: 1_500)' + [Environment]::NewLine +
    $leadIndent + '    : ResolveIntEnvironment(' + [Environment]::NewLine +
    $leadIndent + '        "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",' + [Environment]::NewLine +
    $leadIndent + '        defaultValue: 120,' + [Environment]::NewLine +
    $leadIndent + '        minimum: 0,' + [Environment]::NewLine +
    $leadIndent + '        maximum: 750);' + [Environment]::NewLine +
    $leadIndent + '_v1112PostrollFenceDurationMilliseconds =' + [Environment]::NewLine +
    $leadIndent + '    ResolveIntEnvironment(' + [Environment]::NewLine +
    $leadIndent + '        "SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_MS",' + [Environment]::NewLine +
    $leadIndent + '        defaultValue: 1_200,' + [Environment]::NewLine +
    $leadIndent + '        minimum: 250,' + [Environment]::NewLine +
    $leadIndent + '        maximum: 3_000);'

$text = $text.Remove(
    $leadMatch.Index,
    $leadMatch.Length)
$text = $text.Insert(
    $leadMatch.Index,
    $leadReplacement)

# Create tight fence timer just before visualCutoffDue calculation.
$visualDueAnchor = '        var visualCutoffDue = nominalDurationMilliseconds > 0'
$visualDueIndex = $text.IndexOf(
    $visualDueAnchor,
    [StringComparison]::Ordinal)

if ($visualDueIndex -lt 0) {
    throw "$script:Tag RAD visualCutoffDue anchor missing."
}

$fenceTimer = @'
        _v1112PostrollFenceTimer = new Timer(
            static state =>
            {
                if (state is RadBinkEmbeddedHostApiV724323171 host)
                {
                    host.EnforceAttractPostrollHiddenV1112();
                }
            },
            this,
            dueTime: Timeout.Infinite,
            period: Timeout.Infinite);

'@

$text = $text.Insert(
    $visualDueIndex,
    $fenceTimer)

# Constructor call: add moviePath before nominal duration.
$callPattern =
    '(?ms)new[ \t]+RadBinkEmbeddedHostApiV724323171[ \t]*\([ \t\r\n]*launcherProcess[ \t]*,[ \t\r\n]*rendererProcess[ \t]*,[ \t\r\n]*hostWindow[ \t]*,[ \t\r\n]*playerWindow[ \t]*,[ \t\r\n]*windowReadyMs[ \t]*,[ \t\r\n]*anchorMs[ \t]*,[ \t\r\n]*nominalDurationMilliseconds[ \t\r\n]*\)'

$callMatch = [regex]::Match(
    $text,
    $callPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $callMatch.Success) {
    throw "$script:Tag RAD constructor call not found."
}

$callReplacement = @'
new RadBinkEmbeddedHostApiV724323171(
            launcherProcess,
            rendererProcess,
            hostWindow,
            playerWindow,
            windowReadyMs,
            anchorMs,
            moviePath,
            nominalDurationMilliseconds)
'@

$text = $text.Remove(
    $callMatch.Index,
    $callMatch.Length)
$text = $text.Insert(
    $callMatch.Index,
    $callReplacement)

# SyncBounds: while the attract fence is active, never resize or otherwise
# touch the renderer as visible content. Re-hide all renderer windows instead.
$syncPattern =
    '(?ms)^[ \t]*private[ \t]+void[ \t]+SyncBounds[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$syncRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $syncPattern `
    -Name 'SyncBounds'

$syncGuard = @'

        if (Volatile.Read(
                ref _v1112PostrollFenceActive) != 0)
        {
            EnforceAttractPostrollHiddenV1112();
            return;
        }
'@

$text = $text.Insert(
    $syncRegion.OpenBrace + 1,
    $syncGuard)

# Add fence helpers before CutVisualBeforePostroll.
$cutPattern =
    '(?ms)^[ \t]*private[ \t]+void[ \t]+CutVisualBeforePostroll[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$cutRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $cutPattern `
    -Name 'CutVisualBeforePostroll'

$helpers = @'
    private void ArmAttractPostrollFenceV1112()
    {
        if (!_v1112IsAttractMovie ||
            _disposed ||
            SafeHasExited(_rendererProcess))
        {
            return;
        }

        var untilTick =
            checked(
                Environment.TickCount64 +
                _v1112PostrollFenceDurationMilliseconds);

        Volatile.Write(
            ref _v1112PostrollFenceUntilTick,
            untilTick);

        Interlocked.Exchange(
            ref _v1112PostrollFenceActive,
            1);

        EnforceAttractPostrollHiddenV1112();

        try
        {
            _ = _v1112PostrollFenceTimer.Change(
                dueTime: 0,
                period: 10);
        }
        catch (ObjectDisposedException)
        {
        }

        Console.Error.WriteLine(
            "[BINK-POSTROLL][V1.1.12] fence_armed " +
            "file='attract_movie.bk2' " +
            $"renderer_pid={RendererProcessId} " +
            $"lead_ms={_visualCutoffLeadMilliseconds} " +
            $"fence_ms={_v1112PostrollFenceDurationMilliseconds} " +
            $"until_tick={untilTick} rehide_period_ms=10");
    }

    private void EnforceAttractPostrollHiddenV1112()
    {
        if (_disposed ||
            Volatile.Read(
                ref _v1112PostrollFenceActive) == 0)
        {
            return;
        }

        var untilTick =
            Volatile.Read(
                ref _v1112PostrollFenceUntilTick);

        if (untilTick > 0 &&
            Environment.TickCount64 > untilTick)
        {
            Interlocked.Exchange(
                ref _v1112PostrollFenceActive,
                0);

            try
            {
                _ = _v1112PostrollFenceTimer.Change(
                    Timeout.Infinite,
                    Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
            }

            return;
        }

        if (PlayerWindow != 0 &&
            IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
        }

        // RAD/BinkPlay may create or re-show a top-level post-roll HWND after
        // the embedded child was hidden. Hide every window still owned by this
        // renderer PID. Never inspect titles and never touch SharpEmu's HWND.
        _ = EnumWindows(
            (window, ignored) =>
            {
                _ = GetWindowThreadProcessId(
                    window,
                    out var pid);

                if (pid == RendererProcessId)
                {
                    _ = ShowWindow(
                        window,
                        SwHide);
                }

                return true;
            },
            0);
    }

'@

$text = $text.Insert(
    $cutRegion.Match.Index,
    $helpers)

# Re-resolve CutVisual after helper insertion.
$cutRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $cutPattern `
    -Name 'CutVisualBeforePostroll'

$cutCurrent = $text.Substring(
    $cutRegion.OpenBrace,
    $cutRegion.CloseBrace - $cutRegion.OpenBrace + 1)

$hidePattern =
    '(?ms)if[ \t]*\([ \t]*PlayerWindow[ \t]*!=[ \t]*0[ \t]*&&[ \t\r\n]*IsWindow[ \t]*\([ \t]*PlayerWindow[ \t]*\)[ \t]*\)[ \t\r\n]*\{[ \t\r\n]*_[ \t]*=[ \t]*ShowWindow[ \t]*\([ \t]*PlayerWindow[ \t]*,[ \t]*SwHide[ \t]*\)[ \t]*;[ \t\r\n]*\}'

$hideMatch = [regex]::Match(
    $cutCurrent,
    $hidePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $hideMatch.Success) {
    throw "$script:Tag RAD CutVisual one-shot hide block not found."
}

$hideReplacement = @'
if (_v1112IsAttractMovie)
        {
            ArmAttractPostrollFenceV1112();
        }
        else if (PlayerWindow != 0 &&
                 IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
        }
'@

$hideAbsolute =
    $cutRegion.OpenBrace +
    $hideMatch.Index

$text = $text.Remove(
    $hideAbsolute,
    $hideMatch.Length)
$text = $text.Insert(
    $hideAbsolute,
    $hideReplacement)

# Natural end: stop attract audio exactly at the RAD nominal boundary before
# killing the renderer, and keep every RAD-owned HWND hidden.
$endPattern =
    '(?ms)^[ \t]*private[ \t]+void[ \t]+EndAtNominalMovieBoundary[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$endRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $endPattern `
    -Name 'EndAtNominalMovieBoundary'

$endCurrent = $text.Substring(
    $endRegion.OpenBrace,
    $endRegion.CloseBrace - $endRegion.OpenBrace + 1)

$endHide = [regex]::Match(
    $endCurrent,
    $hidePattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $endHide.Success) {
    throw "$script:Tag RAD nominal-end hide block not found."
}

$endReplacement = @'
if (_v1112IsAttractMovie)
        {
            Interlocked.Exchange(
                ref _v1112PostrollFenceActive,
                1);

            Volatile.Write(
                ref _v1112PostrollFenceUntilTick,
                checked(
                    Environment.TickCount64 +
                    _v1112PostrollFenceDurationMilliseconds));

            EnforceAttractPostrollHiddenV1112();

            BinkDemonSoulsIntroAudioV7243227.StopForMovie(
                _v1112MoviePath);

            try
            {
                _ = _v1112PostrollFenceTimer.Change(
                    Timeout.Infinite,
                    Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
            }

            Console.Error.WriteLine(
                "[BINK-POSTROLL][V1.1.12] attract_nominal_end " +
                "file='attract_movie.bk2' " +
                $"renderer_pid={RendererProcessId} " +
                "audio_stopped=True postroll_hidden=True " +
                "guest_drain_armed=True");
        }
        else if (PlayerWindow != 0 &&
                 IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
        }
'@

$endHideAbsolute =
    $endRegion.OpenBrace +
    $endHide.Index

$text = $text.Remove(
    $endHideAbsolute,
    $endHide.Length)
$text = $text.Insert(
    $endHideAbsolute,
    $endReplacement)

# Dispose fence timer along with other lifecycle timers.
$disposePattern =
    '(?ms)^[ \t]*public[ \t]+void[ \t]+Dispose[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$disposeRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $disposePattern `
    -Name 'Dispose'

$disposeCurrent = $text.Substring(
    $disposeRegion.OpenBrace,
    $disposeRegion.CloseBrace - $disposeRegion.OpenBrace + 1)

$nominalDispose =
    '_nominalEndTimer.Dispose();'

$nominalDisposeRelative = $disposeCurrent.IndexOf(
    $nominalDispose,
    [StringComparison]::Ordinal)

if ($nominalDisposeRelative -lt 0) {
    throw "$script:Tag RAD Dispose nominal-end timer cleanup missing."
}

$nominalDisposeAbsolute =
    $disposeRegion.OpenBrace +
    $nominalDisposeRelative +
    $nominalDispose.Length

$text = $text.Insert(
    $nominalDisposeAbsolute,
    [Environment]::NewLine +
    '        _v1112PostrollFenceTimer.Dispose();')

foreach ($required in @(
    'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12',
    '_v1112MoviePath',
    '_v1112PostrollFenceTimer',
    'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_LEAD_MS',
    'SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_MS',
    'ArmAttractPostrollFenceV1112',
    'EnforceAttractPostrollHiddenV1112',
    '[BINK-POSTROLL][V1.1.12] fence_armed',
    '[BINK-POSTROLL][V1.1.12] attract_nominal_end',
    'BinkDemonSoulsIntroAudioV7243227.StopForMovie',
    'rehide_period_ms=10',
    'moviePath,' + [Environment]::NewLine + '            nominalDurationMilliseconds'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag RAD post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "RAD attract persistent postroll hide fence + nominal audio stop installed."
