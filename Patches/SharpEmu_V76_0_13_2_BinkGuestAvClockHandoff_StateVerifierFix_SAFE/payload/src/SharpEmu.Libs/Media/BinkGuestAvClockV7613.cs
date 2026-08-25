// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using SharpEmu.HLE.Host;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V76.0.13 guest-owned Bink A/V handoff clock.
///
/// The guest remains the only decoder and audio owner.  This helper never
/// decodes, injects or resamples media.  It only prevents the first real Y/UV
/// frame from becoming visible a few milliseconds before the guest audio clock
/// has started to advance, then records presentation skew for diagnostics.
/// </summary>
internal static class BinkGuestAvClockV7613
{
    private static readonly object Gate = new();

    private static readonly bool Enabled =
        !string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_GUEST_AV_SYNC"),
            "0",
            StringComparison.Ordinal);

    private static readonly int FirstVisualHoldMaxMs =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_FIRST_VISUAL_HOLD_MS"),
            out var holdMs)
            ? Math.Clamp(holdMs, 0, 500)
            : 180;

    private static readonly int AudioStartThresholdMs =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUDIO_START_THRESHOLD_MS"),
            out var audioStartMs)
            ? Math.Clamp(audioStartMs, 0, 100)
            : 12;

    private static readonly int TargetFps =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_GUEST_TARGET_FPS"),
            out var targetFps)
            ? Math.Clamp(targetFps, 1, 120)
            : 30;

    private static long _epoch;
    private static string? _path;
    private static long _sessionStartTimestamp;
    private static double _sessionAudioStartSeconds;
    private static long _firstVisualTimestamp;
    private static int _firstVisualReleased;
    private static long _holdObservations;
    private static long _presentedFrames;
    private static long _lastPresentedProducerGeneration;

    internal static bool IsEnabled => Enabled;

    internal static void BeginSession(long epoch, string? path)
    {
        if (!Enabled || epoch <= 0)
        {
            return;
        }

        lock (Gate)
        {
            _epoch = epoch;
            _path = path;
            _sessionStartTimestamp = Stopwatch.GetTimestamp();
            _sessionAudioStartSeconds = GuestAudioClock.PlayedSeconds;
            _firstVisualTimestamp = 0;
            Volatile.Write(ref _firstVisualReleased, 0);
            _holdObservations = 0;
            _presentedFrames = 0;
            _lastPresentedProducerGeneration = 0;
        }

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.13][AV-CLOCK] begin " +
            $"epoch={epoch} file='{Path.GetFileName(path)}' " +
            $"audio_base_s={_sessionAudioStartSeconds:F6} " +
            $"hold_max_ms={FirstVisualHoldMaxMs} " +
            $"audio_start_threshold_ms={AudioStartThresholdMs} " +
            $"target_fps={TargetFps}");
    }

    internal static void EndSession(long epoch, string? path)
    {
        if (!Enabled)
        {
            return;
        }

        long frames;
        double wallSeconds;
        double audioSeconds;
        double videoSeconds;
        bool audioRunning;

        lock (Gate)
        {
            if (_epoch <= 0 || (epoch > 0 && epoch != _epoch))
            {
                return;
            }

            frames = _presentedFrames;
            wallSeconds = ElapsedSeconds(_sessionStartTimestamp);
            audioSeconds = Math.Max(
                0.0,
                GuestAudioClock.PlayedSeconds - _sessionAudioStartSeconds);
            videoSeconds = frames <= 1 ? 0.0 : (frames - 1) / (double)TargetFps;
            audioRunning = GuestAudioClock.IsRunning;

            _epoch = 0;
            _path = null;
            _sessionStartTimestamp = 0;
            _firstVisualTimestamp = 0;
            Volatile.Write(ref _firstVisualReleased, 0);
            _holdObservations = 0;
            _presentedFrames = 0;
            _lastPresentedProducerGeneration = 0;
        }

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.13][AV-CLOCK] end " +
            $"epoch={epoch} file='{Path.GetFileName(path)}' " +
            $"presented={frames} wall_s={wallSeconds:F3} " +
            $"audio_s={audioSeconds:F3} video_est_s={videoSeconds:F3} " +
            $"skew_video_minus_audio_s={videoSeconds - audioSeconds:F3} " +
            $"audio_running={(audioRunning ? 1 : 0)}");
    }

    /// <summary>
    /// Returns true only during the short first-frame handoff window.  Callers
    /// should bind their existing neutral-black Y/UV texture instead of waiting
    /// or blocking the render thread.
    /// </summary>
    internal static bool ShouldHoldFirstVisual(long epoch)
    {
        if (!Enabled ||
            epoch <= 0 ||
            FirstVisualHoldMaxMs <= 0 ||
            Volatile.Read(ref _firstVisualReleased) != 0)
        {
            return false;
        }

        string? releaseReason = null;
        long observation = 0;
        double audioDelta = 0.0;
        double firstVisualMs = 0.0;
        bool audioRunning = false;

        lock (Gate)
        {
            if (_epoch != epoch ||
                _sessionStartTimestamp == 0 ||
                Volatile.Read(ref _firstVisualReleased) != 0)
            {
                return false;
            }

            var now = Stopwatch.GetTimestamp();
            if (_firstVisualTimestamp == 0)
            {
                _firstVisualTimestamp = now;
                Console.Error.WriteLine(
                    "[BINK-GUEST][V76.0.13][HANDOFF] arm " +
                    $"epoch={epoch} file='{Path.GetFileName(_path)}' " +
                    $"hold_max_ms={FirstVisualHoldMaxMs}");
            }

            audioDelta = Math.Max(
                0.0,
                GuestAudioClock.PlayedSeconds - _sessionAudioStartSeconds);
            audioRunning = GuestAudioClock.IsRunning;
            firstVisualMs =
                (now - _firstVisualTimestamp) * 1000.0 / Stopwatch.Frequency;

            if (audioRunning &&
                audioDelta * 1000.0 >= AudioStartThresholdMs)
            {
                Volatile.Write(ref _firstVisualReleased, 1);
                releaseReason = "guest-audio-started";
            }
            else if (firstVisualMs >= FirstVisualHoldMaxMs)
            {
                Volatile.Write(ref _firstVisualReleased, 1);
                releaseReason = audioRunning
                    ? "hold-timeout-audio-below-threshold"
                    : "hold-timeout-no-audio";
            }
            else
            {
                observation = ++_holdObservations;
            }
        }

        if (releaseReason is not null)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.13][HANDOFF] release " +
                $"epoch={epoch} reason={releaseReason} " +
                $"first_visual_ms={firstVisualMs:F3} " +
                $"audio_s={audioDelta:F3} " +
                $"audio_running={(audioRunning ? 1 : 0)}");
            return false;
        }

        if (observation <= 8 || (observation & (observation - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.13][HANDOFF] hold " +
                $"count={observation} epoch={epoch} " +
                $"first_visual_ms={firstVisualMs:F3} " +
                $"audio_s={audioDelta:F3} " +
                $"audio_running={(audioRunning ? 1 : 0)} " +
                "action=neutral-yuv-no-render-thread-wait");
        }

        return true;
    }

    internal static void NotifyPresentedFrame(long epoch, long producerGeneration)
    {
        if (!Enabled || epoch <= 0)
        {
            return;
        }

        long frame;
        double wallSeconds;
        double audioSeconds;
        double videoSeconds;
        bool audioRunning;
        string? path;

        lock (Gate)
        {
            if (_epoch != epoch || _sessionStartTimestamp == 0)
            {
                return;
            }

            if (producerGeneration > 0 &&
                producerGeneration == _lastPresentedProducerGeneration)
            {
                return;
            }

            if (producerGeneration > 0)
            {
                _lastPresentedProducerGeneration = producerGeneration;
            }
            frame = ++_presentedFrames;
            wallSeconds = ElapsedSeconds(_sessionStartTimestamp);
            audioSeconds = Math.Max(
                0.0,
                GuestAudioClock.PlayedSeconds - _sessionAudioStartSeconds);
            videoSeconds = frame <= 1 ? 0.0 : (frame - 1) / (double)TargetFps;
            audioRunning = GuestAudioClock.IsRunning;
            path = _path;
        }

        if (frame <= 8 || frame % 30 == 0 || (frame & (frame - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.13][AV-SYNC] " +
                $"frame={frame} epoch={epoch} producer_generation={producerGeneration} " +
                $"file='{Path.GetFileName(path)}' " +
                $"wall_s={wallSeconds:F3} audio_s={audioSeconds:F3} " +
                $"video_est_s={videoSeconds:F3} " +
                $"skew_video_minus_audio_s={videoSeconds - audioSeconds:F3} " +
                $"audio_running={(audioRunning ? 1 : 0)}");
        }
    }

    private static double ElapsedSeconds(long startTimestamp)
    {
        if (startTimestamp <= 0)
        {
            return 0.0;
        }

        return Math.Max(
            0.0,
            (Stopwatch.GetTimestamp() - startTimestamp) /
            (double)Stopwatch.Frequency);
    }
}
