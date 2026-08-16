// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.11 direct Bink frame normalizer.
///
/// Evidence:
/// - ps_studios_logo reports exactly 255 source frames @ 30 fps.
/// - logo_intro reports exactly 360 source frames @ 30 fps.
/// - V61.13.10 received >600 direct BGRA submissions, so both movies are in
///   the same direct Submit stream.
/// - the user observes visible rewinds/restarts inside ps_studios_logo.
/// - direct BGRA colors are still wrong, proving the earlier YUV-only fix was
///   not on the active path.
///
/// This helper:
/// 1. treats the first 255 direct submissions as ps_studios_logo and the next
///    360 as logo_intro;
/// 2. hashes each decoded frame and suppresses repeated previously-seen frames
///    inside the same source phase, keeping the last good frame visible;
/// 3. swaps R/B in the direct buffer when SHARPEMU_BINK_DIRECT_SWAP_RB=1;
/// 4. starts/stops the cached ps_studios WAV at source frame boundaries rather
///    than using an unrelated wall-clock timer.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();

    private static readonly HashSet<ulong> SeenFrameHashes = new();

    private static int _phase;
    private static int _phaseIncoming;
    private static int _phasePresented;
    private static int _phaseDuplicates;
    private static bool _audioStarted;
    private static bool _finished;

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

    private static string CurrentMovie =>
        _phase switch
        {
            0 => "ps_studios_logo.bk2",
            1 => "logo_intro.bk2",
            _ => "<complete>",
        };

    private static int CurrentExpectedFrames =>
        _phase switch
        {
            0 => 255,
            1 => 360,
            _ => 0,
        };

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
            if (_finished)
            {
                LogOnceLate();
                return false;
            }

            if (_phaseIncoming == 0)
            {
                SeenFrameHashes.Clear();
                Log(
                    "MOVIE_PHASE_BEGIN",
                    "phase=" + _phase.ToString(CultureInfo.InvariantCulture) +
                    " file='" + CurrentMovie +
                    "' expected_frames=" +
                    CurrentExpectedFrames.ToString(CultureInfo.InvariantCulture));

                if (_phase == 0)
                {
                    TryStartAudioLocked();
                }
            }

            _phaseIncoming++;

            var hash = SampleHash(pixels);
            var duplicate = !SeenFrameHashes.Add(hash);

            if (duplicate)
            {
                _phaseDuplicates++;

                if (_phaseDuplicates <= 5 || _phaseDuplicates % 30 == 0)
                {
                    Log(
                        "REWIND_FRAME_SUPPRESSED",
                        "file='" + CurrentMovie +
                        "' source_n=" + _phaseIncoming.ToString(CultureInfo.InvariantCulture) +
                        " duplicate_count=" + _phaseDuplicates.ToString(CultureInfo.InvariantCulture) +
                        " hash=0x" + hash.ToString("X16", CultureInfo.InvariantCulture));
                }
            }
            else
            {
                _phasePresented++;

                if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_SWAP_RB") == "1")
                {
                    SwapRedBlueInPlace(pixels);
                }

                if (_phasePresented <= 3 || _phasePresented % 30 == 0)
                {
                    Log(
                        "DIRECT_FRAME_ACCEPTED",
                        "file='" + CurrentMovie +
                        "' source_n=" + _phaseIncoming.ToString(CultureInfo.InvariantCulture) +
                        " shown_n=" + _phasePresented.ToString(CultureInfo.InvariantCulture) +
                        " hash=0x" + hash.ToString("X16", CultureInfo.InvariantCulture));
                }
            }

            var phaseComplete = _phaseIncoming >= CurrentExpectedFrames;
            if (phaseComplete)
            {
                var file = CurrentMovie;

                Log(
                    "MOVIE_PHASE_COMPLETE",
                    "phase=" + _phase.ToString(CultureInfo.InvariantCulture) +
                    " file='" + file +
                    "' source_frames=" + _phaseIncoming.ToString(CultureInfo.InvariantCulture) +
                    " shown_unique=" + _phasePresented.ToString(CultureInfo.InvariantCulture) +
                    " duplicates_suppressed=" + _phaseDuplicates.ToString(CultureInfo.InvariantCulture));

                if (_phase == 0)
                {
                    StopAudioLocked("source-frame-255");
                }

                _phase++;
                _phaseIncoming = 0;
                _phasePresented = 0;
                _phaseDuplicates = 0;
                SeenFrameHashes.Clear();

                if (_phase > 1)
                {
                    _finished = true;
                    Log("BOOT_MOVIES_COMPLETE", "source_frames_total=615");
                }
            }

            // A duplicate is deliberately not submitted to Vulkan. The prior
            // valid frame stays visible instead of visibly rewinding.
            return !duplicate;
        }
    }

    private static ulong SampleHash(byte[] pixels)
    {
        // FNV-1a over a deterministic sample of the whole image. Sampling is
        // enough to detect exact decoder rewinds without hashing ~3.6MB/frame.
        const ulong offset = 14695981039346656037UL;
        const ulong prime = 1099511628211UL;

        var hash = offset;
        var step = Math.Max(4, pixels.Length / 4096);
        step -= step % 4;
        if (step == 0)
        {
            step = 4;
        }

        for (var i = 0; i < pixels.Length; i += step)
        {
            hash ^= pixels[i];
            hash *= prime;

            if (i + 1 < pixels.Length)
            {
                hash ^= pixels[i + 1];
                hash *= prime;
            }

            if (i + 2 < pixels.Length)
            {
                hash ^= pixels[i + 2];
                hash *= prime;
            }
        }

        return hash;
    }

    private static void SwapRedBlueInPlace(byte[] pixels)
    {
        // NIHAV direct output is treated as RGBA by this compatibility path,
        // while VulkanVideoPresenter.Submit historically labels the byte array
        // as BGRA. Swap byte 0 and byte 2 to make the buffer truly BGRA.
        for (var i = 0; i + 3 < pixels.Length; i += 4)
        {
            (pixels[i], pixels[i + 2]) = (pixels[i + 2], pixels[i]);
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
            return;
        }

        try
        {
            var ok = PlaySoundW(wav, 0, SndAsync | SndNodefault | SndFilename);
            _audioStarted = true;
            Log(
                "AUDIO_START",
                "movie='ps_studios_logo.bk2' started=" + ok +
                " boundary=source-frame-1");
        }
        catch (Exception ex)
        {
            Log(
                "AUDIO_START_FAIL",
                "type=" + ex.GetType().Name +
                " message='" + Sanitize(ex.Message) + "'");
        }
    }

    private static void StopAudioLocked(string reason)
    {
        if (!_audioStarted || !OperatingSystem.IsWindows())
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
        Log("AUDIO_STOP", "movie='ps_studios_logo.bk2' reason=" + reason);
    }

    private static bool _lateLogged;

    private static void LogOnceLate()
    {
        if (_lateLogged)
        {
            return;
        }

        _lateLogged = true;
        Log("POST_BOOT_FRAME_DROPPED", "boot direct sequence already completed");
    }

    internal static void OnDirectPresentationFrame(uint width, uint height)
    {
        // Retained for cumulative V61.13.10 call sites. V61.13.11 frame
        // accounting happens in TryNormalizeDirectPresentationFrame.
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
