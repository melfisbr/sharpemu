// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.InteropServices;
using System.Buffers.Binary;
using SharpEmu.Libs.VideoOut;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-side movie bridge for games that decode video inside their own
/// executable instead of going through an HLE decoder.
///
/// Such a game never imports libSceVideodec or sceAvPlayer, so no HLE export
/// can see its movie frames. Kernel file opens identify the active movie and
/// the presenter requests BGRA frames from <see cref="FfmpegVideoDecoder"/> —
/// the same decoder sceAvPlayer uses, so every format is handled in one place.
/// </summary>
internal static class HostMovieBridge
{
    private const uint MaxDimension = 16384;
    private const uint MaxHostVideoWidth = 1920;
    private const uint MaxHostVideoHeight = 1080;

    private static readonly string[] SelfDecodedMovieExtensions = [".bk2"];

    private static readonly object V34MovieProbeGate = new();
    private static readonly Dictionary<string, bool> V34MovieProbeCache =
        new(StringComparer.OrdinalIgnoreCase);
    private const int V34MovieProbeCacheLimit = 4096;

    private static bool V34IsSelfDecodedMovieByContent(string hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return false;
        }

        lock (V34MovieProbeGate)
        {
            if (V34MovieProbeCache.TryGetValue(hostPath, out var cached))
            {
                return cached;
            }
        }

        // TryReadBinkInfo already validates the KB2 magic and the core
        // Bink2 header fields used by this bridge.
        var isBink2 = TryReadBinkInfo(hostPath, out _);

        lock (V34MovieProbeGate)
        {
            if (V34MovieProbeCache.Count >= V34MovieProbeCacheLimit)
            {
                V34MovieProbeCache.Clear();
            }

            V34MovieProbeCache[hostPath] = isBink2;
        }

        if (isBink2 &&
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_TRACE_MOVIE_IO"),
                "1",
                StringComparison.Ordinal))
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] movie_candidate signature=KB2 path='" +
                hostPath + "'");
        }

        return isBink2;
    }

    private static bool IsSelfDecodedMovie(string hostPath)
    {
        foreach (var extension in SelfDecodedMovieExtensions)
        {
            if (hostPath.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        // SHARPEMU_V34_0_2_BINK_SIGNATURE
        // Some titles open Bink2 containers through opaque/non-.bk2 paths.
        // Reuse SharpEmu's existing validated KB2 parser instead of guessing by filename.
        if (V34IsSelfDecodedMovieByContent(hostPath))
        {
            return true;
        }

        return false;
    }

    private static readonly object Gate = new();
    private static string? _activePath;
    private static Bink2MovieInfo _activeInfo;
    private static byte[]? _frameBuffer;
    private static bool _frameBufferPresented;
    private static MediaFramePlayback? _playback;
    private static long _frameSerial;
    private static uint _presentationWidth = MaxHostVideoWidth;
    private static uint _presentationHeight = MaxHostVideoHeight;

    internal static bool IsHostPlaybackActive
    {
        get
        {
            lock (Gate)
            {
                return _playback is not null || _frameBuffer is not null;
            }
        }
    }

    internal static void SetPresentationSize(uint width, uint height)
    {
        if (width == 0 || height == 0)
        {
            return;
        }

        lock (Gate)
        {
            _presentationWidth = Math.Min(width, MaxHostVideoWidth);
            _presentationHeight = Math.Min(height, MaxHostVideoHeight);
        }

        TryStartConfiguredBootSequence();
    }

    /// <summary>
    /// Returns true only when movie skipping was explicitly requested. Without
    /// a host adapter the guest must be allowed to run the Bink implementation
    /// statically linked into its executable.
    /// </summary>
    internal static bool ShouldSkipGuestMovie(string hostPath) =>
        IsSelfDecodedMovie(hostPath) &&
        ResolveMode() == MovieMode.Skip;

    /// <summary>
    /// Starts or queues host decoding. Decoded frames are only exposed as a
    /// sampled guest texture; presentation and UI composition remain guest-owned.
    /// </summary>
    // V61.13.4_BINK2_NATURAL_FALLBACK
    private static int _naturalGuestMovieObservations;

    internal static bool ObserveGuestMovie(string hostPath) =>
        ObserveMovie(hostPath, naturalGuestRequest: true);

    private static bool ObserveMovie(string hostPath, bool naturalGuestRequest)
    {
        if (!IsSelfDecodedMovie(hostPath) || !File.Exists(hostPath))
        {
            return false;
        }

        if (naturalGuestRequest)
        {
            var observed = Interlocked.Increment(ref _naturalGuestMovieObservations);
            if (observed <= 4)
            {
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.natural_guest_movie_observed n={observed} " +
                    $"file='{Path.GetFileName(hostPath)}'");
            }
        }

        lock (Gate)
        {
            if (string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                return _playback is not null || _frameBuffer is not null;
            }

            var mode = ResolveMode();
            if (mode is MovieMode.Guest or MovieMode.Skip)
            {
                return false;
            }

            if (_playback is not null || _frameBuffer is not null)
            {
                if (PendingMoviePathSet.Add(hostPath))
                {
                    PendingMoviePaths.Enqueue(hostPath);
                    Console.Error.WriteLine(
                        "[LOADER][INFO] Bink2 bridge queued: " +
                        Path.GetFileName(hostPath));
                }
                return PendingMoviePathSet.Contains(hostPath);
            }

            AttachMovieLocked(hostPath, mode);
            return string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) &&
                   (_playback is not null || _frameBuffer is not null);
        }
    }

    internal static bool TryDecodeNextFrame(
        bool advanceClock,
        out byte[] pixels,
        out uint width,
        out uint height,
        out bool advanced,
        out long frameSerial,
        out string hostPath)
    {
        lock (Gate)
        {
            pixels = [];
            width = 0;
            height = 0;
            advanced = false;
            frameSerial = _frameSerial;
            hostPath = _activePath ?? string.Empty;

            if (_playback is not null)
            {
                if (!_playback.TryGetFrame(advanceClock, out pixels, out advanced))
                {
                    if (_playback.IsFinished)
                    {
                        var completedPath = _activePath;
                        var progress = _playback.PlaybackProgress;
                        CloseActiveLocked();
                        Console.Error.WriteLine(
                            "[LOADER][INFO] Bink2 bridge completed: " +
                            $"{Path.GetFileName(completedPath)} after " +
                            $"{progress.Seconds:F2}s at frame {progress.FrameIndex}");
                        AttachNextQueuedMovieLocked();
                    }
                    return false;
                }

                width = _activeInfo.Width;
                height = _activeInfo.Height;
                if (advanced)
                {
                    frameSerial = ++_frameSerial;
                }
                return true;
            }

            if (_frameBuffer is null)
            {
                return false;
            }

            pixels = _frameBuffer;
            width = _activeInfo.Width;
            height = _activeInfo.Height;
            advanced = !_frameBufferPresented;
            _frameBufferPresented = true;
            if (advanced)
            {
                frameSerial = ++_frameSerial;
            }
            return true;
        }
    }

    private static bool IsValid(Bink2MovieInfo info) =>
        info.Width > 0 && info.Height > 0 &&
        info.Width <= MaxDimension && info.Height <= MaxDimension &&
        (ulong)info.Width * info.Height * 4 <= int.MaxValue;

    private static int GetFrameBufferLength(Bink2MovieInfo info) =>
        checked((int)((ulong)info.Width * info.Height * 4));

    private static void AttachMovieLocked(string hostPath, MovieMode mode)
    {
        switch (mode)
        {
            case MovieMode.Dummy:
                AttachDummyMovieLocked(hostPath);
                return;
            case MovieMode.Nihav:
                AttachNihavMovieLocked(hostPath);
                return;
            case MovieMode.Ffmpeg:
                AttachFfmpegMovieLocked(hostPath);
                return;
            case MovieMode.Native:
                // Stock FFmpeg recognises the KB2 container but does not decode
                // Bink2 video. Prefer the optional NihAV backend for KB2 and
                // retain FFmpeg as the generic fallback for other host movies.
                if (AttachNihavMovieLocked(hostPath))
                {
                    return;
                }
                AttachFfmpegMovieLocked(hostPath);
                return;
        }
    }

    private static bool AttachNihavMovieLocked(string hostPath)
    {
        if (!NihavBink2Decoder.TryOpen(
                hostPath, _presentationWidth, _presentationHeight, out var source) ||
            source is null)
        {
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);
        if (!IsValid(info))
        {
            source.Dispose();
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 NIHAV bridge rejected invalid movie dimensions for '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        AttachPlaybackLocked(hostPath, info, source);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink2 NIHAV bridge attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + " @ " +
            info.FramesPerSecondNumerator + "/" + info.FramesPerSecondDenominator + " fps.");
        return true;
    }

    private static bool AttachFfmpegMovieLocked(string hostPath)
    {
        if (!FfmpegVideoDecoder.TryOpen(
                hostPath, _presentationWidth, _presentationHeight, out var source) ||
            source is null)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 bridge could not open movie '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);
        if (!IsValid(info))
        {
            source.Dispose();
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 bridge rejected invalid movie dimensions for '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        AttachPlaybackLocked(hostPath, info, source);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink2 FFmpeg bridge attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + " @ " +
            info.FramesPerSecondNumerator + "/" + info.FramesPerSecondDenominator + " fps.");
        return true;
    }

    private static MovieMode ResolveMode()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE");
        if (string.Equals(configured, "dummy", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Dummy;
        }

        if (string.Equals(configured, "native", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "auto", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Native;
        }

        if (string.Equals(configured, "nihav", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "bink2", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Nihav;
        }

        if (string.Equals(configured, "skip", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Skip;
        }

        if (string.Equals(configured, "guest", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Guest;
        }

        if (string.Equals(configured, "ffmpeg", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Ffmpeg;
        }

        // Native is the default. KB2 first tries the optional NihAV backend and
        // then the existing FFmpeg path. If neither host decoder is available,
        // the guest's statically linked movie code remains untouched.
        return MovieMode.Native;
    }

    private static void AttachDummyMovieLocked(string hostPath)
    {
        if (!TryReadBinkInfo(hostPath, out var info) || !IsValid(info))
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink dummy could not read movie header '" +
                Path.GetFileName(hostPath) + "'.");
            return;
        }

        CloseActiveLocked();
        _activePath = hostPath;
        _activeInfo = info;
        _frameBuffer = GC.AllocateUninitializedArray<byte>(GetFrameBufferLength(info));
        _frameBufferPresented = false;
        FillDummyFrame(_frameBuffer, info.Width, info.Height);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink dummy attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + ".");
    }

    private static void AttachPlaybackLocked(
        string hostPath,
        Bink2MovieInfo info,
        IMediaFrameDecoder decoder)
    {
        CloseActiveLocked();
        _activePath = hostPath;
        _activeInfo = info;
        _playback = new MediaFramePlayback(decoder);
    }

    internal static bool TryReadBinkInfo(string path, out Bink2MovieInfo info)
    {
        info = default;
        Span<byte> header = stackalloc byte[36];
        try
        {
            using var stream = File.OpenRead(path);
            stream.ReadExactly(header);
            if (!header[..3].SequenceEqual("KB2"u8))
            {
                return false;
            }

            info = new Bink2MovieInfo(
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x14, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x18, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x1C, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x20, 4)));
            return info.FramesPerSecondNumerator != 0 &&
                   info.FramesPerSecondDenominator != 0;
        }
        catch (Exception exception) when (exception is IOException or EndOfStreamException)
        {
            return false;
        }
    }

    private static void FillDummyFrame(byte[] pixels, uint width, uint height)
    {
        for (var y = 0u; y < height; y++)
        {
            for (var x = 0u; x < width; x++)
            {
                var offset = checked((int)(((ulong)y * width + x) * 4));
                var band = ((x / 96) + (y / 96)) & 1;
                pixels[offset] = band == 0 ? (byte)0x28 : (byte)0x18;
                pixels[offset + 1] = band == 0 ? (byte)0x18 : (byte)0x28;
                pixels[offset + 2] = 0x10;
                pixels[offset + 3] = 0xFF;
            }
        }
    }


    // V61.13_BINK2_NIHAV_DIRECT_BOOT
    // A title may initialise its statically linked Bink runtime long before it
    // opens the first movie. SHARPEMU_BINK_BOOT_SEQUENCE provides an opt-in
    // compatibility path that plays known boot movies directly through the
    // host presenter, then releases presentation back to the guest.
    private static int _configuredBootSequenceStarted;
    private static int _autoBootFallbackScheduled;
    private static bool _directPresentationActive;
    private static byte[]? _directPresentationFrame;
    private static uint _directPresentationFrameWidth;
    private static uint _directPresentationFrameHeight;
    private static long _directPresentationFrameSerial;
    private static Thread? _directPresentationThread;

    internal static bool IsDirectPresentationActive
    {
        get
        {
            lock (Gate)
            {
                return _directPresentationActive;
            }
        }
    }

    internal static bool TryGetDirectPresentation(
        out byte[] pixels,
        out uint width,
        out uint height,
        out long frameSerial)
    {
        lock (Gate)
        {
            pixels = [];
            width = 0;
            height = 0;
            frameSerial = _directPresentationFrameSerial;
            if (!_directPresentationActive || _directPresentationFrame is null)
            {
                return false;
            }

            pixels = _directPresentationFrame;
            width = _directPresentationFrameWidth;
            height = _directPresentationFrameHeight;
            return true;
        }
    }

    private static void TryStartConfiguredBootSequence()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_BOOT_SEQUENCE");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var explicitPaths = configured
                .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(Environment.ExpandEnvironmentVariables)
                .Where(static path => !string.IsNullOrWhiteSpace(path))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            TryStartBootSequenceThread(explicitPaths, "explicit", delayMilliseconds: 0);
            return;
        }

        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUTO_BOOT"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        // The host runtime already exports the /app0 root through this variable.
        // Auto fallback is intentionally conservative: it only activates when
        // BOTH standard PlayStation Studios / title intro assets are present.
        var app0 = Environment.GetEnvironmentVariable("SHARPEMU_APP0_DIR");
        if (string.IsNullOrWhiteSpace(app0) || !Directory.Exists(app0))
        {
            return;
        }

        var movieRoot = Path.Combine(app0, "movies");
        var autoPaths = new[]
        {
            Path.Combine(movieRoot, "ps_studios_logo.bk2"),
            Path.Combine(movieRoot, "logo_intro.bk2"),
        };
        if (autoPaths.Any(static path => !File.Exists(path)) ||
            autoPaths.Any(static path => !TryReadBinkInfo(path, out _)))
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _autoBootFallbackScheduled, 1, 0) != 0)
        {
            return;
        }

        var graceMilliseconds = 1500;
        if (int.TryParse(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS"),
                out var configuredGrace))
        {
            graceMilliseconds = Math.Clamp(configuredGrace, 0, 10_000);
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.auto_boot_discovered app0='{app0}' " +
            $"movies={autoPaths.Length} grace_ms={graceMilliseconds}");
        TryStartBootSequenceThread(autoPaths, "auto-app0", graceMilliseconds);
    }

    private static void TryStartBootSequenceThread(
        string[] paths,
        string source,
        int delayMilliseconds)
    {
        if (paths.Length == 0 ||
            Volatile.Read(ref _configuredBootSequenceStarted) != 0)
        {
            return;
        }

        _directPresentationThread = new Thread(() =>
        {
            if (delayMilliseconds > 0)
            {
                Thread.Sleep(delayMilliseconds);
            }

            if (source.StartsWith("auto", StringComparison.Ordinal) &&
                Volatile.Read(ref _naturalGuestMovieObservations) != 0)
            {
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.auto_boot_cancelled reason=natural-guest-open " +
                    $"observations={Volatile.Read(ref _naturalGuestMovieObservations)}");
                return;
            }

            if (Interlocked.CompareExchange(ref _configuredBootSequenceStarted, 1, 0) != 0)
            {
                return;
            }

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.boot_sequence_selected source={source} movies={paths.Length}");
            RunConfiguredBootSequence(paths);
        })
        {
            IsBackground = true,
            Name = "SharpEmu Bink2 boot presentation",
        };
        _directPresentationThread.Start();
    }

    private static void RunConfiguredBootSequence(string[] paths)
    {
        var attached = 0;
        lock (Gate)
        {
            _directPresentationActive = true;
            _directPresentationFrame = null;
            _directPresentationFrameWidth = 0;
            _directPresentationFrameHeight = 0;
            _directPresentationFrameSerial = 0;
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.direct_boot_started movies={paths.Length} " +
            $"mode={ResolveMode()}");

        foreach (var path in paths)
        {
            if (!File.Exists(path))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.direct_boot_missing path='" + path + "'");
                continue;
            }

            if (!TryReadBinkInfo(path, out _))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.direct_boot_not_bink2 path='" + path + "'");
                continue;
            }

            if (ObserveMovie(path, naturalGuestRequest: false))
            {
                attached++;
            }
        }

        if (attached == 0)
        {
            lock (Gate)
            {
                _directPresentationActive = false;
                _directPresentationFrame = null;
            }
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.direct_boot_no_decoder movies=0");
            return;
        }

        long presentedFrames = 0;
        try
        {
            while (true)
            {
                if (TryDecodeNextFrame(
                        advanceClock: true,
                        out var pixels,
                        out var width,
                        out var height,
                        out var advanced,
                        out var frameSerial,
                        out var hostPath))
                {
                    if (advanced)
                    {
                        var stableFrame = GC.AllocateUninitializedArray<byte>(pixels.Length);
                        Buffer.BlockCopy(pixels, 0, stableFrame, 0, pixels.Length);
                        lock (Gate)
                        {
                            _directPresentationFrame = stableFrame;
                            _directPresentationFrameWidth = width;
                            _directPresentationFrameHeight = height;
                            _directPresentationFrameSerial = frameSerial;
                        }

                        // V61.13.1: use the stable public host-frame submission seam
                        // instead of patching VulkanVideoPresenter internals. This keeps
                        // the Bink2 implementation compatible with newer presenter
                        // revisions while preserving all intervening GPU changes.
                        VulkanVideoPresenter.Submit(stableFrame, width, height);

                        presentedFrames++;
                        if (presentedFrames <= 3 || presentedFrames % 120 == 0)
                        {
                            Console.Error.WriteLine(
                                $"[LOADER][INFO] bink2.direct_frame n={presentedFrames} " +
                                $"serial={frameSerial} file='{Path.GetFileName(hostPath)}' " +
                                $"size={width}x{height}");
                        }
                    }

                    Thread.Sleep(1);
                    continue;
                }

                lock (Gate)
                {
                    if (_playback is null &&
                        _frameBuffer is null &&
                        PendingMoviePaths.Count == 0)
                    {
                        break;
                    }
                }

                Thread.Sleep(2);
            }
        }
        catch (Exception exception) when (
            exception is IOException or InvalidOperationException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.direct_boot_failed: " + exception.Message);
        }
        finally
        {
            lock (Gate)
            {
                _directPresentationActive = false;
                _directPresentationFrame = null;
                _directPresentationFrameWidth = 0;
                _directPresentationFrameHeight = 0;
                Monitor.PulseAll(Gate);
            }

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.direct_boot_completed frames={presentedFrames}; " +
                "guest presentation restored.");
        }
    }


    private static void CloseActiveLocked()
    {
        _playback?.Dispose();
        _playback = null;
        _activePath = null;
        _activeInfo = default;
        _frameBuffer = null;
        _frameBufferPresented = false;

        // Wake any guest _read() blocked in WaitForHostPlaybackToFinish: its
        // movie either just finished or is being pre-empted by a new attach.
        Monitor.PulseAll(Gate);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct Bink2MovieInfo
    {
        public readonly uint Width;
        public readonly uint Height;
        public readonly uint FramesPerSecondNumerator;
        public readonly uint FramesPerSecondDenominator;

        internal Bink2MovieInfo(
            uint width,
            uint height,
            uint framesPerSecondNumerator,
            uint framesPerSecondDenominator)
        {
            Width = width;
            Height = height;
            FramesPerSecondNumerator = framesPerSecondNumerator;
            FramesPerSecondDenominator = framesPerSecondDenominator;
        }
    }

    private enum MovieMode
    {
        Guest,
        Skip,
        Dummy,
        Native,
        Nihav,
        Ffmpeg,
    }

    private static readonly Queue<string> PendingMoviePaths = new();
    private static readonly HashSet<string> PendingMoviePathSet =
        new(StringComparer.OrdinalIgnoreCase);
    private static void AttachNextQueuedMovieLocked()
    {
        while (PendingMoviePaths.Count > 0)
        {
            var path = PendingMoviePaths.Dequeue();
            PendingMoviePathSet.Remove(path);
            if (!File.Exists(path))
            {
                continue;
            }

            AttachMovieLocked(path, ResolveMode());
            if (_playback is not null || _frameBuffer is not null)
            {
                return;
            }
        }
    }
    // Longest a guest _read() will block waiting for real host playback to
    // finish. A safety net, not a target: real movies finish well under
    // this. Bounds the damage if a movie fails to attach/decode after being
    // queued, so the guest thread doesn't hang forever.
    private const long MaxCompletionWaitMilliseconds = 5 * 60 * 1000;
    /// <summary>
    /// Blocks the calling (guest I/O) thread until the host has actually
    /// finished presenting <paramref name="hostPath"/> — either because it
    /// played through, or because something else took over the timeline.
    ///
    /// The completion shim tells the guest's own Bink header parse "this
    /// movie is one frame and already done" so its native decoder never
    /// blocks the guest on real per-frame work. Without this wait, that lie
    /// lands the instant the guest reads the header, so guest-side game
    /// logic races far ahead of whatever the host is still showing on
    /// screen: pressing a button lands on the (already-advanced) guest
    /// state, but the video visibly keeps playing, and any real-time-gated
    /// trigger later in the guest's own flow can fire against a clock that
    /// no longer matches wall time. Gating the "done" read on real host
    /// completion keeps guest pacing and on-screen playback in lockstep.
    /// </summary>
    internal static void WaitForHostPlaybackToFinish(string hostPath)
    {
        var deadline = Environment.TickCount64 + MaxCompletionWaitMilliseconds;
        lock (Gate)
        {
            while (IsTrackedLocked(hostPath))
            {
                var remaining = deadline - Environment.TickCount64;
                if (remaining <= 0)
                {
                    Console.Error.WriteLine(
                        "[LOADER][WARN] Bink2 bridge completion wait timed out for '" +
                        Path.GetFileName(hostPath) + "'.");
                    return;
                }

                Monitor.Wait(Gate, (int)Math.Min(remaining, 200));
            }
        }
    }

    private static bool IsTrackedLocked(string hostPath) =>
        string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) ||
        PendingMoviePathSet.Contains(hostPath);

    internal static bool TryTakeOverGuestMovie(
        string hostPath,
        out BinkGuestCompletionShim completionShim,
        out bool observed)
    {
        completionShim = default;
        observed = ObserveGuestMovie(hostPath);

        // Keep the real header visible so the guest creates its movie surface
        // and draw. Host-decoded pixels replace that sampled image later; a
        // one-frame completion shim would finish before the descriptor exists.
        return false;
    }

    internal static void NotifyGuestMovieClosed(string hostPath)
    {
        lock (Gate)
        {
            if (PendingMoviePathSet.Remove(hostPath))
            {
                var retained = PendingMoviePaths
                    .Where(path => !string.Equals(
                        path,
                        hostPath,
                        StringComparison.OrdinalIgnoreCase))
                    .ToArray();
                PendingMoviePaths.Clear();
                foreach (var path in retained)
                {
                    PendingMoviePaths.Enqueue(path);
                }
            }

            if (!string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                Monitor.PulseAll(Gate);
                return;
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] Bink2 bridge stopped by guest close: " +
                Path.GetFileName(hostPath));
            CloseActiveLocked();
            AttachNextQueuedMovieLocked();
        }
    }

    internal static bool TryReadGuestCompletionShim(
        string hostPath,
        out BinkGuestCompletionShim completionShim)
    {
        completionShim = default;
        Span<byte> header = stackalloc byte[48];
        try
        {
            using var stream = File.OpenRead(hostPath);
            stream.ReadExactly(header);
            if (!header[..3].SequenceEqual("KB2"u8))
            {
                return false;
            }

            var frameCount = BinaryPrimitives.ReadUInt32LittleEndian(header[8..12]);
            var audioTrackCount = BinaryPrimitives.ReadUInt32LittleEndian(header[40..44]);
            if (frameCount < 2 || audioTrackCount > 256)
            {
                return false;
            }

            var revision = header[3];
            var frameIndexOffset = 44L + checked(12L * audioTrackCount);
            if (revision == (byte)'m')
            {
                frameIndexOffset += 16;
            }
            else if (revision is (byte)'i' or (byte)'j' or (byte)'k' or (byte)'n')
            {
                frameIndexOffset += 4;
            }

            Span<byte> frameOffsets = stackalloc byte[8];
            stream.Position = frameIndexOffset;
            stream.ReadExactly(frameOffsets);
            var firstFrameOffset = BinaryPrimitives.ReadUInt32LittleEndian(frameOffsets[..4]) & ~1u;
            var secondFrameOffset = BinaryPrimitives.ReadUInt32LittleEndian(frameOffsets[4..]) & ~1u;
            if (firstFrameOffset < frameIndexOffset + 8 ||
                secondFrameOffset <= firstFrameOffset ||
                secondFrameOffset > stream.Length)
            {
                return false;
            }

            completionShim = new BinkGuestCompletionShim(
                secondFrameOffset - 8,
                secondFrameOffset - firstFrameOffset);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or EndOfStreamException or OverflowException)
        {
            return false;
        }
    }

    internal readonly struct BinkGuestCompletionShim
    {
        private readonly uint _fileSizeMinusHeader;
        private readonly uint _largestFrameSize;

        internal BinkGuestCompletionShim(uint fileSizeMinusHeader, uint largestFrameSize)
        {
            _fileSizeMinusHeader = fileSizeMinusHeader;
            _largestFrameSize = largestFrameSize;
        }

        /// <summary>
        /// Rewrites the frame-count/size fields the guest's own Bink header
        /// parse reads, if this read covers them. Returns true when the
        /// NumFrames field (the field that tells the guest "this movie is
        /// done") was in range, so the caller can gate that specific read on
        /// the host's real playback actually finishing first.
        /// </summary>
        internal bool Patch(long fileOffset, Span<byte> bytes)
        {
            PatchUInt32(fileOffset, bytes, 4, _fileSizeMinusHeader);
            var touchedCompletionField = PatchUInt32(fileOffset, bytes, 8, 1);
            PatchUInt32(fileOffset, bytes, 12, _largestFrameSize);
            return touchedCompletionField;
        }

        private static bool PatchUInt32(
            long fileOffset,
            Span<byte> bytes,
            long fieldOffset,
            uint value)
        {
            var relativeOffset = fieldOffset - fileOffset;
            if (relativeOffset < 0 || relativeOffset + sizeof(uint) > bytes.Length)
            {
                return false;
            }

            BinaryPrimitives.WriteUInt32LittleEndian(
                bytes.Slice((int)relativeOffset, sizeof(uint)),
                value);
            return true;
        }
    }
}
