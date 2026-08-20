using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace SharpEmu.Libs.Media;

internal static class BinkDemonSoulsIntroAudioV7243227
{
    // SHARPEMU_DEMONS_STARTUP_GUEST_AUDIO_OWNERSHIP_V1_1_6
    private static int _v116GuestAudioMuteActive;
    private static long _v116GuestAudioMuteUntilTick;

    // SHARPEMU_DEMONS_POST_ATTRACT_TRANSITION_FENCE_V1_1_12
    private static long _v1112PostAttractGuestDrainUntilTick;
    private static long _v1112LastAttractStopArmTick;
    private static int _v1112PostAttractBoundaryPending;

    // SHARPEMU_DEMONS_POST_ATTRACT_TITLE_CHAIN_AUDIO_FENCE_V1_1_13
    private static int _v1113PostAttractTitleChainGuestMuteActive;
    private static long _v1113TitleChainHoldCount;

    internal static bool IsStartupGuestAudioMuteActiveV116()
    {
        if (Volatile.Read(
                ref _v1113PostAttractTitleChainGuestMuteActive) != 0)
        {
            return true;
        }

        var drainUntil =
            Volatile.Read(
                ref _v1112PostAttractGuestDrainUntilTick);

        if (drainUntil > 0 &&
            Environment.TickCount64 <= drainUntil)
        {
            return true;
        }

        return Volatile.Read(ref _v116GuestAudioMuteActive) != 0;
    }

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
            _ = BinkDeterministicWavePlayerV317152.Stop();
            _ = PlaySound(null, IntPtr.Zero, 0);

            var wasActive = Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                1);

            var hold = Interlocked.Increment(
                ref _v1113TitleChainHoldCount);

            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_hold " +
                $"n={hold} file='{fileName}' already_active={wasActive != 0}");
            return;
        }

        if (Interlocked.Exchange(
                ref _v1113PostAttractTitleChainGuestMuteActive,
                0) != 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.13] title_chain_guest_mute_released " +
                $"next='{fileName}'");
        }
    }

    [DllImport("winmm.dll")]
    private static extern bool PlaySound(
        string? pszSound,
        IntPtr hmod,
        uint fdwSound);
}

internal static class BinkDeterministicWavePlayerV317152
{
    internal static bool Stop() => true;
}
