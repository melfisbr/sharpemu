using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

// V31.7.20.6.1_MEASURED_DURATION_TEMPO_LOCK
// Keeps V20.4 trim_start=579456 and V20.5 playback-anchor ownership.
// Corrects only the measured V20.4 duration ratio:
// 117366.7 / 116879.1 = 1.004171832.
internal static class DemonSoulsAttractAudioPolicyV317206
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (BinkGuestOwnedRuntimeV7600.Enabled)
        {
            return;
        }

        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "1.004172");

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.v317206_duration_tempo_lock " +
            "tempo=1.004172 nominal_ms=117366.7 calibrated_rad_ms=116879.1 " +
            "trim_start=579456 target_samples=5633600 " +
            "clock=waveout-playback-anchor");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }
}
