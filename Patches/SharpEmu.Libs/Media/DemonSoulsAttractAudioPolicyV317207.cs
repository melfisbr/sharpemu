using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

// V31.7.20.7_IMMEDIATE_ANCHOR_INTERNAL_LOOP_POLICY
internal static class DemonSoulsAttractAudioPolicyV317207
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
        SetDefault("SHARPEMU_RAD_ATTRACT_AUDIO_PLAYBACK_ANCHOR_IMMEDIATE", "1");
        SetDefault("SHARPEMU_RAD_POST_ATTRACT_LOOP_INTERNAL", "0");

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.v317207_policy " +
            "attract_audio=waveout-sidecar anchor=playback-immediate " +
            "tempo=fixed-experiment-disabled content=v20.4-tail " +
            "post_attract_loop=rad");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }
}