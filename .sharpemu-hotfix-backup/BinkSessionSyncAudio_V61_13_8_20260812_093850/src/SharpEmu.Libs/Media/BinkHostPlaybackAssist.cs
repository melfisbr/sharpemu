// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.7 host-side companion for the natural Bink boot sequence.
/// - Starts a pre-decoded WAV when the matching BK2 session begins.
/// - Gives the external nihav decoder AboveNormal priority once discovered.
/// Both features are opt-in and Windows-only.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static string? _activeMovie;
    private static bool _audioStarted;
    private static bool _priorityApplied;

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
                _activeMovie = hostPath;
                _audioStarted = false;
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.session_begin file='{Path.GetFileName(hostPath)}'");
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

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.session_end file='{Path.GetFileName(_activeMovie)}'");
            StopAudioLocked();
            _activeMovie = null;
            _audioStarted = false;
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

        // The current boot probe established that ps_studios_logo.bk2 has
        // Bink Audio DCT, stereo, 48 kHz. logo_intro.bk2 has no audio stream.
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
        }
        catch (Exception ex)
        {
            _audioStarted = true;
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.audio_start_failed type={ex.GetType().Name} " +
                $"message='{ex.Message.Replace('\r', ' ').Replace('\n', ' ')}'");
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

    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PlaySoundW(string? pszSound, nint hmod, uint fdwSound);
}
