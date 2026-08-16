// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.8.2 host-side companion for the natural Bink boot sequence.
///
/// Adds process-independent file telemetry so Bink/session/audio evidence is
/// preserved even when the mitigated SharpEmu child is detached from the
/// PowerShell launcher.
///
/// Opt-in through SHARPEMU_BINK_SESSION_LOG.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();

    private static string? _activeMovie;
    private static bool _audioStarted;
    private static bool _priorityApplied;
    private static long _frameHeartbeat;
    private static long _sessionStartTick;

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

    internal static void OnMovieFrame(string hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return;
        }

        lock (Gate)
        {
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

                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.session_begin file='{Path.GetFileName(hostPath)}'");
                Log(
                    "SESSION_BEGIN",
                    "file='" + Path.GetFileName(hostPath) +
                    "' path='" + hostPath + "'");
            }

            var heartbeat = ++_frameHeartbeat;
            if (heartbeat <= 3 || (heartbeat % 30) == 0)
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
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.audio_cache_missing; host audio disabled for this session.");
            Log("AUDIO_CACHE_MISSING", "movie='ps_studios_logo.bk2'");
            _audioStarted = true;
            return;
        }

        try
        {
            var ok = PlaySoundW(
                wav,
                0,
                SndAsync | SndNodefault | SndFilename);

            _audioStarted = true;

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.audio_start file='ps_studios_logo.bk2' " +
                $"wav='{wav}' started={ok}");

            Log(
                "AUDIO_START",
                "movie='ps_studios_logo.bk2' wav='" + wav +
                "' started=" + ok);
        }
        catch (Exception ex)
        {
            _audioStarted = true;

            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.audio_start_failed type={ex.GetType().Name} " +
                $"message='{Sanitize(ex.Message)}'");

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
            Log("AUDIO_STOP", "movie='" + Path.GetFileName(_activeMovie ?? string.Empty) + "'");
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

                    Console.Error.WriteLine(
                        $"[LOADER][INFO] bink2.nihav_priority pid={process.Id} class=AboveNormal");

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
            // Telemetry must never affect guest execution.
        }
    }

    private static string Sanitize(string value) =>
        value.Replace('\r', ' ').Replace('\n', ' ');

    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PlaySoundW(string? pszSound, nint hmod, uint fdwSound);
}
