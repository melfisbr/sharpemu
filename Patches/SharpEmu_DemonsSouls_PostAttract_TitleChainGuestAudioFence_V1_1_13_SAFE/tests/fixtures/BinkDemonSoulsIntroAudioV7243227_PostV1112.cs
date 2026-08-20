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

    internal static bool IsStartupGuestAudioMuteActiveV116()
    {
        var v1112DrainUntil =
            Volatile.Read(
                ref _v1112PostAttractGuestDrainUntilTick);

        if (v1112DrainUntil > 0 &&
            Environment.TickCount64 <= v1112DrainUntil)
        {
            return true;
        }

        if (Volatile.Read(ref _v116GuestAudioMuteActive) == 0)
        {
            return false;
        }

        if (Environment.TickCount64 <=
            Volatile.Read(ref _v116GuestAudioMuteUntilTick))
        {
            return true;
        }

        Interlocked.Exchange(ref _v116GuestAudioMuteActive, 0);
        return false;
    }

    private static void ArmPostAttractTransitionFenceV1112(
        string reason)
    {
        Volatile.Write(
            ref _v1112LastAttractStopArmTick,
            Environment.TickCount64);

        Volatile.Write(
            ref _v1112PostAttractGuestDrainUntilTick,
            Environment.TickCount64 + 1500);

        Interlocked.Exchange(
            ref _v1112PostAttractBoundaryPending,
            1);

        _ = BinkDeterministicWavePlayerV317152.Stop();
        _ = PlaySound(null, IntPtr.Zero, 0);
    }

    public static void StopForMovie(string moviePath)
    {
        if (string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            ArmPostAttractTransitionFenceV1112(
                "attract-playback-ended");
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
