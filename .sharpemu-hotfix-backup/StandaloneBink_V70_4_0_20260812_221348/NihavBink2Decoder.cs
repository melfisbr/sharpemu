// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Bink2/KB2 host decoder backed by the external NihAV decoder tool.
///
/// NihAV is intentionally not linked into SharpEmu and is not redistributed by
/// this source file. The optional executable is discovered under
/// <c>plugins\bink2\nihav-tool.exe</c> or via SHARPEMU_NIHAV_TOOL. Keeping the
/// codec in a child process gives us natural backpressure and isolates malformed
/// movie data from the emulator process.
///
/// The tool writes PPM for RGB or PGMYUV for YUV frames. This adapter decodes
/// short time slices, consumes those images, converts them to BGRA and deletes
/// each slice before moving to the next one. Slice decoding bounds temporary
/// disk usage instead of allowing a whole 4K movie to be dumped at once.
/// </summary>
internal sealed class NihavBink2Decoder : IMediaFrameDecoder
{
    private const int HeaderProbeLength = 48;
    private const int DecoderTimeoutMilliseconds = 120_000;
    private const double DefaultChunkSeconds = 1.0;
    private const double MinimumChunkSeconds = 0.25;
    private const double MaximumChunkSeconds = 4.0;
    private const int MaxTraceLength = 4096;

    private readonly string _moviePath;
    private readonly string _toolPath;
    private readonly string _sessionRoot;
    private readonly uint _sourceWidth;
    private readonly uint _sourceHeight;
    private readonly uint _frameCount;
    private readonly bool _trace;
    private readonly bool _swapUv;
    private readonly bool _fullRange;
    private readonly bool _singlePass;
    private readonly bool _bt709;
    private readonly int _prefetchDepth;
    private readonly bool _streamSinglePass;
    private readonly bool _autoRange;
    private readonly int[] _sourceXByOutput;
    private readonly int[] _chromaXByOutput;

    // [V61.13.17][FAST_YUV_TABLES]
    private readonly int[] _sourceYByOutput;
    private readonly int[] _chromaYByOutput;
    private readonly int[] _yLimitedTable;
    private readonly int[] _yFullTable;
    private readonly int[] _rFromVTable;
    private readonly int[] _gFromUTable;
    private readonly int[] _gFromVTable;
    private readonly int[] _bFromUTable;

    // [V61.13.24][BINK2_FULL_RANGE_CHROMA]
    // Bink 2 uses full-range color values. The previous LUT path switched
    // luma to 0..255 but accidentally kept studio-range chroma coefficients.
    // Keep separate full-range chroma contribution tables.
    private readonly int[] _rFromVFullTable;
    private readonly int[] _gFromUFullTable;
    private readonly int[] _gFromVFullTable;
    private readonly int[] _bFromUFullTable;

    private readonly double _chunkSeconds;
    private readonly Dictionary<int, Task<byte[]?>> _prefetchedFrames = [];
    private Process? _streamProcess;
    private Task<string>? _streamStdoutTask;
    private Task<string>? _streamStderrTask;
    private string? _streamDirectory;

    // [V61.13.23][FFMPEG_SWSCALE_COLOR]
    // Use one persistent swscale process for YUV420 -> BGRA when ffmpeg is
    // available. This replaces the scalar/LUT color path with FFmpeg's
    // optimized chroma reconstruction and Rec.709 range conversion, while
    // retaining the existing LUT converter as a safe fallback.
    private Process? _colorProcess;
    private Stream? _colorInput;
    private Stream? _colorOutput;
    private Task<string>? _colorStderrTask;
    private byte[]? _colorOutputBuffer;
    private bool _colorConverterDisabled;
    private long _streamLastOrdinal = long.MinValue;
    private long _streamStartTick;

    // [V61.13.24][STREAM_WALLCLOCK_CATCHUP]
    // When NihAV initially falls behind and later produces a large backlog,
    // consume the frame nearest the real movie clock instead of presenting
    // every stale frame sequentially.
    private long _streamPlaybackStartTick;
    private long _streamFirstOrdinal = long.MinValue;
    private long _streamSkippedFrames;

    // [V61.13.25][REALTIME_MOVIE_DEADLINE]
    // Wall-clock playback must not become slow motion just because the external
    // Bink2 decoder cannot produce every 4K frame at 30 fps. The presentation
    // layer may drop stale frames, and the movie ends at its nominal duration.
    private long _streamRealtimeDeadlineTick;
    private bool _streamRealtimeDeadlineLogged;

    // [V61.13.16][REUSABLE_SOURCE_BUFFER]
    // File.ReadAllBytes allocated ~12.4 MB on the LOH for every 4K PGMYUV
    // frame. Reuse one grow-only source buffer for the decoder lifetime.
    private byte[]? _sourceFileBuffer;

    // [V70.1.0][PGMYUV_SIDE_BY_SIDE_CHROMA]
    // NihAV PGMYUV stores U and V side-by-side in the rows below Y, not as
    // two contiguous planar blocks. Repack once into reusable I420 storage so
    // both the LUT converter and optional FFmpeg converter consume true planes.
    private byte[]? _pgmPlanarBuffer;
    private bool? _detectedFullRange;
    private long _readTicks;
    private long _convertTicks;
    private long _waitTicks;
    private long _perfFrames;

    private List<string> _chunkFrames = [];
    private int _chunkFrameIndex;
    private uint _deliveredFrames;
    private double _nextChunkStartSeconds;
    private int _chunkIndex;
    private int _disposed;

    private NihavBink2Decoder(
        string moviePath,
        string toolPath,
        string sessionRoot,
        uint sourceWidth,
        uint sourceHeight,
        uint frameCount,
        uint outputWidth,
        uint outputHeight,
        uint framesPerSecondNumerator,
        uint framesPerSecondDenominator)
    {
        _moviePath = moviePath;
        _toolPath = toolPath;
        _sessionRoot = sessionRoot;
        _sourceWidth = sourceWidth;
        _sourceHeight = sourceHeight;
        _frameCount = frameCount;
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath);
        Width = outputWidth;
        Height = outputHeight;
        FramesPerSecondNumerator = framesPerSecondNumerator;
        FramesPerSecondDenominator = framesPerSecondDenominator;
        _trace = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_LOG_BINK2"),
            "1",
            StringComparison.Ordinal);
        _swapUv = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_UV_SWAP"),
            "1",
            StringComparison.Ordinal);
        _fullRange = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_YUV_FULL_RANGE"),
            "1",
            StringComparison.Ordinal);

        // [V61.13.14][NIHAV_SINGLE_PASS]
        // KB2 seeking is not reliable in the external decoder used by this
        // compatibility path. The old 1-second slicing repeatedly restarted
        // from the beginning of the movie. Single-pass mode decodes the whole
        // BK2 once and then consumes the generated frames sequentially.
        _singlePass = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_SINGLE_PASS"),
            "1",
            StringComparison.Ordinal);

        // [V61.13.14][BT709]
        // HD/4K Bink material is treated as Rec.709 by default. Set
        // SHARPEMU_NIHAV_COLOR_MATRIX=601 to restore the legacy matrix.
        var colorMatrix =
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_COLOR_MATRIX");
        _bt709 = !string.Equals(
            colorMatrix,
            "601",
            StringComparison.OrdinalIgnoreCase) &&
            _sourceWidth >= 1280;

        // [V61.13.14][BOUNDED_PREFETCH]
        // Single-pass removed the decoder rewind, but V61.13.13 still converted
        // one 4K PGMYUV frame synchronously on the presentation thread. That
        // produced only ~10-12 new frames/s and made the display hold/repeat
        // frames. Pre-convert a small ordered window on worker threads.
        _prefetchDepth = ResolvePrefetchDepth();

        // [V61.13.15][STREAMING_SINGLE_PASS]
        // V61.13.14.1 decoded an entire 4K BK2 to hundreds of PGMYUV files
        // before the first frame was consumed. That creates multi-GB temporary
        // output and lets Windows file cache / the helper process grow sharply.
        // Streaming mode keeps one NIHAV process alive but consumes and deletes
        // each completed frame while the process is still decoding.
        _streamSinglePass =
            _singlePass &&
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_STREAMING_SINGLE_PASS"),
                "0",
                StringComparison.Ordinal);

        // [V61.13.16][FAST_SCALE_MAP]
        // Avoid two integer divisions for every output pixel.
        _sourceXByOutput = BuildScaleMap(
            checked((int)Width),
            checked((int)_sourceWidth));
        _chromaXByOutput = BuildChromaScaleMap(
            _sourceXByOutput);
        _sourceYByOutput = BuildScaleMap(
            checked((int)Height),
            checked((int)_sourceHeight));
        _chromaYByOutput = BuildChromaScaleMap(
            _sourceYByOutput);

        (_yLimitedTable,
         _yFullTable,
         _rFromVTable,
         _gFromUTable,
         _gFromVTable,
         _bFromUTable) = BuildYuvTables(_bt709);

        (_rFromVFullTable,
         _gFromUFullTable,
         _gFromVFullTable,
         _bFromUFullTable) = BuildFullRangeChromaTables(_bt709);

        _autoRange = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_AUTO_RANGE"),
            "1",
            StringComparison.Ordinal);

        _chunkSeconds = ResolveChunkSeconds();
    }

    public uint Width { get; }

    public uint Height { get; }

    public uint FramesPerSecondNumerator { get; }

    public uint FramesPerSecondDenominator { get; }

    private static double ResolveChunkSeconds()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_CHUNK_SECONDS");
        if (double.TryParse(
                configured,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var seconds))
        {
            return Math.Clamp(seconds, MinimumChunkSeconds, MaximumChunkSeconds);
        }

        return DefaultChunkSeconds;
    }

    private static int ResolvePrefetchDepth()
    {
        var configured =
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_PREFETCH_FRAMES");
        return int.TryParse(
                configured,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var depth)
            ? Math.Clamp(depth, 0, 8)
            : 4;
    }

    internal static bool TryOpen(
        string path,
        uint maximumWidth,
        uint maximumHeight,
        out NihavBink2Decoder? decoder)
    {
        decoder = null;
        if (!TryReadHeader(
                path,
                out var sourceWidth,
                out var sourceHeight,
                out var frameCount,
                out var frameRateNumerator,
                out var frameRateDenominator))
        {
            return false;
        }

        var toolPath = FindToolPath();
        if (toolPath is null)
        {
            LogMissingToolOnce();
            return false;
        }

        // [V61.13.17][OUTPUT_CAP]
        // 4K Bink source is decoded by NIHAV at native resolution, but the
        // presenter does not need a 1280x720 CPU conversion while the guest is
        // simultaneously booting. A bounded compatibility output materially
        // reduces YUV->BGRA work and upload bandwidth without touching source
        // timing or frame count.
        var effectiveMaximumWidth = maximumWidth;
        var effectiveMaximumHeight = maximumHeight;
        if (uint.TryParse(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_WIDTH"),
                out var configuredMaxWidth) &&
            configuredMaxWidth >= 320)
        {
            effectiveMaximumWidth = Math.Min(
                effectiveMaximumWidth,
                configuredMaxWidth);
        }
        if (uint.TryParse(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT"),
                out var configuredMaxHeight) &&
            configuredMaxHeight >= 180)
        {
            effectiveMaximumHeight = Math.Min(
                effectiveMaximumHeight,
                configuredMaxHeight);
        }

        var (outputWidth, outputHeight) = FitWithin(
            sourceWidth,
            sourceHeight,
            effectiveMaximumWidth,
            effectiveMaximumHeight);
        var sessionRoot = Path.Combine(
            Path.GetTempPath(),
            "SharpEmu",
            "Bink2",
            Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture));
        Directory.CreateDirectory(sessionRoot);

        var candidate = new NihavBink2Decoder(
            path,
            toolPath,
            sessionRoot,
            sourceWidth,
            sourceHeight,
            frameCount,
            outputWidth,
            outputHeight,
            frameRateNumerator,
            frameRateDenominator);
        try
        {
            // [V61.13.15][STREAM_OPEN]
            // In streaming single-pass mode, do not wait for nihav-tool to dump
            // the whole movie before attaching the bridge. Start one persistent
            // process and wait only until its first complete frame becomes
            // available.
            if (candidate._streamSinglePass)
            {
                if (!candidate.StartStreamingSinglePass() ||
                    !candidate.WaitForFirstStreamingFrame())
                {
                    candidate.Dispose();
                    return false;
                }
            }
            else if (!candidate.DecodeNextChunk())
            {
                candidate.Dispose();
                return false;
            }

            decoder = candidate;
            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.nihav_ready file='{Path.GetFileName(path)}' " +
                $"source={sourceWidth}x{sourceHeight} output={outputWidth}x{outputHeight} " +
                $"frames={frameCount} fps={frameRateNumerator}/{frameRateDenominator} " +
                $"chunk={candidate._chunkSeconds:F2}s " +
                $"single_pass={candidate._singlePass} " +
                $"matrix={(candidate._bt709 ? "BT709" : "BT601")} " +
                $"uv_swap={candidate._swapUv} " +
                $"prefetch={(candidate._streamSinglePass ? 0 : candidate._prefetchDepth)} " +
                $"streaming={candidate._streamSinglePass} " +
                $"auto_range={candidate._autoRange} " +
                $"range={(candidate._fullRange ? "full" : candidate._autoRange ? "auto" : "limited")} " +
                $"lut=True output_cap={effectiveMaximumWidth}x{effectiveMaximumHeight} " +
                $"tool='{toolPath}'");
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or InvalidOperationException or
            UnauthorizedAccessException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 NIHAV decoder initialization failed: " +
                exception.Message);
            candidate.Dispose();
            return false;
        }
    }

    public bool TryDecodeNextFrame(Span<byte> destination)
    {
        ObjectDisposedException.ThrowIf(
            Volatile.Read(ref _disposed) != 0,
            this);

        var requiredBytes = checked((int)((ulong)Width * Height * 4));
        if (destination.Length < requiredBytes)
        {
            throw new InvalidOperationException(
                $"Bink2 output buffer is too small ({destination.Length} < {requiredBytes}).");
        }

        if (_streamSinglePass)
        {
            return TryDecodeNextStreamingFrame(destination[..requiredBytes]);
        }

        while (_frameCount == 0 || _deliveredFrames < _frameCount)
        {
            if (_chunkFrameIndex >= _chunkFrames.Count)
            {
                if (!DecodeNextChunk())
                {
                    return false;
                }
            }

            while (_chunkFrameIndex < _chunkFrames.Count)
            {
                var frameIndex = _chunkFrameIndex++;
                var framePath = _chunkFrames[frameIndex];

                bool decoded;
                if (_singlePass && _prefetchDepth > 0)
                {
                    // [V61.13.14][PREFETCH_CONSUME]
                    PrimePrefetch();

                    if (!_prefetchedFrames.Remove(frameIndex, out var frameTask))
                    {
                        frameTask = Task.Run(() => ReadFrameOwned(framePath));
                    }

                    var owned = frameTask.GetAwaiter().GetResult();
                    PrimePrefetch();

                    decoded = owned is not null;
                    if (owned is not null)
                    {
                        owned.AsSpan().CopyTo(destination[..requiredBytes]);
                    }
                }
                else
                {
                    decoded = TryReadFrame(framePath, destination[..requiredBytes]);
                }

                if (!decoded)
                {
                    TryDelete(framePath);
                    continue;
                }

                _deliveredFrames++;
                TryDelete(framePath);
                if (_trace &&
                    (_deliveredFrames <= 3 || _deliveredFrames % 120 == 0))
                {
                    Console.Error.WriteLine(
                        $"[LOADER][TRACE] bink2.nihav_frame n={_deliveredFrames} " +
                        $"file='{Path.GetFileName(_moviePath)}' size={Width}x{Height}");
                }
                return true;
            }
        }

        return false;
    }

    // [V61.13.15][STREAMING_METHODS]
    private bool StartStreamingSinglePass()
    {
        if (_streamProcess is not null)
        {
            return true;
        }

        CleanupConsumedChunk();

        var totalDurationSeconds = _frameCount == 0
            ? double.PositiveInfinity
            : (double)_frameCount * FramesPerSecondDenominator /
              FramesPerSecondNumerator;

        var directory = Path.Combine(_sessionRoot, "stream");
        Directory.CreateDirectory(directory);
        var prefix = Path.Combine(directory, "frame_");

        var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = _toolPath,
            WorkingDirectory = directory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        process.StartInfo.ArgumentList.Add("-an");
        process.StartInfo.ArgumentList.Add("-nm=count");
        process.StartInfo.ArgumentList.Add("-vpfx");
        process.StartInfo.ArgumentList.Add(prefix);
        process.StartInfo.ArgumentList.Add("-ignerr");
        process.StartInfo.ArgumentList.Add(_moviePath);
        if (!double.IsPositiveInfinity(totalDurationSeconds))
        {
            process.StartInfo.ArgumentList.Add(FormatTime(totalDurationSeconds));
        }

        if (_trace)
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] bink2.nihav_stream_start " +
                $"duration={totalDurationSeconds:F3}s " +
                $"file='{Path.GetFileName(_moviePath)}'");
        }

        if (!process.Start())
        {
            process.Dispose();
            return false;
        }

        try
        {
            // [V61.13.17][NIHAV_PRIORITY]
            // V61.13.15 intentionally lowered NIHAV priority, but the measured
            // wait_avg_ms showed producer starvation during ps_studios_logo.
            // When cinematic GPU throttling is enabled, give the decoder normal
            // scheduling priority and throttle the competing guest GPU producer
            // instead.
            var priorityMode =
                Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_FAST_PRIORITY");
            process.PriorityClass = priorityMode switch
            {
                "2" => ProcessPriorityClass.AboveNormal,
                "1" => ProcessPriorityClass.Normal,
                _ => ProcessPriorityClass.BelowNormal,
            };
        }
        catch (InvalidOperationException)
        {
        }

        _streamProcess = process;
        _streamStdoutTask = process.StandardOutput.ReadToEndAsync();
        _streamStderrTask = process.StandardError.ReadToEndAsync();
        _streamDirectory = directory;
        _streamLastOrdinal = long.MinValue;
        _streamStartTick = Stopwatch.GetTimestamp();
        _streamPlaybackStartTick = 0;
        _streamFirstOrdinal = long.MinValue;
        _streamSkippedFrames = 0;
        _streamRealtimeDeadlineTick = 0;
        _streamRealtimeDeadlineLogged = false;

        return true;
    }

    private bool WaitForFirstStreamingFrame()
    {
        var deadline = Stopwatch.GetTimestamp() +
            (long)(Stopwatch.Frequency * 15.0);

        while (Stopwatch.GetTimestamp() < deadline)
        {
            if (FindNextStreamingFrame() is not null)
            {
                return true;
            }

            if (StreamingProcessExited())
            {
                return FindNextStreamingFrame() is not null;
            }

            Thread.Sleep(2);
        }

        return false;
    }

    private bool TryDecodeNextStreamingFrame(Span<byte> destination)
    {
        var waitStart = Stopwatch.GetTimestamp();

        if (TryFinishStreamingAtRealtimeDeadline())
        {
            return false;
        }

        if (_frameCount != 0 && _deliveredFrames >= _frameCount)
        {
            CompleteStreamingProcess();
            return false;
        }

        var deadline = Stopwatch.GetTimestamp() +
            (long)(Stopwatch.Frequency * 10.0);

        while (Stopwatch.GetTimestamp() < deadline)
        {
            if (TryFinishStreamingAtRealtimeDeadline())
            {
                return false;
            }

            var framePath = FindStreamingFrameForClock(out var skipped);
            if (framePath is not null)
            {
                var ordinal = ExtractOrdinal(framePath);
                if (skipped > 0)
                {
                    _streamSkippedFrames += skipped;
                    if (_trace || _streamSkippedFrames <= 8 ||
                        (_streamSkippedFrames & (_streamSkippedFrames - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[LOADER][INFO] bink2.clock_catchup " +
                            $"file='{Path.GetFileName(_moviePath)}' " +
                            $"skip={skipped} total_skipped={_streamSkippedFrames} " +
                            $"ordinal={ordinal}");
                    }
                }

                // A newly-created PGM/PPM can be visible in the directory
                // before nihav-tool has finished writing it. Do not delete or
                // advance the ordinal until the complete frame parses.
                _waitTicks += Stopwatch.GetTimestamp() - waitStart;
                if (TryReadFrame(framePath, destination))
                {
                    _streamLastOrdinal = ordinal;
                    if (_streamPlaybackStartTick == 0)
                    {
                        _streamPlaybackStartTick = Stopwatch.GetTimestamp();
                        _streamFirstOrdinal = ordinal;
                        ArmRealtimeMovieDeadline();
                    }
                    _deliveredFrames++;
                    TryDelete(framePath);
                    LogPerfIfNeeded();

                    if (_trace &&
                        (_deliveredFrames <= 3 || _deliveredFrames % 120 == 0))
                    {
                        Console.Error.WriteLine(
                            $"[LOADER][TRACE] bink2.nihav_stream_frame " +
                            $"n={_deliveredFrames} ordinal={ordinal} " +
                            $"file='{Path.GetFileName(_moviePath)}'");
                    }

                    return true;
                }

                Thread.Sleep(1);
                continue;
            }

            if (StreamingProcessExited())
            {
                // One final directory scan catches a file that became visible
                // at process shutdown.
                framePath = FindNextStreamingFrame();
                if (framePath is not null)
                {
                    _waitTicks += Stopwatch.GetTimestamp() - waitStart;
                }

                if (framePath is not null &&
                    TryReadFrame(framePath, destination))
                {
                    _streamLastOrdinal = ExtractOrdinal(framePath);
                    if (_streamPlaybackStartTick == 0)
                    {
                        _streamPlaybackStartTick = Stopwatch.GetTimestamp();
                        _streamFirstOrdinal = _streamLastOrdinal;
                        ArmRealtimeMovieDeadline();
                    }
                    _deliveredFrames++;
                    TryDelete(framePath);
                    LogPerfIfNeeded();
                    return true;
                }

                CompleteStreamingProcess();
                return false;
            }

            Thread.Sleep(2);
        }

        if (_trace)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.nihav_stream_frame_timeout " +
                $"delivered={_deliveredFrames} " +
                $"file='{Path.GetFileName(_moviePath)}'");
        }

        return false;
    }

    private void ArmRealtimeMovieDeadline()
    {
        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_REALTIME_DEADLINE") != "1" ||
            _frameCount == 0 ||
            FramesPerSecondNumerator == 0 ||
            _streamPlaybackStartTick == 0)
        {
            return;
        }

        var durationTicks = (long)Math.Ceiling(
            _frameCount *
            (double)FramesPerSecondDenominator *
            Stopwatch.Frequency /
            FramesPerSecondNumerator);

        // One frame of tolerance avoids ending before the nominal last display
        // interval because of timer quantization.
        var frameTicks = (long)Math.Ceiling(
            FramesPerSecondDenominator *
            (double)Stopwatch.Frequency /
            FramesPerSecondNumerator);

        _streamRealtimeDeadlineTick =
            _streamPlaybackStartTick + durationTicks + frameTicks;
    }

    private bool TryFinishStreamingAtRealtimeDeadline()
    {
        var deadline = _streamRealtimeDeadlineTick;
        if (deadline <= 0 || Stopwatch.GetTimestamp() < deadline)
        {
            return false;
        }

        if (!_streamRealtimeDeadlineLogged)
        {
            _streamRealtimeDeadlineLogged = true;

            var elapsedMs =
                (Stopwatch.GetTimestamp() - _streamPlaybackStartTick) *
                1000.0 /
                Stopwatch.Frequency;
            var nominalMs =
                _frameCount *
                (double)FramesPerSecondDenominator *
                1000.0 /
                Math.Max(1u, FramesPerSecondNumerator);

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.realtime_deadline " +
                $"file='{Path.GetFileName(_moviePath)}' " +
                $"elapsed_ms={elapsedMs:F2} nominal_ms={nominalMs:F2} " +
                $"delivered={_deliveredFrames} " +
                $"clock_skipped={_streamSkippedFrames}");
        }

        StopStreamingProcess();

        var directory = _streamDirectory;
        if (!string.IsNullOrWhiteSpace(directory))
        {
            TryDeleteDirectory(directory);
        }

        return true;
    }

    private string? FindStreamingFrameForClock(out int skipped)
    {
        skipped = 0;
        var directory = _streamDirectory;
        if (string.IsNullOrWhiteSpace(directory) ||
            !Directory.Exists(directory))
        {
            return null;
        }

        var candidates = new List<(string Path, long Ordinal)>();
        try
        {
            foreach (var path in Directory.EnumerateFiles(directory))
            {
                if (!LooksLikePortableAnyMap(path))
                {
                    continue;
                }

                var ordinal = ExtractOrdinal(path);
                if (ordinal > _streamLastOrdinal)
                {
                    candidates.Add((path, ordinal));
                }
            }
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        if (candidates.Count == 0)
        {
            return null;
        }

        candidates.Sort(static (left, right) =>
            left.Ordinal.CompareTo(right.Ordinal));

        // First presented frame establishes time zero. This preserves the
        // beginning of each logo even when the external decoder has startup
        // latency. After that, stale backlog is skipped to stay near 30 fps.
        if (_streamPlaybackStartTick == 0 ||
            _streamFirstOrdinal == long.MinValue)
        {
            return candidates[0].Path;
        }

        var elapsedTicks =
            Stopwatch.GetTimestamp() - _streamPlaybackStartTick;
        var elapsedFrames = (long)Math.Floor(
            (double)elapsedTicks *
            FramesPerSecondNumerator /
            (Stopwatch.Frequency * (double)FramesPerSecondDenominator));

        var targetOrdinal =
            _streamFirstOrdinal + Math.Max(1L, elapsedFrames);

        var selectedIndex = 0;
        for (var index = 0; index < candidates.Count; index++)
        {
            if (candidates[index].Ordinal > targetOrdinal)
            {
                break;
            }

            selectedIndex = index;
        }

        // If producer output is ahead of the real movie clock, preserve future
        // frames. Delete only stale frames that the clock has already passed.
        for (var index = 0; index < selectedIndex; index++)
        {
            TryDelete(candidates[index].Path);
            skipped++;
        }

        return candidates[selectedIndex].Path;
    }

    private string? FindNextStreamingFrame()
    {
        var directory = _streamDirectory;
        if (string.IsNullOrWhiteSpace(directory) ||
            !Directory.Exists(directory))
        {
            return null;
        }

        string? bestPath = null;
        var bestOrdinal = long.MaxValue;

        try
        {
            foreach (var path in Directory.EnumerateFiles(directory))
            {
                if (!LooksLikePortableAnyMap(path))
                {
                    continue;
                }

                var ordinal = ExtractOrdinal(path);
                if (ordinal <= _streamLastOrdinal ||
                    ordinal >= bestOrdinal)
                {
                    continue;
                }

                bestOrdinal = ordinal;
                bestPath = path;
            }
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        return bestPath;
    }

    private bool StreamingProcessExited()
    {
        var process = _streamProcess;
        if (process is null)
        {
            return true;
        }

        try
        {
            return process.HasExited;
        }
        catch (InvalidOperationException)
        {
            return true;
        }
    }

    private void CompleteStreamingProcess()
    {
        var process = _streamProcess;
        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                return;
            }

            var stdout = _streamStdoutTask?.GetAwaiter().GetResult() ?? string.Empty;
            var stderr = _streamStderrTask?.GetAwaiter().GetResult() ?? string.Empty;

            if (_trace && process.ExitCode != 0)
            {
                Console.Error.WriteLine(
                    $"[LOADER][TRACE] bink2.nihav_stream_exit " +
                    $"exit={process.ExitCode} delivered={_deliveredFrames} " +
                    $"detail='{Truncate(FirstNonEmpty(stderr, stdout), MaxTraceLength)}'");
            }
        }
        catch (InvalidOperationException)
        {
        }
        finally
        {
            process.Dispose();
            _streamProcess = null;
            _streamStdoutTask = null;
            _streamStderrTask = null;
        }
    }

    private void StopStreamingProcess()
    {
        var process = _streamProcess;
        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5_000);
            }
        }
        catch (InvalidOperationException)
        {
        }
        finally
        {
            try
            {
                process.Dispose();
            }
            catch (InvalidOperationException)
            {
            }

            _streamProcess = null;
            _streamStdoutTask = null;
            _streamStderrTask = null;
        }
    }

    private bool DecodeNextChunk()
    {
        CleanupConsumedChunk();

        if (_frameCount != 0 && _deliveredFrames >= _frameCount)
        {
            return false;
        }

        var totalDurationSeconds = _frameCount == 0
            ? double.PositiveInfinity
            : (double)_frameCount * FramesPerSecondDenominator /
              FramesPerSecondNumerator;
        if (_nextChunkStartSeconds >= totalDurationSeconds)
        {
            return false;
        }

        // The last slice ends at the actual movie duration. A small epsilon
        // avoids asking the demuxer for a timestamp infinitesimally past EOF.
        var chunkEndSeconds = _singlePass
            ? totalDurationSeconds
            : Math.Min(
                _nextChunkStartSeconds + _chunkSeconds,
                totalDurationSeconds);
        var chunkDirectory = Path.Combine(
            _sessionRoot,
            "chunk_" + _chunkIndex.ToString("D6", CultureInfo.InvariantCulture));
        _chunkIndex++;
        Directory.CreateDirectory(chunkDirectory);
        var prefix = Path.Combine(chunkDirectory, "frame_");

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = _toolPath,
            WorkingDirectory = chunkDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        process.StartInfo.ArgumentList.Add("-an");
        process.StartInfo.ArgumentList.Add("-nm=count");
        process.StartInfo.ArgumentList.Add("-vpfx");
        process.StartInfo.ArgumentList.Add(prefix);
        process.StartInfo.ArgumentList.Add("-ignerr");
        if (!_singlePass && _nextChunkStartSeconds > 0.000_001)
        {
            process.StartInfo.ArgumentList.Add("-seek");
            process.StartInfo.ArgumentList.Add(FormatTime(_nextChunkStartSeconds));
        }
        process.StartInfo.ArgumentList.Add(_moviePath);
        if (!double.IsPositiveInfinity(chunkEndSeconds))
        {
            process.StartInfo.ArgumentList.Add(FormatTime(chunkEndSeconds));
        }

        if (_trace)
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] bink2.nihav_chunk start={_nextChunkStartSeconds:F3} " +
                $"end={chunkEndSeconds:F3} single_pass={_singlePass} " +
                $"file='{Path.GetFileName(_moviePath)}'");
        }

        if (!process.Start())
        {
            throw new InvalidOperationException(
                "Could not start the NihAV Bink2 decoder.");
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(DecoderTimeoutMilliseconds))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
            }

            throw new InvalidOperationException(
                $"NihAV timed out while decoding {Path.GetFileName(_moviePath)}.");
        }

        // Ensure redirected streams are drained after process termination.
        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();

        _chunkFrames = EnumerateFrameFiles(chunkDirectory);
        _chunkFrameIndex = 0;
        _prefetchedFrames.Clear();
        PrimePrefetch();
        _nextChunkStartSeconds = chunkEndSeconds;

        if (_chunkFrames.Count == 0)
        {
            var details = FirstNonEmpty(stderr, stdout);
            if (_trace || process.ExitCode != 0)
            {
                Console.Error.WriteLine(
                    $"[LOADER][WARN] bink2.nihav_no_frames exit={process.ExitCode} " +
                    $"at={_nextChunkStartSeconds:F3}s file='{Path.GetFileName(_moviePath)}' " +
                    $"detail='{Truncate(details, MaxTraceLength)}'");
            }

            return false;
        }

        if (_trace && process.ExitCode != 0)
        {
            Console.Error.WriteLine(
                $"[LOADER][TRACE] bink2.nihav_partial exit={process.ExitCode} " +
                $"frames={_chunkFrames.Count} detail='" +
                Truncate(FirstNonEmpty(stderr, stdout), MaxTraceLength) + "'");
        }

        return true;
    }

    private List<string> EnumerateFrameFiles(string directory)
    {
        var files = new List<(string Path, long Ordinal)>();
        foreach (var path in Directory.EnumerateFiles(directory))
        {
            if (!LooksLikePortableAnyMap(path))
            {
                continue;
            }

            files.Add((path, ExtractOrdinal(path)));
        }

        files.Sort(static (left, right) =>
        {
            var ordinal = left.Ordinal.CompareTo(right.Ordinal);
            return ordinal != 0
                ? ordinal
                : StringComparer.OrdinalIgnoreCase.Compare(left.Path, right.Path);
        });
        return files.Select(static item => item.Path).ToList();
    }

    // [V61.13.14][PREFETCH_HELPERS]
    private void PrimePrefetch()
    {
        if (!_singlePass || _prefetchDepth <= 0 || _chunkFrames.Count == 0)
        {
            return;
        }

        var end = Math.Min(
            _chunkFrames.Count,
            _chunkFrameIndex + _prefetchDepth);

        for (var index = _chunkFrameIndex; index < end; index++)
        {
            if (_prefetchedFrames.ContainsKey(index))
            {
                continue;
            }

            var framePath = _chunkFrames[index];
            _prefetchedFrames[index] =
                Task.Run(() => ReadFrameOwned(framePath));
        }
    }

    private byte[]? ReadFrameOwned(string path)
    {
        var requiredBytes = checked((int)((ulong)Width * Height * 4));
        var output = GC.AllocateUninitializedArray<byte>(requiredBytes);
        return TryReadFrame(path, output)
            ? output
            : null;
    }

    private bool TryReadFrame(string path, Span<byte> destination)
    {
        // [V61.13.16][POOLED_FRAME_READ]
        // Streaming exposes the path before the writer necessarily closes it,
        // so read the current length into one reusable buffer. No per-frame
        // multi-megabyte byte[] allocation is performed.
        var readStart = Stopwatch.GetTimestamp();
        if (!TryReadFrameFile(path, out var fileBytes))
        {
            return false;
        }
        _readTicks += Stopwatch.GetTimestamp() - readStart;

        if (!TryParsePnmHeader(
                fileBytes,
                out var magic,
                out var width,
                out var storedHeight,
                out var maxValue,
                out var payloadOffset) ||
            maxValue <= 0 ||
            maxValue > 255)
        {
            return false;
        }

        if (magic == "P6")
        {
            var sourceHeight = storedHeight;
            var required = checked(width * sourceHeight * 3);
            if (payloadOffset + required > fileBytes.Length)
            {
                return false;
            }

            var rgbConvertStart = Stopwatch.GetTimestamp();
            ConvertRgb24ToBgra(
                fileBytes.Slice(payloadOffset, required),
                width,
                sourceHeight,
                destination);
            _convertTicks += Stopwatch.GetTimestamp() - rgbConvertStart;
            _perfFrames++;
            return true;
        }

        if (magic != "P5")
        {
            return false;
        }

        // PGMYUV stores a planar YUV picture inside a P5 payload. The visible
        // height comes from the Bink header; the PGM header commonly reports
        // 3/2 of that height because U and V planes are appended after Y.
        var visibleWidth = checked((int)_sourceWidth);
        var visibleHeight = checked((int)_sourceHeight);
        if (width != visibleWidth)
        {
            return false;
        }

        if (storedHeight < visibleHeight)
        {
            return false;
        }

        var chromaWidth = (visibleWidth + 1) / 2;
        var chromaHeight = (visibleHeight + 1) / 2;
        var yBytes = checked(visibleWidth * visibleHeight);
        var chromaBytes = checked(chromaWidth * chromaHeight);
        var requiredPayload = checked(yBytes + (2 * chromaBytes));
        if (payloadOffset + requiredPayload > fileBytes.Length)
        {
            return false;
        }

        var payload = fileBytes.Slice(payloadOffset, requiredPayload);
        var yPlanePacked = payload[..yBytes];

        // [V70.1.0][PGMYUV_SIDE_BY_SIDE_CHROMA]
        // NihAV's PGMYUV geometry is:
        //
        //   YYYYYYYYYY
        //   YYYYYYYYYY
        //   UUUUUVVVVV
        //
        // i.e. the U and V half-width planes are next to each other on every
        // chroma row below the full-width Y image. The old code split the
        // complete lower block in half, mixing alternating U/V row regions and
        // producing the strong green cast seen in standalone Bink playback.
        if (_pgmPlanarBuffer is null ||
            _pgmPlanarBuffer.Length < requiredPayload)
        {
            _pgmPlanarBuffer =
                GC.AllocateUninitializedArray<byte>(requiredPayload);
        }

        var planar = _pgmPlanarBuffer.AsSpan(0, requiredPayload);
        yPlanePacked.CopyTo(planar[..yBytes]);
        var planarU = planar.Slice(yBytes, chromaBytes);
        var planarV = planar.Slice(yBytes + chromaBytes, chromaBytes);

        for (var chromaY = 0; chromaY < chromaHeight; chromaY++)
        {
            var packedRow =
                payload.Slice(
                    yBytes + chromaY * visibleWidth,
                    visibleWidth);
            packedRow[..chromaWidth]
                .CopyTo(planarU.Slice(chromaY * chromaWidth, chromaWidth));
            packedRow.Slice(chromaWidth, chromaWidth)
                .CopyTo(planarV.Slice(chromaY * chromaWidth, chromaWidth));
        }

        var yPlane = planar[..yBytes];
        var uPlane = _swapUv ? planarV : planarU;
        var vPlane = _swapUv ? planarU : planarV;

        var useFullRange = _fullRange ||
            (_autoRange && ResolveDetectedFullRange(yPlane));

        var yuvConvertStart = Stopwatch.GetTimestamp();

        // The reusable repacked buffer is true I420/YUV420P, so both native
        // swscale and the LUT fallback now consume the same correct planes.
        if (!TryConvertYuvViaFfmpeg(
                _pgmPlanarBuffer!,
                0,
                requiredPayload,
                destination))
        {
            ConvertYuv420ToBgra(
                yPlane,
                uPlane,
                vPlane,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                destination,
                useFullRange);
        }

        _convertTicks += Stopwatch.GetTimestamp() - yuvConvertStart;
        _perfFrames++;
        return true;
    }

    private bool TryConvertYuvViaFfmpeg(
        byte[] sourceBuffer,
        int sourceOffset,
        int sourceLength,
        Span<byte> destination)
    {
        if (_colorConverterDisabled ||
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_FFMPEG_COLOR") != "1")
        {
            return false;
        }

        try
        {
            if (!EnsureFfmpegColorConverter())
            {
                return false;
            }

            var input = _colorInput!;
            var output = _colorOutput!;

            // [V61.13.23.3][CONCURRENT_FFMPEG_PIPES]
            // V61.13.23.2 wrote the full 12.4 MiB 4K I420 frame before it
            // started reading FFmpeg stdout. Anonymous-pipe buffers are much
            // smaller than either frame: FFmpeg filled stdout while SharpEmu
            // was still filling stdin, so both processes blocked each other.
            //
            // Use the existing reusable source-file buffer as ReadOnlyMemory,
            // start stdin and stdout transfers concurrently, and read BGRA into
            // one reusable ~2 MiB output buffer. No per-frame 12 MiB copy/LOH
            // allocation is introduced.
            var requiredOutput = destination.Length;
            if (_colorOutputBuffer is null ||
                _colorOutputBuffer.Length < requiredOutput)
            {
                _colorOutputBuffer =
                    GC.AllocateUninitializedArray<byte>(requiredOutput);
            }

            var source =
                new ReadOnlyMemory<byte>(
                    sourceBuffer,
                    sourceOffset,
                    sourceLength);
            var target =
                _colorOutputBuffer.AsMemory(0, requiredOutput);

            var writeTask = input.WriteAsync(source).AsTask();
            var readTask = output.ReadExactlyAsync(target).AsTask();
            var both = Task.WhenAll(writeTask, readTask);

            var timeoutMs = 5_000;
            if (int.TryParse(
                    Environment.GetEnvironmentVariable(
                        "SHARPEMU_BINK_FFMPEG_FRAME_TIMEOUT_MS"),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out var configuredTimeout) &&
                configuredTimeout >= 250)
            {
                timeoutMs = configuredTimeout;
            }

            if (!both.Wait(timeoutMs))
            {
                throw new IOException(
                    $"ffmpeg color frame timed out after {timeoutMs} ms");
            }

            // Propagate any asynchronous pipe exception.
            both.GetAwaiter().GetResult();

            _colorOutputBuffer
                .AsSpan(0, requiredOutput)
                .CopyTo(destination);

            return true;
        }
        catch (Exception exception) when (
            exception is IOException or InvalidOperationException or
            EndOfStreamException or AggregateException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ffmpeg_color_fallback " +
                $"file='{Path.GetFileName(_moviePath)}' " +
                $"reason='{exception.Message.Replace('\r', ' ').Replace('\n', ' ')}'");

            StopFfmpegColorConverter();
            _colorConverterDisabled = true;
            return false;
        }
    }

    private bool EnsureFfmpegColorConverter()
    {
        if (_colorProcess is not null)
        {
            try
            {
                if (!_colorProcess.HasExited)
                {
                    return true;
                }
            }
            catch (InvalidOperationException)
            {
            }

            StopFfmpegColorConverter();
        }

        var ffmpeg = FindFfmpegPath();
        if (ffmpeg is null)
        {
            _colorConverterDisabled = true;
            return false;
        }

        var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        process.StartInfo.ArgumentList.Add("-hide_banner");
        process.StartInfo.ArgumentList.Add("-loglevel");
        process.StartInfo.ArgumentList.Add("error");
        process.StartInfo.ArgumentList.Add("-f");
        process.StartInfo.ArgumentList.Add("rawvideo");
        process.StartInfo.ArgumentList.Add("-pix_fmt");
        process.StartInfo.ArgumentList.Add("yuv420p");
        process.StartInfo.ArgumentList.Add("-video_size");
        process.StartInfo.ArgumentList.Add($"{_sourceWidth}x{_sourceHeight}");
        process.StartInfo.ArgumentList.Add("-framerate");
        process.StartInfo.ArgumentList.Add(
            $"{FramesPerSecondNumerator}/{FramesPerSecondDenominator}");
        process.StartInfo.ArgumentList.Add("-color_range");
        process.StartInfo.ArgumentList.Add("tv");
        process.StartInfo.ArgumentList.Add("-colorspace");
        process.StartInfo.ArgumentList.Add("bt709");
        process.StartInfo.ArgumentList.Add("-i");
        process.StartInfo.ArgumentList.Add("pipe:0");
        process.StartInfo.ArgumentList.Add("-vf");
        process.StartInfo.ArgumentList.Add(
            $"scale={Width}:{Height}:" +
            "flags=bilinear+accurate_rnd+full_chroma_int:" +
            "in_color_matrix=bt709:out_color_matrix=bt709:" +
            "in_range=tv:out_range=pc");
        process.StartInfo.ArgumentList.Add("-pix_fmt");
        process.StartInfo.ArgumentList.Add("bgra");
        process.StartInfo.ArgumentList.Add("-f");
        process.StartInfo.ArgumentList.Add("rawvideo");
        process.StartInfo.ArgumentList.Add("pipe:1");

        if (!process.Start())
        {
            process.Dispose();
            _colorConverterDisabled = true;
            return false;
        }

        try
        {
            process.PriorityClass = ProcessPriorityClass.AboveNormal;
        }
        catch (InvalidOperationException)
        {
        }

        _colorProcess = process;
        _colorInput = process.StandardInput.BaseStream;
        _colorOutput = process.StandardOutput.BaseStream;
        _colorStderrTask = process.StandardError.ReadToEndAsync();

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.ffmpeg_color_ready " +
            $"file='{Path.GetFileName(_moviePath)}' " +
            $"source={_sourceWidth}x{_sourceHeight} output={Width}x{Height} " +
            "matrix=BT709 range=limited chroma=bilinear pixfmt=bgra");

        return true;
    }

    private static string? FindFfmpegPath()
    {
        var configured =
            Environment.GetEnvironmentVariable("SHARPEMU_FFMPEG");
        if (!string.IsNullOrWhiteSpace(configured) &&
            File.Exists(configured))
        {
            return configured;
        }

        var appLocal = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        if (File.Exists(appLocal))
        {
            return appLocal;
        }

        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(pathValue))
        {
            foreach (var entry in pathValue.Split(
                         Path.PathSeparator,
                         StringSplitOptions.RemoveEmptyEntries |
                         StringSplitOptions.TrimEntries))
            {
                try
                {
                    var candidate = Path.Combine(entry, "ffmpeg.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch
                {
                }
            }
        }

        return null;
    }

    private void StopFfmpegColorConverter()
    {
        var process = _colorProcess;
        _colorProcess = null;

        try
        {
            _colorInput?.Dispose();
        }
        catch
        {
        }
        try
        {
            _colorOutput?.Dispose();
        }
        catch
        {
        }

        _colorInput = null;
        _colorOutput = null;
        _colorOutputBuffer = null;

        if (process is not null)
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit(2_000);
                }
            }
            catch
            {
            }

            try
            {
                process.Dispose();
            }
            catch
            {
            }
        }

        _colorStderrTask = null;
    }

    // [V61.13.16][LOW_ALLOCATION_HELPERS]
    private bool TryReadFrameFile(
        string path,
        out ReadOnlySpan<byte> bytes)
    {
        bytes = default;

        try
        {
            // [V70.3.0][CLOSED_FRAME_ONLY]
            // Directory enumeration can observe NIHAV's PGMYUV path before the
            // writer has completed the frame. Excluding FileShare.Write makes
            // this open fail until nihav-tool releases its active writer.
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete,
                bufferSize: 64 * 1024,
                FileOptions.SequentialScan);

            var length64 = stream.Length;
            if (length64 <= 0 || length64 > int.MaxValue)
            {
                return false;
            }

            var length = checked((int)length64);

            // PGMYUV 4:2:0 is about 1.5 bytes/source-pixel. Start at 16 MiB
            // so a partially-visible 4K frame does not cause repeated LOH
            // growth while nihav-tool is still writing it.
            var minimumCapacity = 16 * 1024 * 1024;
            if (_sourceFileBuffer is null ||
                _sourceFileBuffer.Length < length)
            {
                var newSize = Math.Max(minimumCapacity, length);
                _sourceFileBuffer = GC.AllocateUninitializedArray<byte>(newSize);
            }

            var target = _sourceFileBuffer.AsSpan(0, length);
            var read = 0;
            while (read < target.Length)
            {
                var count = stream.Read(target[read..]);
                if (count <= 0)
                {
                    return false;
                }
                read += count;
            }

            // [V70.3.0][STABLE_LENGTH]
            // On permissive filesystems, also reject a frame whose size
            // changed while it was being read.
            if (stream.Length != length64)
            {
                return false;
            }

            bytes = _sourceFileBuffer.AsSpan(0, length);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static int[] BuildScaleMap(int outputWidth, int sourceWidth)
    {
        var map = new int[outputWidth];
        for (var x = 0; x < outputWidth; x++)
        {
            map[x] = (int)((long)x * sourceWidth / outputWidth);
        }
        return map;
    }

    private static int[] BuildChromaScaleMap(int[] sourceX)
    {
        var map = new int[sourceX.Length];
        for (var x = 0; x < sourceX.Length; x++)
        {
            map[x] = sourceX[x] / 2;
        }
        return map;
    }

    private static (
        int[] YLimited,
        int[] YFull,
        int[] RFromV,
        int[] GFromU,
        int[] GFromV,
        int[] BFromU) BuildYuvTables(bool bt709)
    {
        var yLimited = new int[256];
        var yFull = new int[256];
        var rFromV = new int[256];
        var gFromU = new int[256];
        var gFromV = new int[256];
        var bFromU = new int[256];

        var rV = bt709 ? 459 : 409;
        var gU = bt709 ? -55 : -100;
        var gV = bt709 ? -136 : -208;
        var bU = bt709 ? 541 : 516;

        for (var value = 0; value < 256; value++)
        {
            yLimited[value] = 298 * Math.Max(0, value - 16);
            yFull[value] = value << 8;

            var centered = value - 128;
            rFromV[value] = rV * centered;
            gFromU[value] = gU * centered;
            gFromV[value] = gV * centered;
            bFromU[value] = bU * centered;
        }

        return (yLimited, yFull, rFromV, gFromU, gFromV, bFromU);
    }

    private static (
        int[] RFromV,
        int[] GFromU,
        int[] GFromV,
        int[] BFromU) BuildFullRangeChromaTables(bool bt709)
    {
        var rFromV = new int[256];
        var gFromU = new int[256];
        var gFromV = new int[256];
        var bFromU = new int[256];

        // 8-bit fixed-point full-range YCbCr -> RGB.
        // BT.709: R=Y+1.5748Cr, G=Y-0.1873Cb-0.4681Cr,
        //         B=Y+1.8556Cb.
        // BT.601 fallback retains the previous full-range coefficients.
        var rV = bt709 ? 403 : 359;
        var gU = bt709 ? -48 : -88;
        var gV = bt709 ? -120 : -183;
        var bU = bt709 ? 475 : 454;

        for (var value = 0; value < 256; value++)
        {
            var centered = value - 128;
            rFromV[value] = rV * centered;
            gFromU[value] = gU * centered;
            gFromV[value] = gV * centered;
            bFromU[value] = bU * centered;
        }

        return (rFromV, gFromU, gFromV, bFromU);
    }

    private bool ResolveDetectedFullRange(ReadOnlySpan<byte> yPlane)
    {
        if (_detectedFullRange is bool detected)
        {
            return detected;
        }

        byte minimum = byte.MaxValue;
        byte maximum = byte.MinValue;

        // Sample ~4096 luma values from the first complete frame.
        var step = Math.Max(1, yPlane.Length / 4096);
        for (var i = 0; i < yPlane.Length; i += step)
        {
            var value = yPlane[i];
            if (value < minimum)
            {
                minimum = value;
            }
            if (value > maximum)
            {
                maximum = value;
            }
        }

        // Studio-range video normally remains around 16..235. Values clearly
        // outside that range are strong evidence of a full-range source.
        detected = minimum < 8 || maximum > 247;
        _detectedFullRange = detected;

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.color_range_auto " +
            $"file='{Path.GetFileName(_moviePath)}' " +
            $"sample_min={minimum} sample_max={maximum} " +
            $"selected={(detected ? "full" : "limited")}");

        return detected;
    }

    private void LogPerfIfNeeded()
    {
        if (_deliveredFrames == 0 ||
            (_deliveredFrames % 30) != 0)
        {
            return;
        }

        var frames = Math.Max(1L, _perfFrames);
        var tickToMs = 1000.0 / Stopwatch.Frequency;
        var readMs = _readTicks * tickToMs / frames;
        var convertMs = _convertTicks * tickToMs / frames;
        var waitMs = _waitTicks * tickToMs / Math.Max(1u, _deliveredFrames);

        var backlog = 0;
        var directory = _streamDirectory;
        if (!string.IsNullOrWhiteSpace(directory) &&
            Directory.Exists(directory))
        {
            try
            {
                backlog = Directory.EnumerateFiles(directory)
                    .Count(LooksLikePortableAnyMap);
            }
            catch (IOException)
            {
            }
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.perf " +
            $"file='{Path.GetFileName(_moviePath)}' " +
            $"frame={_deliveredFrames} read_avg_ms={readMs:F2} " +
            $"convert_avg_ms={convertMs:F2} wait_avg_ms={waitMs:F2} " +
            $"backlog={backlog}");
    }

    private void ConvertRgb24ToBgra(
        ReadOnlySpan<byte> source,
        int sourceWidth,
        int sourceHeight,
        Span<byte> destination)
    {
        var outputWidth = checked((int)Width);
        var outputHeight = checked((int)Height);
        for (var y = 0; y < outputHeight; y++)
        {
            var sourceY = (int)((long)y * sourceHeight / outputHeight);
            for (var x = 0; x < outputWidth; x++)
            {
                var sourceX = (int)((long)x * sourceWidth / outputWidth);
                var sourceOffset = (sourceY * sourceWidth + sourceX) * 3;
                var destinationOffset = (y * outputWidth + x) * 4;
                destination[destinationOffset] = source[sourceOffset + 2];
                destination[destinationOffset + 1] = source[sourceOffset + 1];
                destination[destinationOffset + 2] = source[sourceOffset];
                destination[destinationOffset + 3] = 0xFF;
            }
        }
    }

    private void ConvertYuv420ToBgra(
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int sourceWidth,
        int sourceHeight,
        int chromaWidth,
        Span<byte> destination,
        bool useFullRange)
    {
        // [V61.13.17][LUT_YUV_CONVERT]
        // The V61.13.16 measurement put scalar conversion at ~31 ms/frame,
        // essentially the entire 30-fps frame budget. Replace per-pixel
        // multiplies and vertical divisions with table lookups and maps.
        var outputWidth = checked((int)Width);
        var outputHeight = checked((int)Height);
        var yTable = useFullRange ? _yFullTable : _yLimitedTable;
        var rFromV = useFullRange ? _rFromVFullTable : _rFromVTable;
        var gFromU = useFullRange ? _gFromUFullTable : _gFromUTable;
        var gFromV = useFullRange ? _gFromVFullTable : _gFromVTable;
        var bFromU = useFullRange ? _bFromUFullTable : _bFromUTable;

        for (var y = 0; y < outputHeight; y++)
        {
            var sourceY = _sourceYByOutput[y];
            var yRow = sourceY * sourceWidth;
            var chromaRow = _chromaYByOutput[y] * chromaWidth;
            var destinationOffset = y * outputWidth * 4;

            for (var x = 0; x < outputWidth; x++)
            {
                var luma = yPlane[yRow + _sourceXByOutput[x]];
                var chromaOffset = chromaRow + _chromaXByOutput[x];
                var u = uPlane[chromaOffset];
                var v = vPlane[chromaOffset];

                var yBase = yTable[luma];
                destination[destinationOffset] = ClampByte(
                    (yBase + bFromU[u] + 128) >> 8);
                destination[destinationOffset + 1] = ClampByte(
                    (yBase + gFromU[u] + gFromV[v] + 128) >> 8);
                destination[destinationOffset + 2] = ClampByte(
                    (yBase + rFromV[v] + 128) >> 8);
                destination[destinationOffset + 3] = 0xFF;
                destinationOffset += 4;
            }
        }
    }

    private static byte ClampByte(int value) =>
        (byte)Math.Clamp(value, byte.MinValue, byte.MaxValue);

    private static bool TryReadHeader(
        string path,
        out uint width,
        out uint height,
        out uint frameCount,
        out uint frameRateNumerator,
        out uint frameRateDenominator)
    {
        width = 0;
        height = 0;
        frameCount = 0;
        frameRateNumerator = 0;
        frameRateDenominator = 0;
        Span<byte> header = stackalloc byte[HeaderProbeLength];
        try
        {
            using var stream = File.OpenRead(path);
            stream.ReadExactly(header);
        }
        catch (Exception exception) when (
            exception is IOException or EndOfStreamException)
        {
            return false;
        }

        if (!header[..3].SequenceEqual("KB2"u8))
        {
            return false;
        }

        frameCount = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
            header.Slice(8, 4));
        width = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
            header.Slice(0x14, 4));
        height = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
            header.Slice(0x18, 4));
        frameRateNumerator =
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
                header.Slice(0x1C, 4));
        frameRateDenominator =
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
                header.Slice(0x20, 4));
        return width > 0 &&
               height > 0 &&
               frameCount > 0 &&
               frameRateNumerator > 0 &&
               frameRateDenominator > 0;
    }

    private static (uint Width, uint Height) FitWithin(
        uint width,
        uint height,
        uint maximumWidth,
        uint maximumHeight)
    {
        if (maximumWidth == 0 ||
            maximumHeight == 0 ||
            (width <= maximumWidth && height <= maximumHeight))
        {
            return (width, height);
        }

        if ((ulong)width * maximumHeight > (ulong)height * maximumWidth)
        {
            var outputHeight = Math.Max(
                1u,
                (uint)((ulong)height * maximumWidth / width));
            return (maximumWidth, outputHeight);
        }

        var outputWidth = Math.Max(
            1u,
            (uint)((ulong)width * maximumHeight / height));
        return (outputWidth, maximumHeight);
    }

    private static string? FindToolPath()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_TOOL");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var expanded = Environment.ExpandEnvironmentVariables(configured);
            if (File.Exists(expanded))
            {
                return Path.GetFullPath(expanded);
            }
        }

        var baseDirectory = AppContext.BaseDirectory;
        foreach (var relative in new[]
                 {
                     Path.Combine("plugins", "bink2", "nihav-tool.exe"),
                     Path.Combine("plugins", "bink2", "nihav_tool.exe"),
                     Path.Combine("plugins", "bink2", "nihav-tool"),
                     "nihav-tool.exe",
                     "nihav-tool",
                 })
        {
            var candidate = Path.Combine(baseDirectory, relative);
            if (File.Exists(candidate))
            {
                return Path.GetFullPath(candidate);
            }
        }

        return null;
    }

    private static int _missingToolLogged;

    private static void LogMissingToolOnce()
    {
        if (Interlocked.Exchange(ref _missingToolLogged, 1) != 0)
        {
            return;
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] Bink2 NIHAV runtime is not installed. Expected " +
            "'plugins\\bink2\\nihav-tool.exe' or SHARPEMU_NIHAV_TOOL.");
    }

    private static bool LooksLikePortableAnyMap(string path)
    {
        try
        {
            using var stream = File.Open(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length < 2)
            {
                return false;
            }

            var first = stream.ReadByte();
            var second = stream.ReadByte();
            return first == 'P' && (second == '5' || second == '6');
        }
        catch (IOException)
        {
            return false;
        }
    }

    private static bool TryParsePnmHeader(
        ReadOnlySpan<byte> bytes,
        out string magic,
        out int width,
        out int height,
        out int maxValue,
        out int payloadOffset)
    {
        magic = string.Empty;
        width = 0;
        height = 0;
        maxValue = 0;
        payloadOffset = 0;
        var offset = 0;
        if (!TryReadToken(bytes, ref offset, out magic) ||
            !TryReadToken(bytes, ref offset, out var widthToken) ||
            !TryReadToken(bytes, ref offset, out var heightToken) ||
            !TryReadToken(bytes, ref offset, out var maxValueToken) ||
            !int.TryParse(widthToken, NumberStyles.Integer, CultureInfo.InvariantCulture, out width) ||
            !int.TryParse(heightToken, NumberStyles.Integer, CultureInfo.InvariantCulture, out height) ||
            !int.TryParse(maxValueToken, NumberStyles.Integer, CultureInfo.InvariantCulture, out maxValue) ||
            width <= 0 ||
            height <= 0)
        {
            return false;
        }

        // NihAV's writer terminates the PNM header with whitespace. Advance
        // through that delimiter, but do not continue skipping arbitrary bytes
        // because binary pixel data may itself begin with an ASCII whitespace.
        if (offset < bytes.Length && IsWhitespace(bytes[offset]))
        {
            offset++;
        }
        payloadOffset = offset;
        return magic is "P5" or "P6";
    }

    private static bool TryReadToken(
        ReadOnlySpan<byte> bytes,
        ref int offset,
        out string token)
    {
        token = string.Empty;
        while (offset < bytes.Length)
        {
            if (bytes[offset] == '#')
            {
                while (offset < bytes.Length &&
                       bytes[offset] is not (byte)'\n' and not (byte)'\r')
                {
                    offset++;
                }
                continue;
            }

            if (!IsWhitespace(bytes[offset]))
            {
                break;
            }
            offset++;
        }

        var start = offset;
        while (offset < bytes.Length &&
               !IsWhitespace(bytes[offset]) &&
               bytes[offset] != '#')
        {
            offset++;
        }

        if (offset <= start)
        {
            return false;
        }

        token = Encoding.ASCII.GetString(bytes[start..offset]);
        return true;
    }

    private static bool IsWhitespace(byte value) =>
        value is (byte)' ' or (byte)'\t' or (byte)'\n' or (byte)'\r' or
            (byte)'\f' or (byte)'\v';

    private static long ExtractOrdinal(string path)
    {
        var name = Path.GetFileNameWithoutExtension(path);
        var end = name.Length - 1;
        while (end >= 0 && !char.IsDigit(name[end]))
        {
            end--;
        }
        if (end < 0)
        {
            return long.MaxValue;
        }

        var start = end;
        while (start > 0 && char.IsDigit(name[start - 1]))
        {
            start--;
        }

        return long.TryParse(
            name.AsSpan(start, end - start + 1),
            NumberStyles.None,
            CultureInfo.InvariantCulture,
            out var ordinal)
            ? ordinal
            : long.MaxValue;
    }

    private static string FormatTime(double seconds)
    {
        var time = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return FormattableString.Invariant(
            $"{(int)time.TotalHours:00}:{time.Minutes:00}:{time.Seconds:00}.{time.Milliseconds:000}");
    }

    private static string FirstNonEmpty(string first, string second) =>
        !string.IsNullOrWhiteSpace(first)
            ? first.Trim()
            : second.Trim();

    private static string Truncate(string value, int maximumLength) =>
        value.Length <= maximumLength
            ? value
            : value[..maximumLength];

    private void CleanupConsumedChunk()
    {
        if (_prefetchedFrames.Count > 0)
        {
            foreach (var task in _prefetchedFrames.Values)
            {
                try
                {
                    _ = task.GetAwaiter().GetResult();
                }
                catch (Exception)
                {
                    // Cleanup must remain best-effort; decode failures are
                    // handled by the consumer path.
                }
            }
            _prefetchedFrames.Clear();
        }

        if (_chunkFrames.Count == 0)
        {
            return;
        }

        string? directory = null;
        foreach (var path in _chunkFrames)
        {
            directory ??= Path.GetDirectoryName(path);
            TryDelete(path);
        }
        _chunkFrames = [];
        _chunkFrameIndex = 0;
        if (!string.IsNullOrWhiteSpace(directory))
        {
            TryDeleteDirectory(directory);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        StopFfmpegColorConverter();
        StopStreamingProcess();
        CleanupConsumedChunk();
        TryDeleteDirectory(_sessionRoot);
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(_moviePath);
    }
}
