// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.10 direct-presentation helper.
///
/// The V61.13.9 trace showed PumpHostMovieFrame first observing
/// ps_studios_logo at serial 92 (~3.1s @ 30fps) and logo_intro at serial 178.
/// That means the auto-boot direct BGRA path was already running before the
/// guest-YUV replacement path joined it. V61.13.10 keeps only the direct BGRA
/// presentation path for this compatibility mode.
///
/// The known ps_studios WAV is started on the first direct BGRA presentation
/// and stopped after 8.5 seconds. logo_intro has no audio stream.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();

    private static bool _directStarted;
    private static bool _audioStarted;
    private static long _directFrameCount;

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

    internal static void OnDirectPresentationFrame(uint width, uint height)
    {
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_PRESENT_ONLY") != "1")
        {
            return;
        }

        lock (Gate)
        {
            var frame = ++_directFrameCount;

            if (!_directStarted)
            {
                _directStarted = true;
                Log(
                    "DIRECT_PRESENT_BEGIN",
                    "size=" + width + "x" + height +
                    " frame=" + frame.ToString(CultureInfo.InvariantCulture));

                TryStartAudioLocked();
            }

            if (frame <= 3 || frame % 30 == 0)
            {
                Log(
                    "DIRECT_PRESENT_FRAME",
                    "n=" + frame.ToString(CultureInfo.InvariantCulture) +
                    " size=" + width + "x" + height);
            }
        }
    }

    private static void TryStartAudioLocked()
    {
        if (_audioStarted ||
            !OperatingSystem.IsWindows() ||
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO") != "1")
        {
            return;
        }

        var wav = Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO_WAV");
        if (string.IsNullOrWhiteSpace(wav) || !File.Exists(wav))
        {
            Log("AUDIO_CACHE_MISSING", "movie='ps_studios_logo.bk2'");
            _audioStarted = true;
            return;
        }

        try
        {
            var ok = PlaySoundW(wav, 0, SndAsync | SndNodefault | SndFilename);
            _audioStarted = true;
            Log(
                "AUDIO_START",
                "movie='ps_studios_logo.bk2' wav='" + wav + "' started=" + ok);

            ThreadPool.QueueUserWorkItem(
                static _ =>
                {
                    Thread.Sleep(8_500);
                    lock (Gate)
                    {
                        if (!_audioStarted)
                        {
                            return;
                        }

                        try
                        {
                            _ = PlaySoundW(null, 0, SndPurge);
                        }
                        catch
                        {
                        }

                        _audioStarted = false;
                        Log("AUDIO_STOP", "movie='ps_studios_logo.bk2' reason=8500ms");
                    }
                });
        }
        catch (Exception ex)
        {
            _audioStarted = true;
            Log(
                "AUDIO_START_FAIL",
                "type=" + ex.GetType().Name +
                " message='" + ex.Message.Replace('\r',' ').Replace('\n',' ') + "'");
        }
    }

    internal static int GetExpectedDurationMs(string? hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return 0;
        }

        var file = Path.GetFileName(hostPath);
        if (file.Equals("ps_studios_logo.bk2", StringComparison.OrdinalIgnoreCase))
        {
            return 8_500;
        }
        if (file.Equals("logo_intro.bk2", StringComparison.OrdinalIgnoreCase))
        {
            return 12_000;
        }
        return 0;
    }

    // Compatibility no-ops retained so a cumulative checkout containing
    // V61.13.8/9 presenter hooks still compiles when direct-present mode is off.
    internal static void OnMovieFrame(string hostPath) { }
    internal static void EndMovieSession(string? hostPath) { }
    internal static void CompleteMovieSession(string? hostPath, string reason) { }

    internal static void LogExternal(string stage, string detail) => Log(stage, detail);

    private static void Log(string stage, string detail)
    {
        var path = Environment.GetEnvironmentVariable("SHARPEMU_BINK_SESSION_LOG");
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var line =
                DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) +
                " pid=" + Environment.ProcessId.ToString(CultureInfo.InvariantCulture) +
                " tid=" + Environment.CurrentManagedThreadId.ToString(CultureInfo.InvariantCulture) +
                " [" + stage + "] " + detail + Environment.NewLine;

            lock (LogGate)
            {
                File.AppendAllText(path, line, new UTF8Encoding(false));
            }
        }
        catch
        {
        }
    }

    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PlaySoundW(string? pszSound, nint hmod, uint fdwSound);
}
