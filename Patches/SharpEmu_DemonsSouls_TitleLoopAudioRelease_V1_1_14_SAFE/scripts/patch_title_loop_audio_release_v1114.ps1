param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "Title-loop guest-audio release already installed."
    exit 0
}

foreach ($required in @(
    'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13',
    'NotifyMovieAttachV1113',
    '_v1113PostAttractTitleChainGuestMuteActive',
    '_v1112PostAttractGuestDrainUntilTick',
    '_v1112LastAttractStopArmTick',
    'BinkDeterministicWavePlayerV317152.Stop()'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Required V1.1.13/V1.1.12 marker missing: $required"
    }
}

$methodPattern =
    '(?ms)^[ \t]*internal[ \t]+static[ \t]+void[ \t]+NotifyMovieAttachV1113[ \t]*\([ \t\r\n]*string[ \t]+moviePath[ \t\r\n]*\)[ \t\r\n]*\{'

$region = Find-MethodRegion `
    -Text $text `
    -Pattern $methodPattern `
    -Name 'NotifyMovieAttachV1113'

$oldMethod = $text.Substring(
    $region.Match.Index,
    $region.CloseBrace - $region.Match.Index + 1)

foreach ($required in @(
    'logo_intro.bk2',
    'logo_intro_loop.bk2',
    'title_chain_guest_mute_hold',
    'title_chain_guest_mute_released'
)) {
    if ($oldMethod.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Existing V1.1.13 lifecycle method missing expected marker: $required"
    }
}

$newMethod = @'
    // SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14
    //
    // V1.1.13 correctly proved that the attract bleed came through guest
    // AudioOut/AudioOut2, but it held that mute through logo_intro_loop.
    // Runtime telemetry now proves logo_intro_loop has host_audio_probe=False
    // and guest_audio_owner=True, with non-zero AudioOut2 peaks while muted.
    //
    // Correct ownership:
    //   attract end  -> arm guest discard
    //   logo_intro   -> keep guest discard active
    //   intro loop   -> stop any old host WaveOut, then release guest audio
    //                   before the loop starts
    //   other movie  -> ensure title-chain latch is released
    internal static void NotifyMovieAttachV1113(
        string moviePath)
    {
        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return;
        }

        var fileName =
            Path.GetFileName(moviePath);

        if (string.Equals(
                fileName,
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (string.Equals(
                fileName,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            // Keep consuming/discarding guest submissions while the one-shot
            // intro movie runs. This is what removes residual attract PCM
            // without stopping guest pacing.
            _ = BinkDeterministicWavePlayerV317152.Stop();
            _ = PlaySound(null, IntPtr.Zero, 0);

            var wasActive = Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                1);

            var hold = Interlocked.Increment(
                ref _v1113TitleChainHoldCount);

            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.14] title_intro_guest_drain_hold " +
                $"n={hold} file='{fileName}' " +
                $"already_active={wasActive != 0} " +
                "waveout_stopped=True playsound_stopped=True " +
                "guest_audio_muted=True guest_pacing_preserved=True");
            return;
        }

        if (string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            // The loop has no host-audio probe in the current title path:
            // its audio owner is the guest. Do not carry the attract mute into
            // this movie. Re-stop any stale host owner first, then release the
            // V1.1.13 lifecycle latch. The older V1.1.12 1500 ms drain remains
            // authoritative only if an unusually fast skip reaches the loop
            // before that minimum discard window has elapsed.
            _ = BinkDeterministicWavePlayerV317152.Stop();
            _ = PlaySound(null, IntPtr.Zero, 0);

            var wasActive = Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                0);

            var now =
                Environment.TickCount64;

            var attractStopTick =
                Volatile.Read(
                    ref _v1112LastAttractStopArmTick);

            var drainUntil =
                Volatile.Read(
                    ref _v1112PostAttractGuestDrainUntilTick);

            var elapsedSinceAttract =
                attractStopTick > 0 &&
                now >= attractStopTick
                    ? now - attractStopTick
                    : -1;

            var residualDrainMs =
                drainUntil > now
                    ? drainUntil - now
                    : 0;

            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.14] title_loop_guest_audio_release " +
                $"file='{fileName}' latch_was_active={wasActive != 0} " +
                $"elapsed_since_attract_ms={elapsedSinceAttract} " +
                $"residual_v1112_drain_ms={residualDrainMs} " +
                "waveout_stopped=True playsound_stopped=True " +
                "host_audio_probe=False guest_audio_owner=True " +
                "guest_audio_release_requested=True");
            return;
        }

        if (Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                0) != 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.14] title_intro_guest_drain_released " +
                $"next='{fileName}' " +
                "guest_audio_restored=True reason=left-post-attract-intro");
        }
    }
'@

$text = $text.Remove(
    $region.Match.Index,
    $region.CloseBrace - $region.Match.Index + 1)

$text = $text.Insert(
    $region.Match.Index,
    $newMethod)

foreach ($required in @(
    'SHARPEMU_DEMONS_TITLE_LOOP_AUDIO_RELEASE_V1_1_14',
    '[BINK-AUDIO-OWNER][V1.1.14] title_intro_guest_drain_hold',
    '[BINK-AUDIO-OWNER][V1.1.14] title_loop_guest_audio_release',
    'residual_v1112_drain_ms=',
    'guest_audio_release_requested=True',
    'host_audio_probe=False guest_audio_owner=True'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag V1.1.14 post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "Title-loop guest audio release installed; attract drain retained through logo_intro only."
