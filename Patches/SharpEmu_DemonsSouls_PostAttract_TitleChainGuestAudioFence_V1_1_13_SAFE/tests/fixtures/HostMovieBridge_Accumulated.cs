using System;

namespace SharpEmu.Libs.Media;

internal static class HostMovieBridge
{
    private enum MovieMode
    {
        Native,
        Nihav,
        Ffmpeg,
        Rad,
    }

    // V74.0.82.2 TITLE_LOOP_AUDIO host_audio_probe=False guest_audio_owner=True
    private static void AttachMovieLocked(
        string hostPath,
        MovieMode mode)
    {
        var fileName = System.IO.Path.GetFileName(hostPath);

        if (mode == MovieMode.Rad &&
            string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            mode = MovieMode.Nihav;
        }

        switch (mode)
        {
            case MovieMode.Rad:
                break;
            case MovieMode.Nihav:
                break;
        }
    }
}
