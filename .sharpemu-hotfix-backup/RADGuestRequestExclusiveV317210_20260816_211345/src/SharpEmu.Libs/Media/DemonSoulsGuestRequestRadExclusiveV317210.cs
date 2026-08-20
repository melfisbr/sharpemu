using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

internal static class DemonSoulsGuestRequestRadExclusiveV317210
{
    internal const string Marker =
        "V31.7.21.0_GUEST_REQUEST_RAD_EXCLUSIVE_USER_CLOSE";

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_GUEST_REQUEST_RAD_EXCLUSIVE"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        // Guest state owns when attract begins. Never inject it merely because
        // the first guest frame appeared.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_DEMONS_ATTRACT_GUEST_FRAME_HANDOFF",
            "0");

        // The V20.x diagnostic hard-gated HLE/guest work for the full RAD
        // movie. That prevents the title's StartIntro/MusicSkipIntro/sound/UI
        // state machines from advancing while the visual movie plays.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_THROTTLE_GUEST_GPU",
            "0");

        // V20.x used this sentinel for evidence collection and deliberately
        // ignored SDL close/quit requests until late in the movie sequence.
        // V21.0 always honors user shutdown.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_GUEST_CLOCK_CAPTURE_CLOSE_GUARD",
            null);

        // No host boot sequence. Natural guest movie requests still use the
        // requested global movie backend.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_AUTO_BOOT",
            "0");

        // V21.0 uses one source-only prearmed sidecar path. Disable older
        // in-process/embedded audio paths so they cannot duplicate it.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_DS_ATTRACT_EMBED_AUDIO",
            "0");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
            "0");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_DS_INTRO_WAVEOUT_CLOCK",
            "0");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_RAD_ATTRACT_AUDIO_RENDERER_TIMELINE_ZERO",
            "0");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_RAD_ATTRACT_AUDIO_PLAYBACK_ANCHOR_IMMEDIATE",
            "0");

        // Keep the fourth movie on the internal path so RAD shell/chrome cannot
        // reappear after attract.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_RAD_POST_ATTRACT_LOOP_INTERNAL",
            "1");

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.v317210_guest_request_rad_exclusive " +
            "guest_frame_handoff=False guest_hard_gate=False " +
            "close_guard=False old_host_audio=False " +
            "post_attract_loop=nihav");
    }
}
