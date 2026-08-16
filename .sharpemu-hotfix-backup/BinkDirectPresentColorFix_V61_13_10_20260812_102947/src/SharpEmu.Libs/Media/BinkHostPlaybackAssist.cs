// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.9 host-side Bink boot playback assistant.
///
/// The V61.13.8.2 trace proved that the 2.5-second "no frame" timeout was
/// fragmenting one BK2 into several fake sessions. This helper now distinguishes
/// natural session end from wall-clock completion and suppresses late frames from
/// reopening an already-completed boot movie.
///
/// ps_studios_logo.bk2: 255 @ 30 fps = 8.50 s
/// logo_intro.bk2:      360 @ 30 fps = 12.00 s
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();

    private static string? _activeMovie;
    private static string? _completedMovie;
    private static bool _audioStarted;
    private static bool _priorityApplied;
    private static long _frameHeartbeat;
    private static long _lateFrameCount;
    private static long _sessionStartTick;

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

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

    internal static void OnMovieFrame(string hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return;
        }

        lock (Gate)
        {
            if (_completedMovie is not null &&
                string.Equals(_completedMovie, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                var late = ++_lateFrameCount;
                if (late <= 3 || late % 30 == 0)
                {
                    Log(
                        "LATE_FRAME_SUPPRESSED",
                        "file='" + Path.GetFileName(hostPath) +
                        "' n=" + late.ToString(CultureInfo.InvariantCulture));
                }
                return;
            }

            if (_completedMovie is not null &&
                !string.Equals(_completedMovie, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                _completedMovie = null;
                _lateFrameCount = 0;
            }

            if (!string.Equals(_activeMovie, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                StopAudioLocked();

                if (_activeMovie is not null)
                {
                    Log(
                        "SESSION_SWITCH",
                        "from='" + Path.GetFileName(_activeMovie) +
                        "' to='" + Path.GetFileName(hostPath) + "'");
                }

                _activeMovie = hostPath;
                _audioStarted = false;
                _frameHeartbeat = 0;
                _sessionStartTick = Environment.TickCount64;

                var expectedMs = GetExpectedDurationMs(hostPath);

                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.session_begin file='{Path.GetFileName(hostPath)}' " +
                    $"expected_ms={expectedMs}");

                Log(
                    "SESSION_BEGIN",
                    "file='" + Path.GetFileName(hostPath) +
                    "' path='" + hostPath +
                    "' expected_ms=" + expectedMs.ToString(CultureInfo.InvariantCulture));
            }

            var heartbeat = ++_frameHeartbeat;
            if (heartbeat <= 3 || heartbeat % 30 == 0)
            {
                Log(
                    "FRAME_HEARTBEAT",
                    "file='" + Path.GetFileName(hostPath) +
                    "' n=" + heartbeat.ToString(CultureInfo.InvariantCulture) +
                    " elapsed_ms=" +
                    (Environment.TickCount64 - _sessionStartTick)
                        .ToString(CultureInfo.InvariantCulture));
            }

            TryBoostNihavPriorityLocked();
            TryStartAudioLocked(hostPath);
        }
    }

    internal static void CompleteMovieSession(string? hostPath, string reason)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return;
        }

        lock (Gate)
        {
            if (_completedMovie is not null &&
                string.Equals(_completedMovie, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var elapsed =
                _sessionStartTick > 0
                    ? Environment.TickCount64 - _sessionStartTick
                    : 0;

            var expected = GetExpectedDurationMs(hostPath);

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.session_complete file='{Path.GetFileName(hostPath)}' " +
                $"elapsed_ms={elapsed} expected_ms={expected} reason={reason}");

            Log(
                "SESSION_COMPLETE",
                "file='" + Path.GetFileName(hostPath) +
                "' elapsed_ms=" + elapsed.ToString(CultureInfo.InvariantCulture) +
                " expected_ms=" + expected.ToString(CultureInfo.InvariantCulture) +
                " heartbeats=" + _frameHeartbeat.ToString(CultureInfo.InvariantCulture) +
                " reason=" + reason);

            StopAudioLocked();
            _completedMovie = hostPath;
            _activeMovie = null;
            _audioStarted = false;
            _frameHeartbeat = 0;
            _lateFrameCount = 0;
            _sessionStartTick = 0;
        }
    }

    internal static void EndMovieSession(string? hostPath)
    {
        lock (Gate)
        {
            if (_activeMovie is null)
            {
                return;
            }

            if (!string.IsNullOrWhiteSpace(hostPath) &&
                !string.Equals(_activeMovie, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var elapsed = Environment.TickCount64 - _sessionStartTick;

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.session_end file='{Path.GetFileName(_activeMovie)}'");

            Log(
                "SESSION_END",
                "file='" + Path.GetFileName(_activeMovie) +
                "' elapsed_ms=" + elapsed.ToString(CultureInfo.InvariantCulture) +
                " heartbeats=" + _frameHeartbeat.ToString(CultureInfo.InvariantCulture));

            StopAudioLocked();
            _activeMovie = null;
            _audioStarted = false;
            _frameHeartbeat = 0;
            _sessionStartTick = 0;
        }
    }

    private static void TryStartAudioLocked(string hostPath)
    {
        if (_audioStarted ||
            !OperatingSystem.IsWindows() ||
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO") != "1")
        {
            return;
        }

        if (!Path.GetFileName(hostPath).Equals(
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase))
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
                "movie='ps_studios_logo.bk2' wav='" + wav +
                "' started=" + ok);
        }
        catch (Exception ex)
        {
            _audioStarted = true;
            Log(
                "AUDIO_START_FAIL",
                "type=" + ex.GetType().Name +
                " message='" + Sanitize(ex.Message) + "'");
        }
    }

    private static void StopAudioLocked()
    {
        if (!OperatingSystem.IsWindows() || !_audioStarted)
        {
            return;
        }

        try
        {
            _ = PlaySoundW(null, 0, SndPurge);
            Log(
                "AUDIO_STOP",
                "movie='" + Path.GetFileName(_activeMovie ?? _completedMovie ?? string.Empty) + "'");
        }
        catch
        {
        }

        _audioStarted = false;
    }

    private static void TryBoostNihavPriorityLocked()
    {
        if (_priorityApplied ||
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_NIHAV_PRIORITY") != "1")
        {
            return;
        }

        try
        {
            foreach (var process in Process.GetProcessesByName("nihav-tool"))
            {
                try
                {
                    process.PriorityClass = ProcessPriorityClass.AboveNormal;
                    _priorityApplied = true;
                    Log(
                        "NIHAV_PRIORITY",
                        "pid=" + process.Id.ToString(CultureInfo.InvariantCulture) +
                        " class=AboveNormal");
                    break;
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
        }
        catch
        {
        }
    }

    internal static void LogExternal(string stage, string detail) =>
        Log(stage, detail);

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
                " [" + stage + "] " + detail +
                Environment.NewLine;

            lock (LogGate)
            {
                File.AppendAllText(path, line, new UTF8Encoding(false));
            }
        }
        catch
        {
        }
    }

    private static string Sanitize(string value) =>
        value.Replace('\r', ' ').Replace('\n', ' ');

    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PlaySoundW(string? pszSound, nint hmod, uint fdwSound);
}
