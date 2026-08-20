param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "Post-attract audio transition fence already installed."
    exit 0
}

foreach ($required in @(
    'internal static class BinkDemonSoulsIntroAudioV7243227',
    'SHARPEMU_DEMONS_STARTUP_GUEST_AUDIO_OWNERSHIP_V1_1_6',
    'IsStartupGuestAudioMuteActiveV116',
    'ReleaseStartupGuestAudioMuteV116',
    'public static AttachDisposition PrepareAttach',
    'public static void StopForMovie',
    'BinkDeterministicWavePlayerV317152.Stop()',
    '"attract_movie.bk2"'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Intro-audio baseline marker missing: $required"
    }
}

$mutePattern =
    '(?ms)^[ \t]*internal[ \t]+static[ \t]+bool[ \t]+IsStartupGuestAudioMuteActiveV116[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$muteRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $mutePattern `
    -Name 'IsStartupGuestAudioMuteActiveV116'

$helperBlock = @'
    // SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12
    //
    // The startup owner latch intentionally keeps guest AudioOut/AudioOut2
    // alive while RAD/the attract WaveOut owns host sound. Attract teardown
    // used to clear that latch immediately, making guest PCM that accumulated
    // during the movie audible on the first title frames.
    //
    // Keep only a short silent pacing window after attract. No guest thread,
    // queue, or game state is stopped.
    private static long _v1112PostAttractGuestDrainUntilTick;
    private static long _v1112LastAttractStopArmTick;
    private static int _v1112PostAttractBoundaryPending;

    private static int ResolvePostAttractGuestDrainMillisecondsV1112()
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_POST_ATTRACT_GUEST_DRAIN_MS");

        return int.TryParse(configured, out var parsed)
            ? Math.Clamp(parsed, 250, 5_000)
            : 1_500;
    }

    private static void ArmPostAttractTransitionFenceV1112(
        string reason)
    {
        var now = Environment.TickCount64;
        var last = Volatile.Read(
            ref _v1112LastAttractStopArmTick);

        // EndAtNominalMovieBoundary and RadBinkExternalPlayback.Dispose can
        // converge on the same movie end. Never re-arm after the next title
        // movie has already consumed the boundary.
        if (last > 0 &&
            now >= last &&
            now - last < 5_000)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.12] post_attract_duplicate_stop_ignored " +
                $"reason='{reason}' elapsed_ms={now - last}");
            return;
        }

        Volatile.Write(
            ref _v1112LastAttractStopArmTick,
            now);

        var drainMs =
            ResolvePostAttractGuestDrainMillisecondsV1112();

        var untilTick = checked(now + drainMs);

        Volatile.Write(
            ref _v1112PostAttractGuestDrainUntilTick,
            untilTick);

        Interlocked.Exchange(
            ref _v1112PostAttractBoundaryPending,
            1);

        // Exact host-owner teardown. The short guest drain below is separate:
        // it consumes/discards stale guest PCM while preserving guest pacing.
        _ = BinkDeterministicWavePlayerV317152.Stop();
        _ = PlaySound(null, IntPtr.Zero, 0);

        Console.Error.WriteLine(
            "[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_armed " +
            $"reason='{reason}' drain_ms={drainMs} until_tick={untilTick} " +
            "waveout_stopped=True playsound_stopped=True " +
            "audioout=True audioout2=True guest_pacing_preserved=True");
    }

    private static bool TryConsumePostAttractHostAudioBlockV1112(
        string fileName)
    {
        if (Volatile.Read(
                ref _v1112PostAttractBoundaryPending) == 0)
        {
            return false;
        }

        var isPostAttractTitle =
            string.Equals(
                fileName,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                fileName,
                "main_menu.bk2",
                StringComparison.OrdinalIgnoreCase);

        if (!isPostAttractTitle)
        {
            return false;
        }

        if (Interlocked.Exchange(
                ref _v1112PostAttractBoundaryPending,
                0) == 0)
        {
            return false;
        }

        lock (Gate)
        {
            _ = BinkDeterministicWavePlayerV317152.Stop();
            _ = PlaySound(null, IntPtr.Zero, 0);

            _activeRoot = null;
            _activeMovie = null;
            _activeMode = TimelineMode.None;
            _timelineStarted = false;
        }

        Console.Error.WriteLine(
            "[BINK-AUDIO-OWNER][V1.1.12] post_attract_host_audio_blocked " +
            $"next='{fileName}' waveout_stopped=True " +
            "playsound_stopped=True nihav_audio=False ffmpeg_audio=False " +
            "guest_drain_preserved=True");

        return true;
    }

'@

$text = $text.Insert(
    $muteRegion.Match.Index,
    $helperBlock)

# Re-resolve mute method after helper insertion.
$muteRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $mutePattern `
    -Name 'IsStartupGuestAudioMuteActiveV116'

$drainCheck = @'

        var v1112DrainUntil =
            Volatile.Read(
                ref _v1112PostAttractGuestDrainUntilTick);

        if (v1112DrainUntil > 0)
        {
            var v1112Now =
                Environment.TickCount64;

            if (v1112Now <= v1112DrainUntil)
            {
                return true;
            }

            if (Interlocked.CompareExchange(
                    ref _v1112PostAttractGuestDrainUntilTick,
                    0,
                    v1112DrainUntil) == v1112DrainUntil)
            {
                Console.Error.WriteLine(
                    "[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_released " +
                    $"elapsed_tick={v1112Now} guest_audio_restored=True");
            }
        }
'@

$text = $text.Insert(
    $muteRegion.OpenBrace + 1,
    $drainCheck)

# Block any title-side host audio re-arm immediately after attract, before asset
# resolution or older V1.1.11 reset logic can take ownership.
$preparePattern =
    '(?ms)^[ \t]*public[ \t]+static[ \t]+AttachDisposition[ \t]+PrepareAttach[ \t]*\([ \t\r\n]*string[ \t]+moviePath[ \t\r\n]*\)[ \t\r\n]*\{'

$prepareRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $preparePattern `
    -Name 'PrepareAttach'

$postAttractPrepareGuard = @'

        var v1112PostAttractFile =
            string.IsNullOrWhiteSpace(moviePath)
                ? string.Empty
                : Path.GetFileName(moviePath);

        if (TryConsumePostAttractHostAudioBlockV1112(
                v1112PostAttractFile))
        {
            // Returning NewTimeline makes BinkHostAudioBridge stop any generic
            // audio extraction for this title transition. Video playback is
            // untouched and remains owned by the selected movie backend.
            return AttachDisposition.NewTimeline;
        }
'@

$text = $text.Insert(
    $prepareRegion.OpenBrace + 1,
    $postAttractPrepareGuard)

# Arm before V1.1.11's owner-drift early return (if installed) and before normal
# StopForMovie cleanup.
$stopPattern =
    '(?ms)^[ \t]*public[ \t]+static[ \t]+void[ \t]+StopForMovie[ \t]*\([ \t\r\n]*string[ \t]+moviePath[ \t\r\n]*\)[ \t\r\n]*\{'

$stopRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $stopPattern `
    -Name 'StopForMovie'

$stopArm = @'

        if (!string.IsNullOrWhiteSpace(moviePath) &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            ArmPostAttractTransitionFenceV1112(
                "attract-playback-ended");
        }
'@

$text = $text.Insert(
    $stopRegion.OpenBrace + 1,
    $stopArm)

foreach ($required in @(
    'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12',
    '_v1112PostAttractGuestDrainUntilTick',
    'SHARPEMU_DS_POST_ATTRACT_GUEST_DRAIN_MS',
    '[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_armed',
    '[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_released',
    '[BINK-AUDIO-OWNER][V1.1.12] post_attract_host_audio_blocked',
    'TryConsumePostAttractHostAudioBlockV1112',
    'ArmPostAttractTransitionFenceV1112',
    'guest_pacing_preserved=True'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Intro post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "Post-attract guest PCM drain + title host-audio boundary installed."
