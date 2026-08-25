using System;
using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

// V31.7.20.9_GUEST_LOGO_FIRST_RAD_ONLY_BOOT
// Guest owns startup presentation. Host auto-boot must not cover the game's
// first frames. Natural Bink requests use the RAD embedded-host lane.
internal static class DemonSoulsGuestOwnedRadBootPolicyV317209
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (BinkGuestOwnedRuntimeV7600.Enabled)
        {
            return;
        }

        SetDefault("SHARPEMU_BINK_MODE", "native-rad");
        SetDefault("SHARPEMU_BINK_AUTO_BOOT", "0");
        SetDefault("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS", "0");
        SetDefault("SHARPEMU_BINK_NATIVE_PREFER", "1");
        SetDefault("SHARPEMU_BINK_NATIVE_FALLBACK", "0");
        SetDefault("SHARPEMU_BINK_NATIVE_EXCLUSIVE", "1");
        SetDefault("SHARPEMU_RAD_POST_ATTRACT_LOOP_INTERNAL", "0");
        SetDefault("SHARPEMU_RAD_PLAYER_INPUT_LOCK", "1");
        SetDefault("SHARPEMU_RAD_CONTROL_STRIP_CLIP_PX", "24");

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.v317209_guest_logo_first_rad_only " +
            "guest_owned_boot=True host_auto_boot=False " +
            "movie_mode=native-rad native_exclusive=True external_rad_fallback=False " +
            "post_attract_loop=native-rad " +
            "startup='guest-logo -> natural-native-rad-movie-requests'");
    }

    private static void SetDefault(string name, string value)
    {
        if (string.IsNullOrWhiteSpace(
            Environment.GetEnvironmentVariable(name)))
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }
}