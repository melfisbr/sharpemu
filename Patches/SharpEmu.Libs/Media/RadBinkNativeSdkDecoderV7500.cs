// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;

namespace SharpEmu.Libs.Media;

/// <summary>
/// In-process Bink SDK decoder front-end.
///
/// Video is decoded by SharpEmu.BinkNative.dll into a bounded BGRA ring owned
/// by MediaFramePlayback. Embedded Bink audio remains owned by the SDK adapter.
/// Demon's Souls attract_movie has no embedded Bink track, so its existing
/// deterministic AT9/WaveOut cursor becomes the preferred presentation clock.
/// </summary>
internal sealed class RadBinkNativeSdkDecoderV7500 :
    IMediaFrameDecoder,
    IMediaPlaybackClockSource,
    IMediaPresentationAware,
    IMediaFrameBufferPolicy
{
    private readonly nint _movie;
    private readonly string _moviePath;
    private readonly bool _preferDemonSoulsSidecarClock;
    private long _decodedFrames;
    private long _decodeTicks;
    private int _presentationStarted;
    private int _disposed;

    private RadBinkNativeSdkDecoderV7500(
        string moviePath,
        nint movie,
        BinkNativeSdkAbiV7500.NativeMovieInfo info)
    {
        _moviePath = moviePath;
        _movie = movie;

        Width = info.Width;
        Height = info.Height;
        FramesPerSecondNumerator =
            info.FramesPerSecondNumerator;
        FramesPerSecondDenominator =
            info.FramesPerSecondDenominator;
        FrameCount = info.FrameCount;
        AudioTrackCount = info.AudioTrackCount;
        EmbeddedAudioActive =
            (info.Flags &
             BinkNativeSdkAbiV7500.InfoFlagEmbeddedAudioActive) != 0;

        _preferDemonSoulsSidecarClock =
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase);

        // Match RAD/Nihav's lifecycle ownership. BinkHostPlaybackAssist keeps
        // title/UI movies guest-live while applying the existing one-shot gate
        // semantics to movies that require it.
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath);
    }

    internal static bool IsRuntimeAvailable =>
        BinkNativeSdkAbiV7500.IsAvailable;

    internal static string? RuntimeLibraryPath =>
        BinkNativeSdkAbiV7500.LibraryPath;

    internal static bool TryOpen(
        string moviePath,
        out RadBinkNativeSdkDecoderV7500? decoder)
    {
        decoder = null;

        if (BinkGuestOwnedRuntimeV7600.Enabled)
        {
            return false;
        }

        if (!BinkNativeSdkAbiV7500.TryOpen(
                moviePath,
                out var movie,
                out var info,
                out var error))
        {
            Console.Error.WriteLine(
                "[BINK-NATIVE][V75.0.0] open_failed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"detail='{Sanitize(error)}'");
            return false;
        }

        if (info.Width == 0 ||
            info.Height == 0 ||
            info.FramesPerSecondNumerator == 0 ||
            info.FramesPerSecondDenominator == 0 ||
            (ulong)info.Width * info.Height * 4 > int.MaxValue)
        {
            BinkNativeSdkAbiV7500.Close(movie);
            Console.Error.WriteLine(
                "[BINK-NATIVE][V75.0.0] open_rejected_invalid_info " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"size={info.Width}x{info.Height} " +
                $"fps={info.FramesPerSecondNumerator}/" +
                $"{info.FramesPerSecondDenominator}");
            return false;
        }

        var embeddedAudioActive =
            (info.Flags &
             BinkNativeSdkAbiV7500.InfoFlagEmbeddedAudioActive) != 0;

        if (info.AudioTrackCount > 0 &&
            !embeddedAudioActive &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_NATIVE_ALLOW_SILENT_EMBEDDED_AUDIO") != "1")
        {
            BinkNativeSdkAbiV7500.Close(movie);
            Console.Error.WriteLine(
                "[BINK-NATIVE][V75.0.0] open_rejected_audio_provider " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"tracks={info.AudioTrackCount} " +
                "embedded_audio_active=False " +
                "fallback_required=True");
            return false;
        }

        decoder = new RadBinkNativeSdkDecoderV7500(
            moviePath,
            movie,
            info);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.0] open_ok " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"size={info.Width}x{info.Height} " +
            $"fps={info.FramesPerSecondNumerator}/" +
            $"{info.FramesPerSecondDenominator} " +
            $"frames={info.FrameCount} " +
            $"tracks={info.AudioTrackCount} " +
            $"embedded_audio_active={embeddedAudioActive} " +
            $"dll='{RuntimeLibraryPath}'");
        return true;
    }

    public uint Width { get; }

    public uint Height { get; }

    public uint FramesPerSecondNumerator { get; }

    public uint FramesPerSecondDenominator { get; }

    internal uint FrameCount { get; }

    internal uint AudioTrackCount { get; }

    internal bool EmbeddedAudioActive { get; }

    public int PreferredBufferCount => 3;

    public bool PrimeFirstFrameSynchronously => true;

    public bool TryDecodeNextFrame(
        Span<byte> destination)
    {
        ObjectDisposedException.ThrowIf(
            Volatile.Read(ref _disposed) != 0,
            this);

        var requiredBytes =
            checked((int)((ulong)Width * Height * 4));

        if (destination.Length < requiredBytes)
        {
            throw new ArgumentException(
                $"Destination is too small: {destination.Length} < {requiredBytes}.",
                nameof(destination));
        }

        var started = Stopwatch.GetTimestamp();
        var result = BinkNativeSdkAbiV7500.DecodeBgra(
            _movie,
            destination[..requiredBytes],
            checked((int)Width * 4));
        var elapsed = Stopwatch.GetElapsedTime(started);

        if (result == 0)
        {
            Console.Error.WriteLine(
                "[BINK-NATIVE][V75.0.0] eos " +
                $"file='{Path.GetFileName(_moviePath)}' " +
                $"decoded={_decodedFrames}");
            return false;
        }

        if (result < 0)
        {
            throw new InvalidOperationException(
                "Native Bink decode failed: " +
                BinkNativeSdkAbiV7500.LastError);
        }

        var decoded = Interlocked.Increment(
            ref _decodedFrames);
        Interlocked.Add(
            ref _decodeTicks,
            elapsed.Ticks);

        if (decoded <= 3 || decoded % 120 == 0)
        {
            var totalTicks =
                Math.Max(
                    1,
                    Interlocked.Read(ref _decodeTicks));

            Console.Error.WriteLine(
                "[BINK-NATIVE][PERF][V75.0.0] " +
                $"file='{Path.GetFileName(_moviePath)}' " +
                $"frame={decoded} " +
                $"decode_ms={elapsed.TotalMilliseconds:F3} " +
                $"decode_avg_ms={TimeSpan.FromTicks(totalTicks / decoded).TotalMilliseconds:F3} " +
                $"queue_buffers={PreferredBufferCount}");
        }

        return true;
    }

    public void NotifyPresentationStarted()
    {
        if (Interlocked.Exchange(ref _presentationStarted, 1) != 0 ||
            Volatile.Read(ref _disposed) != 0)
        {
            return;
        }

        // Release embedded PCM and the native media clock exactly at the first
        // presentable frame. Demon's Souls attract_movie is video-only, so the
        // same seam releases its deterministic AT9 sidecar instead.
        BinkNativeSdkAbiV7500.NotifyPresented(_movie);
        BinkHostAudioBridgeV7241.NotifyPresentationStarted(_moviePath);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.4] first_visible_frame " +
            $"file='{Path.GetFileName(_moviePath)}' " +
            $"embedded_audio={EmbeddedAudioActive} sidecar_clock={_preferDemonSoulsSidecarClock}");
    }

    public bool TryGetPlaybackSeconds(
        out double seconds)
    {
        seconds = 0;

        if (_preferDemonSoulsSidecarClock &&
            BinkDeterministicWavePlayerV317152.
                TryGetProgressMilliseconds(
                    out var sidecarMilliseconds))
        {
            seconds =
                Math.Max(
                    0,
                    sidecarMilliseconds / 1000.0);
            return true;
        }

        return BinkNativeSdkAbiV7500.
            TryGetClockSeconds(
                _movie,
                out seconds);
    }

    internal void RequestSkip()
    {
        if (Volatile.Read(ref _disposed) == 0)
        {
            BinkNativeSdkAbiV7500.RequestSkip(
                _movie);
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(
                ref _disposed,
                1) != 0)
        {
            return;
        }

        BinkNativeSdkAbiV7500.Close(
            _movie);
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(_moviePath);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.0] closed " +
            $"file='{Path.GetFileName(_moviePath)}' " +
            $"decoded={Interlocked.Read(ref _decodedFrames)}");
    }

    private static string Sanitize(string value) =>
        value.Replace('\r', ' ').Replace('\n', ' ');
}
