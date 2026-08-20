param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$text = Get-Content -LiteralPath $Path -Raw
$marker = 'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13'

if ($text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
    Write-Step "Post-attract title-chain guest-audio fence already installed."
    exit 0
}

foreach ($required in @(
    'SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12',
    'SHARPEMU_DEMONS_STARTUP_GUEST_AUDIO_OWNERSHIP_V1_1_6',
    'IsStartupGuestAudioMuteActiveV116',
    'ArmPostAttractTransitionFenceV1112',
    '_v1112PostAttractBoundaryPending',
    '_v1112PostAttractGuestDrainUntilTick',
    'BinkDeterministicWavePlayerV317152.Stop()'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Required accumulated intro-audio marker missing: $required"
    }
}

# 1. Add lifecycle latch after V1.1.12 boundary state.
$fieldPattern =
    '(?m)^(?<indent>[ \t]*)private[ \t]+static[ \t]+int[ \t]+_v1112PostAttractBoundaryPending[ \t]*;'

$fieldMatch = [regex]::Match(
    $text,
    $fieldPattern,
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

if (-not $fieldMatch.Success) {
    throw "$script:Tag V1.1.12 boundary field not found structurally."
}

$indent = $fieldMatch.Groups['indent'].Value
$fieldInsert = [Environment]::NewLine +
    [Environment]::NewLine +
    $indent + '// SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13' + [Environment]::NewLine +
    $indent + '// Keep guest AudioOut/AudioOut2 silent for the entire zero-track' + [Environment]::NewLine +
    $indent + '// post-attract title chain. Guest threads/pacing continue normally.' + [Environment]::NewLine +
    $indent + 'private static int _v1113PostAttractTitleChainGuestMuteActive;' + [Environment]::NewLine +
    $indent + 'private static long _v1113TitleChainHoldCount;'

$text = $text.Insert(
    $fieldMatch.Index + $fieldMatch.Length,
    $fieldInsert)

# 2. Lifecycle latch takes precedence over V1.1.12's 1500ms drain.
$mutePattern =
    '(?ms)^[ \t]*internal[ \t]+static[ \t]+bool[ \t]+IsStartupGuestAudioMuteActiveV116[ \t]*\([ \t\r\n]*\)[ \t\r\n]*\{'

$muteRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $mutePattern `
    -Name 'IsStartupGuestAudioMuteActiveV116'

$mutePrefix = @'

        // V1.1.13: title-chain ownership is lifecycle-based, not timer-based.
        if (Volatile.Read(
                ref _v1113PostAttractTitleChainGuestMuteActive) != 0)
        {
            return true;
        }
'@

$text = $text.Insert(
    $muteRegion.OpenBrace + 1,
    $mutePrefix)

# 3. Arm the lifecycle latch at exact attract teardown.
$armPattern =
    '(?ms)^[ \t]*private[ \t]+static[ \t]+void[ \t]+ArmPostAttractTransitionFenceV1112[ \t]*\([ \t\r\n]*string[ \t]+reason[ \t\r\n]*\)[ \t\r\n]*\{'

$armRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $armPattern `
    -Name 'ArmPostAttractTransitionFenceV1112'

$armPrefix = @'

        if (Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                1) == 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_armed " +
                $"reason='{reason}' " +
                "hold=logo_intro+logo_intro_loop " +
                "audioout=True audioout2=True guest_pacing_preserved=True");
        }
'@

$text = $text.Insert(
    $armRegion.OpenBrace + 1,
    $armPrefix)

# Re-resolve method offsets after insertion.
$armRegion = Find-MethodRegion `
    -Text $text `
    -Pattern $armPattern `
    -Name 'ArmPostAttractTransitionFenceV1112'

# 4. Direct movie-lifecycle hook called by HostMovieBridge.
$lifecycleMethod = @'
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

        var isPostAttractTitleChain =
            string.Equals(
                fileName,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase);

        if (isPostAttractTitleChain)
        {
            // Reassert host-owner shutdown on every title-chain attach.
            // Current runtime says host_audio_probe=False for the loop, but
            // this also blocks any late deterministic WaveOut/PlaySound owner.
            _ = BinkDeterministicWavePlayerV317152.Stop();
            _ = PlaySound(null, IntPtr.Zero, 0);

            var wasActive = Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                1);

            var hold = Interlocked.Increment(
                ref _v1113TitleChainHoldCount);

            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_hold " +
                $"n={hold} file='{fileName}' " +
                $"already_active={wasActive != 0} " +
                "waveout_stopped=True playsound_stopped=True " +
                "host_audio_probe=False guest_audio_muted=True " +
                "guest_pacing_preserved=True");
            return;
        }

        if (Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                0) != 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_released " +
                $"next='{fileName}' " +
                "guest_audio_restored=True reason=left-zero-track-title-chain");
        }
    }

'@

$text = $text.Insert(
    $armRegion.Match.Index,
    $lifecycleMethod)

foreach ($required in @(
    'SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13',
    '_v1113PostAttractTitleChainGuestMuteActive',
    'NotifyMovieAttachV1113',
    '[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_armed',
    '[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_hold',
    '[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_released',
    'hold=logo_intro+logo_intro_loop',
    'guest_audio_muted=True',
    'guest_pacing_preserved=True'
)) {
    if ($text.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "$script:Tag Intro V1.1.13 post-patch marker missing: $required"
    }
}

Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
Write-Step "Lifecycle title-chain guest-audio fence installed."
