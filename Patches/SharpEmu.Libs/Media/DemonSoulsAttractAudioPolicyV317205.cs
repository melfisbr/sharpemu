using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

// V31.7.20.5_PLAYBACK_ANCHOR_SIDECAR_POLICY
// V20.4 proved the Demon's Souls intro WAV sample boundary. Do not alter the
// content again. The remaining A/V experiment is clock ownership: keep the
// original attract BK2 video-only and start the exact WAV via WaveOut from the
// measured RAD playback/reveal anchor. Explicit user/test environment values
// always win over these process-local defaults.
internal static class DemonSoulsAttractAudioPolicyV317205
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (BinkGuestOwnedRuntimeV7600.Enabled)
        {
            return;
        }

        SetDefault("SHARPEMU_DS_ATTRACT_EMBED_AUDIO", "0");
        SetDefault("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "1");
        SetDefault("SHARPEMU_DS_INTRO_WAVEOUT_CLOCK", "1");
        SetDefault("SHARPEMU_RAD_ATTRACT_AUDIO_RENDERER_TIMELINE_ZERO", "0");
        SetDefault("SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS", "0");

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.v317205_attract_audio_policy " +
            "embedded=False sidecar=True clock=waveout " +
            "anchor=rad-playback-before-reveal content=v20.4-fact-tail");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }
}