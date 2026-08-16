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
    private static long _movieThrottleStartTick;
    private static long _lastDirectFrameTick;
    private static long _movieCompleteTick;
    private static long _lastCapturePermitTick;
    private static long _capturePermitCount;
    private static bool _audioStarted;

    private const long BootMovieFrameCount = 613;

    // [V61.13.18][PRE_SNAPSHOT_GPU_THROTTLE]
    // V61.13.17 blocked payload work only after AGC had already evaluated the
    // shader and captured large guest-memory snapshots. The recovered runs
    // showed this was too late: blocked producers still retained 16+ MiB
    // snapshots each. V61.13.18 gates compute evaluation before those arrays
    // are captured, then releases work gradually after the real 613-frame boot
    // sequence completes.
    internal static bool ShouldThrottleGuestGpu
    {
        get
        {
            if (Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_THROTTLE_GUEST_GPU") != "1")
            {
                return false;
            }

            var frames = Interlocked.Read(ref _frameCount);
            return frames > 0 && frames < BootMovieFrameCount;
        }
    }

    internal static bool WaitForGuestGpuCapturePermit()
    {
        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_THROTTLE_GUEST_GPU") != "1")
        {
            return true;
        }

        while (true)
        {
            var frames = Interlocked.Read(ref _frameCount);
            if (frames <= 0)
            {
                return true;
            }

            var now = Environment.TickCount64;
            var started = Interlocked.Read(ref _movieThrottleStartTick);

            // Safety valve if a movie aborts before the expected boot boundary.
            if (started > 0 && now - started >= 90_000)
            {
                return true;
            }

            if (frames < BootMovieFrameCount)
            {
                Thread.Sleep(2);
                continue;
            }

            var complete = Interlocked.Read(ref _movieCompleteTick);
            if (complete <= 0)
            {
                Interlocked.CompareExchange(ref _movieCompleteTick, now, 0);
                complete = Interlocked.Read(ref _movieCompleteTick);
            }

            var elapsed = now - complete;

            // First let ordered release/event/acquire work drain without a new
            // burst of large compute snapshots.
            if (elapsed < 1000)
            {
                Thread.Sleep(2);
                continue;
            }

            // Then reopen compute capture progressively: ~31/s, 62/s, 125/s.
            var intervalMs = elapsed < 3000
                ? 32L
                : elapsed < 5000
                    ? 16L
                    : elapsed < 8000
                        ? 8L
                        : 0L;

            if (intervalMs == 0)
            {
                return true;
            }

            lock (Gate)
            {
                now = Environment.TickCount64;
                if (now - _lastCapturePermitTick >= intervalMs)
                {
                    _lastCapturePermitTick = now;
                    var permit = ++_capturePermitCount;
                    if (permit <= 8 || (permit & (permit - 1)) == 0)
                    {
                        Log(
                            "POST_MOVIE_CAPTURE_PERMIT",
                            "n=" + permit.ToString(CultureInfo.InvariantCulture) +
                            " elapsed_ms=" +
                            (now - complete).ToString(CultureInfo.InvariantCulture) +
                            " interval_ms=" +
                            intervalMs.ToString(CultureInfo.InvariantCulture));
                    }
                    return true;
                }
            }

            Thread.Sleep(1);
        }
    }

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
            _lastDirectFrameTick = Environment.TickCount64;
            if (n == 1)
            {
                _movieThrottleStartTick = _lastDirectFrameTick;
                Log(
                    "DIRECT_STREAM_BEGIN",
                    "size=" + width + "x" + height +
                    " guest_gpu_throttle=" +
                    (Environment.GetEnvironmentVariable(
                        "SHARPEMU_BINK_THROTTLE_GUEST_GPU") == "1"));
                TryStartAudioLocked();
            }

            if (n == BootMovieFrameCount)
            {
                Interlocked.Exchange(ref _movieCompleteTick, _lastDirectFrameTick);
                Log(
                    "BOOT_MOVIE_FRAME_BOUNDARY",
                    "frame=" + n.ToString(CultureInfo.InvariantCulture) +
                    " staged_gpu_release=1");
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
