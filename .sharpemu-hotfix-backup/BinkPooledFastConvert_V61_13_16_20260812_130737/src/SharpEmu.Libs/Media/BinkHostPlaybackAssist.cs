// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.14 lightweight direct-movie audio/telemetry helper.
///
/// Decoder continuity is fixed in NihavBink2Decoder itself, so the presenter
/// no longer needs V61.13.11 per-frame hashes or CPU R/B rewrites.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();
    private static long _frameCount;
    private static bool _audioStarted;

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

    internal static bool TryNormalizeDirectPresentationFrame(
        byte[] pixels,
        uint width,
        uint height)
    {
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_PRESENT_ONLY") != "1")
        {
            return true;
        }

        lock (Gate)
        {
            var n = ++_frameCount;
            if (n == 1)
            {
                Log("DIRECT_STREAM_BEGIN", "size=" + width + "x" + height);
                TryStartAudioLocked();
            }

            if (n <= 3 || n % 30 == 0)
            {
                Log("DIRECT_FRAME", "n=" + n.ToString(CultureInfo.InvariantCulture));
            }
        }

        return true;
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
            return;
        }

        try
        {
            var ok = PlaySoundW(wav, 0, SndAsync | SndNodefault | SndFilename);
            _audioStarted = true;
            Log("AUDIO_START", "started=" + ok);
        }
        catch (Exception ex)
        {
            Log("AUDIO_START_FAIL", "message='" + ex.Message.Replace('\r',' ').Replace('\n',' ') + "'");
        }
    }

    internal static void OnDirectPresentationFrame(uint width, uint height) { }
    internal static int GetExpectedDurationMs(string? hostPath) =>
        string.IsNullOrWhiteSpace(hostPath)
            ? 0
            : Path.GetFileName(hostPath).Equals(
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase)
                ? 8_500
                : Path.GetFileName(hostPath).Equals(
                    "logo_intro.bk2",
                    StringComparison.OrdinalIgnoreCase)
                    ? 12_000
                    : 0;

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
