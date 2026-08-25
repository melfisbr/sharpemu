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
internal sealed class NihavBink2Decoder : IMediaFrameDecoder, IMediaFramePixelLayoutSource
{
    private const int HeaderProbeLength = 48;
    private const int DecoderTimeoutMilliseconds = 120_000;
    private const double DefaultChunkSeconds = 1.0;
    private const double MinimumChunkSeconds = 0.25;
    private const double MaximumChunkSeconds = 4.0;
    private const int MaxTraceLength = 4096;
    // [V72.4.3.2.15][RAW_PGMYUV_TRUTH]
    private static int _v7243215RawTruthSerial;

    private readonly string _moviePath;
    private readonly string _toolPath;
    private readonly string _sessionRoot;
    private readonly uint _sourceWidth;
    private readonly uint _sourceHeight;
    private readonly uint _frameCount;
    private readonly bool _trace;
    // SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV
    private readonly bool _directUiYuvV74105;
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

    // [V70.4.1.0][GREEN_FALLBACK_REPAIR]
    private byte[]? _fallbackColorScratch;
    private bool? _fallbackSwapUvDecision;
    private bool _forcedUvRecoveryLogged;
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

    // SHARPEMU_V74_0_109_DIRECT_YUV_CHROMA_REPAIR
    // Reusable planar scratch for repairing NIHAV chroma after 4K->1080p
    // downscale without reintroducing a YUV->RGB->YUV round-trip.
    private byte[]? _v74109DirectChromaRepairBuffer;

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
        _directUiYuvV74105 =
            HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(moviePath) &&
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_DS_UI_BINK_DIRECT_YUV"),
                "0",
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

    public MediaFramePixelLayout PixelLayout =>
        _directUiYuvV74105
            ? MediaFramePixelLayout.Nv12
            : MediaFramePixelLayout.Bgra32;

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

        // SHARPEMU_V74_0_95_1_UI_BINK_DECODE_CAP
        // Guest UI movies need more source detail than the boot-video path, but
        // must not expand to the guest 4K plane on the CPU. Select a dedicated
        // cap by path; the presenter owns the final Vulkan scale.
        var uiBinkV740951 =
            HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(path);
        var maxWidthVariableV740951 = uiBinkV740951
            ? "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_WIDTH"
            : "SHARPEMU_BINK_OUTPUT_MAX_WIDTH";
        var maxHeightVariableV740951 = uiBinkV740951
            ? "SHARPEMU_DS_UI_BINK_OUTPUT_MAX_HEIGHT"
            : "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT";

        if (uint.TryParse(
                Environment.GetEnvironmentVariable(maxWidthVariableV740951),
                out var configuredMaxWidth) &&
            configuredMaxWidth >= 320)
        {
            effectiveMaximumWidth = Math.Min(
                effectiveMaximumWidth,
                configuredMaxWidth);
        }
        if (uint.TryParse(
                Environment.GetEnvironmentVariable(maxHeightVariableV740951),
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

        // SHARPEMU_V74_0_108_2_DIRECT_YUV_OUTPUT_BUFFER_CONTRACT
        // MediaFramePlayback sizes its ring from PixelLayout. Keep the decoder's
        // destination contract identical: NV12 is 1.5 bytes/pixel, BGRA is 4.
        var requiredBytes = PixelLayout == MediaFramePixelLayout.Nv12
            ? checked((int)((ulong)Width * Height * 3 / 2))
            : checked((int)((ulong)Width * Height * 4));
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
                // [V70.5.0][NIHAV_HIGH_PRIORITY]
                // Standalone playback has no competing guest CPU workload. Give
                // the external Bink producer High priority when explicitly
                // requested so it can fill the streaming queue ahead of display.
                "3" => ProcessPriorityClass.High,
                "2" => ProcessPriorityClass.AboveNormal,
                "1" => ProcessPriorityClass.Normal,
                // SHARPEMU_V74_0_100_1_NIHAV_PRODUCER_PRIORITY
                // The title loop feeds the live guest compositor. BelowNormal
                // let the 4K producer fall to ~4 FPS while the consumer waited
                // about 243 ms per frame. AboveNormal is the new safe default;
                // explicit 0 restores BelowNormal.
                "0" => ProcessPriorityClass.BelowNormal,
                _ => ProcessPriorityClass.AboveNormal,
            };
        }
        catch (Exception exception) when (
            exception is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            NotSupportedException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.nihav_priority_failed " +
                $"type={exception.GetType().Name} message='{exception.Message}'");
        }

        // V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY_APPLY
        TryApplyV724329DedicatedAffinity(process);

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

    // V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY
    //
    // HostMovieExecutionGate limits the SharpEmu process during Bink playback.
    // A newly-created child inherits the parent's current affinity. Move NihAV
    // onto the highest system logical processors after CreateProcess so guest
    // workers and the single-threaded Bink2 decoder do not contend on the same
    // logical CPUs.
    [System.Runtime.InteropServices.DllImport(
        "kernel32.dll",
        SetLastError = false)]
    private static extern uint GetActiveProcessorCount(
        ushort groupNumber);

    private static void TryApplyV724329DedicatedAffinity(
        Process process)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            const ushort allProcessorGroups = 0xFFFF;

            var active =
                (int)GetActiveProcessorCount(
                    allProcessorGroups);

            if (active <= 0)
            {
                return;
            }

            active = Math.Min(active, 63);

            // V74.0.100.1: NihAV may fan out decode/scale work internally. Two
            // inherited logical CPUs were insufficient on a 24-thread host.
            // Reserve six on larger machines, while retaining two on compact
            // hosts and honoring the existing explicit override.
            var configured = active >= 12 ? 6 : Math.Min(active, 2);
            var raw =
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT");

            if (int.TryParse(
                    raw,
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out var parsed))
            {
                configured =
                    Math.Clamp(parsed, 1, Math.Min(active, 8));
            }

            ulong mask = 0;

            for (var i = 0;
                 i < configured;
                 i++)
            {
                var bit = active - 1 - i;
                if (bit < 0)
                {
                    break;
                }

                mask |= 1UL << bit;
            }

            if (mask == 0)
            {
                return;
            }

            process.ProcessorAffinity =
                (nint)(long)mask;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.nihav_dedicated_affinity " +
                $"system_logical={active} count={configured} mask=0x{mask:X}");
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            NotSupportedException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.nihav_dedicated_affinity_failed " +
                $"type={ex.GetType().Name} message='{ex.Message}'");
        }
    }

    // [V70.8.0.1][STREAM_FULL_CACHE]
    private bool WaitForFirstStreamingFrame()
    {
        if (ResolveStreamingFullCache())
        {
            return WaitForStreamingProducerCompletion();
        }

        // SHARPEMU_V74_0_83_TITLE_LOOP_FAST_RESTART
        // Do not rebuild the global 60-frame reservoir every time the
        // persistent title loop wraps.
        var titleLoopFastStartV74083 =
            string.Equals(
                Path.GetFileName(_moviePath),
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase);
        var target = titleLoopFastStartV74083
            ? ResolveTitleLoopStreamingPrefetchFramesV741001()
            : ResolveStreamingStartupPrefetchFrames();

        if (titleLoopFastStartV74083)
        {
            Console.Error.WriteLine(
                "[V74.0.100.1][TITLE_LOOP_RESERVOIR] " +
                $"file='logo_intro_loop.bk2' target={target} " +
                "mode=producer-reservoir");
        }
        var deadline = Stopwatch.GetTimestamp() +
            (long)(Stopwatch.Frequency * ResolveStreamingStartupPrefetchSeconds());
        var bestReady = 0;

        while (Stopwatch.GetTimestamp() < deadline)
        {
            var ready = CountReadyStreamingFrames(target);
            bestReady = Math.Max(bestReady, ready);
            if (ready >= target)
            {
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.stream_prefetch_ready " +
                    $"file='{Path.GetFileName(_moviePath)}' ready={ready} target={target}");
                return true;
            }

            if (StreamingProcessExited())
            {
                var finalReady = CountReadyStreamingFrames(target);
                if (finalReady > 0)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][INFO] bink2.stream_prefetch_partial " +
                        $"file='{Path.GetFileName(_moviePath)}' ready={finalReady} target={target} producer_exited=True");
                    return true;
                }
                return false;
            }

            Thread.Sleep(1);
        }

        var fallbackReady = CountReadyStreamingFrames(target);
        if (fallbackReady > 0 || FindNextStreamingFrame() is not null)
        {
            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.stream_prefetch_timeout " +
                $"file='{Path.GetFileName(_moviePath)}' ready={Math.Max(bestReady, fallbackReady)} target={target}");
            return true;
        }

        return false;
    }

    private bool WaitForStreamingProducerCompletion()
    {
        var timeoutSeconds = ResolveStreamingFullCacheTimeoutSeconds();
        var started = Stopwatch.GetTimestamp();
        var deadline = started + (long)(Stopwatch.Frequency * timeoutSeconds);
        var nextProgress = started;
        var lastCount = 0;

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.full_cache_begin " +
            $"file='{Path.GetFileName(_moviePath)}' timeout_s={timeoutSeconds:0}");

        while (Stopwatch.GetTimestamp() < deadline)
        {
            var now = Stopwatch.GetTimestamp();
            if (now >= nextProgress)
            {
                lastCount = CountStreamingFrameFilesFast();
                var elapsed = (now - started) / (double)Stopwatch.Frequency;
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.full_cache_progress " +
                    $"file='{Path.GetFileName(_moviePath)}' ready={lastCount} elapsed_s={elapsed:0.0}");
                nextProgress = now + (long)(Stopwatch.Frequency * 2.0);
            }

            if (StreamingProcessExited())
            {
                var finalCount = CountReadyStreamingFrames(int.MaxValue);
                if (finalCount <= 0)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][WARN] bink2.full_cache_empty " +
                        $"file='{Path.GetFileName(_moviePath)}'");
                    return false;
                }

                var elapsed = (Stopwatch.GetTimestamp() - started) /
                    (double)Stopwatch.Frequency;
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.full_cache_ready " +
                    $"file='{Path.GetFileName(_moviePath)}' frames={finalCount} elapsed_s={elapsed:0.0}");
                return true;
            }

            Thread.Sleep(20);
        }

        var ready = CountReadyStreamingFrames(int.MaxValue);
        if (ready > 0)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.full_cache_timeout " +
                $"file='{Path.GetFileName(_moviePath)}' ready={ready} timeout_s={timeoutSeconds:0}; starting with partial cache");
            return true;
        }

        return false;
    }

    private static bool ResolveStreamingFullCache()
    {
        var value = Environment.GetEnvironmentVariable(
            "SHARPEMU_NIHAV_STREAM_FULL_CACHE");
        return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(value, "true", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(value, "yes", StringComparison.OrdinalIgnoreCase);
    }

    private static double ResolveStreamingFullCacheTimeoutSeconds()
    {
        var value = Environment.GetEnvironmentVariable(
            "SHARPEMU_NIHAV_STREAM_FULL_CACHE_TIMEOUT_SECONDS");
        return double.TryParse(
                value,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var seconds)
            ? Math.Clamp(seconds, 30.0, 1800.0)
            : 900.0;
    }

    private int CountStreamingFrameFilesFast()
    {
        var directory = _streamDirectory;
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
        {
            return 0;
        }

        try
        {
            var count = 0;
            foreach (var path in Directory.EnumerateFiles(directory))
            {
                if (LooksLikePortableAnyMap(path))
                {
                    count++;
                }
            }
            return count;
        }
        catch (IOException)
        {
            return 0;
        }
        catch (UnauthorizedAccessException)
        {
            return 0;
        }
    }

    private static int ResolveStreamingStartupPrefetchFrames()
    {
        var configured = Environment.GetEnvironmentVariable(
            "SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES");
        return int.TryParse(
                configured,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var frames)
            ? Math.Clamp(frames, 1, 60)
            : 12;
    }

    private static int ResolveTitleLoopStreamingPrefetchFramesV741001()
    {
        var configured = Environment.GetEnvironmentVariable(
            "SHARPEMU_NIHAV_TITLE_LOOP_PREFETCH_FRAMES");
        return int.TryParse(
                configured,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var frames)
            ? Math.Clamp(frames, 1, 90)
            : 30;
    }

    private static double ResolveStreamingStartupPrefetchSeconds()
    {
        var configured = Environment.GetEnvironmentVariable(
            "SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS");
        return double.TryParse(
                configured,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var seconds)
            ? Math.Clamp(seconds, 1.0, 30.0)
            : 8.0;
    }

    private int CountReadyStreamingFrames(int stopAfter)
    {
        var directory = _streamDirectory;
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
        {
            return 0;
        }

        var count = 0;
        try
        {
            foreach (var path in Directory.EnumerateFiles(directory))
            {
                if (!LooksLikePortableAnyMap(path))
                {
                    continue;
                }

                try
                {
                    using var stream = new FileStream(
                        path,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read | FileShare.Delete);
                    if (stream.Length <= 16)
                    {
                        continue;
                    }
                }
                catch (IOException)
                {
                    continue;
                }
                catch (UnauthorizedAccessException)
                {
                    continue;
                }

                count++;
                if (count >= stopAfter)
                {
                    break;
                }
            }
        }
        catch (IOException)
        {
            return count;
        }
        catch (UnauthorizedAccessException)
        {
            return count;
        }

        return count;
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

        // V72.4.3.2.23 CATCHUP_SKIP_CAP
        // V22 could discard 10+ frames in one step when the first movie was
        // CPU-starved. Bound stale-frame deletion so quality/artifacts do not
        // collapse while still allowing gradual A/V clock recovery.
        // V72.4.3.2.24 FULL_CACHE_NO_SKIP
        // V72.4.3.2.25 HYBRID_REALTIME_CATCHUP
        // V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP
        // Preserve decoded frame order. The 60-frame startup buffer
        // absorbs the measured short-movie producer deficit instead of
        // creating visible jumps by deleting stale frames.
        var maxCatchupSkip = 0;
        var rawCatchupSkip =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_MAX_CATCHUP_SKIP");

        if (int.TryParse(rawCatchupSkip, out var parsedCatchupSkip))
        {
            maxCatchupSkip =
                Math.Clamp(
                    parsedCatchupSkip,
                    0,
                    8);
        }

        selectedIndex =
            Math.Min(
                selectedIndex,
                maxCatchupSkip);

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
        var requiredBytes = PixelLayout == MediaFramePixelLayout.Nv12
            ? checked((int)((ulong)Width * Height * 3 / 2))
            : checked((int)((ulong)Width * Height * 4));
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
            if (_directUiYuvV74105)
            {
                Console.Error.WriteLine(
                    "[V74.0.105][UI_BINK_DIRECT_YUV] " +
                    $"file='{Path.GetFileName(_moviePath)}' action=reject-rgb-source");
                return false;
            }

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

        // [V72.4.3.2.15][RAW_PGMYUV_TRUTH]
        // Capture exact NihAV bytes before planar repack, scaling, range
        // selection or RGB conversion.
        TryDumpV7243215RawChromaTruth(
            path,
            payload,
            visibleWidth,
            visibleHeight,
            chromaWidth,
            chromaHeight);

        // V72.4.3.2.13 PACKED_PGMYUV_BOX
        //
        // The V72.4.3.2.11 exact-scale fallback chooses the first sample of
        // every 6x6 luma / 3x3 chroma footprint. It also repacks the complete
        // 3840x2160 PGMYUV payload into a second ~12.4 MiB I420 buffer before
        // producing a 640x360 host frame.
        //
        // Convert directly from PGMYUV's [Y rows][U|V rows] representation.
        // Center-sample luma and box-filter the whole chroma footprint. For the
        // 4K->640x360 path the 3x3 chroma footprint is explicitly unrolled to remove nested-loop overhead.
        // Keep the V72.4.3.2.11 path as an environment-controlled fallback.
        // SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV
        // NIHAV already produced YUV420. Downscale directly into NV12 and let
        // the guest's own Bink shader perform its original color conversion.
        // No RGB conversion or second RGB->YUV pass occurs.
        if (_directUiYuvV74105)
        {
            if (chromaWidth * 2 != visibleWidth ||
                chromaHeight * 2 != visibleHeight ||
                (Width & 1) != 0 ||
                (Height & 1) != 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.105][UI_BINK_DIRECT_YUV] " +
                    $"file='{Path.GetFileName(_moviePath)}' action=reject-layout " +
                    $"source={visibleWidth}x{visibleHeight} output={Width}x{Height}");
                return false;
            }

            var directStartV74105 = Stopwatch.GetTimestamp();
            ConvertPackedPgmYuvToNv12V74105(
                payload,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                chromaHeight,
                checked((int)Width),
                checked((int)Height),
                destination);

            // SHARPEMU_V74_0_110_DIRECT_YUV_REFERENCE_COLOR
            // Direct NV12 must reproduce the reference-calibrated chroma that
            // made the earlier BGRA path visually correct. V105/V109 bypassed
            // that Q14 calibration and only deblocked U/V, leaving the title
            // loop with the strong green cast seen in runtime screenshots.
            // Keep the direct YUV path, but calibrate U/V in-place at 1080p.
            ApplyDirectNv12ReferenceColorV74110(
                destination,
                checked((int)Width),
                checked((int)Height));

            _convertTicks += Stopwatch.GetTimestamp() - directStartV74105;
            _perfFrames++;

            var directCountV74105 = Interlocked.Increment(
                ref _v74105DirectYuvTraceCount);
            if (directCountV74105 <= 16 ||
                (directCountV74105 & (directCountV74105 - 1)) == 0)
            {
                var frameBytesV74105 = checked(
                    (int)((ulong)Width * Height * 3 / 2));
                Console.Error.WriteLine(
                    "[V74.0.105][UI_BINK_DIRECT_YUV] " +
                    $"count={directCountV74105} file='{Path.GetFileName(_moviePath)}' " +
                    $"source={visibleWidth}x{visibleHeight} output={Width}x{Height} " +
                    $"bytes={frameBytesV74105} bgra_roundtrip=False");
            }
            return true;
        }

        var explicitFfmpegColor =
            string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_FFMPEG_COLOR"),
                "1",
                StringComparison.Ordinal);
        var packedDirectEnabled =
            !explicitFfmpegColor &&
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_PACKED_DIRECT"),
                "0",
                StringComparison.Ordinal);

        if (packedDirectEnabled &&
            chromaWidth * 2 == visibleWidth &&
            chromaHeight * 2 == visibleHeight)
        {
            var packedDirectFullRange =
                _fullRange ||
                (_autoRange &&
                 ResolveDetectedFullRange(yPlanePacked));

            var packedDirectStart = Stopwatch.GetTimestamp();

            ConvertPackedPgmYuvToBgraV7243213(
                payload,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                chromaHeight,
                checked((int)Width),
                checked((int)Height),
                destination,
                packedDirectFullRange,
                _swapUv);

            _convertTicks +=
                Stopwatch.GetTimestamp() - packedDirectStart;
            _perfFrames++;
            return true;
        }

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

        // V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR
        // The RAW NIHAV audit isolated rectangular discontinuities to U/V
        // before SharpEmu color conversion. Repair only those chroma block
        // boundaries; Y remains bit-for-bit untouched.
        BinkChromaRepairV7243227.RepairInPlace(
            planarU,
            planarV,
            chromaWidth,
            chromaHeight,
            _moviePath);

        var yPlane = planar[..yBytes];
        var uPlane = _swapUv ? planarV : planarU;
        var vPlane = _swapUv ? planarU : planarV;

        var useFullRange = _fullRange ||
            (_autoRange && ResolveDetectedFullRange(yPlane));

        var yuvConvertStart = Stopwatch.GetTimestamp();

        // [V61.24.2 FFMPEG_UV_SWAP]
        // _swapUv used to affect only the LUT fallback because FFmpeg consumed
        // _pgmPlanarBuffer directly. That made SHARPEMU_NIHAV_UV_SWAP a no-op
        // whenever the persistent swscale converter was active. Swap the two
        // contiguous chroma planes around the FFmpeg call, then restore them so
        // the existing LUT fallback continues to see the original buffer.
        var ffmpegSwapUv = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_UV_SWAP"),
            "1",
            StringComparison.Ordinal);

        var ffmpegConverted = false;
        if (ffmpegSwapUv)
        {
            SwapEqualPlanes(planarU, planarV);
        }

        try
        {
            ffmpegConverted = TryConvertYuvViaFfmpeg(
                _pgmPlanarBuffer!,
                0,
                requiredPayload,
                destination);
        }
        finally
        {
            if (ffmpegSwapUv)
            {
                SwapEqualPlanes(planarU, planarV);
            }
        }

        if (!ffmpegConverted)
        {
            // V72.4.3.2.2 EXACT_BT709_I420
            // Consume the decoder's repacked I420 as Y/U/V directly.
            // Do not apply the old post-conversion green heuristic.
            ConvertYuv420ToBgraBt709Exact(
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

    // SHARPEMU_V74_0_110_DIRECT_YUV_REFERENCE_COLOR
    private static long _v74110DirectReferenceColorTraceCount;

    private void ApplyDirectNv12ReferenceColorV74110(
        Span<byte> destination,
        int width,
        int height)
    {
        if (width <= 0 || height <= 0 ||
            (width & 1) != 0 || (height & 1) != 0)
        {
            return;
        }

        var legacyDeblockSetting =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_LEGACY_CHROMA_REPAIR");
        var legacyDeblock =
            !string.Equals(
                legacyDeblockSetting,
                "0",
                StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(
                legacyDeblockSetting,
                "false",
                StringComparison.OrdinalIgnoreCase);
        if (legacyDeblock)
        {
            RepairDirectNv12ChromaV74109(destination, width, height);
        }

        var calibrationSetting =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION");
        var referenceCalibration =
            !string.Equals(
                calibrationSetting,
                "0",
                StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(
                calibrationSetting,
                "false",
                StringComparison.OrdinalIgnoreCase);

        var yBytes = checked(width * height);
        var chromaWidth = width / 2;
        var chromaHeight = height / 2;
        var uvBytes = checked(chromaWidth * chromaHeight * 2);
        if (destination.Length < checked(yBytes + uvBytes))
        {
            return;
        }

        if (referenceCalibration)
        {
            var yPlane = destination[..yBytes];
            var uv = destination.Slice(yBytes, uvBytes);
            for (var chromaY = 0; chromaY < chromaHeight; chromaY++)
            {
                var lumaY = chromaY * 2;
                var lumaRow0 = lumaY * width;
                var lumaRow1 = lumaRow0 + width;
                var uvRow = chromaY * chromaWidth * 2;
                for (var chromaX = 0; chromaX < chromaWidth; chromaX++)
                {
                    var lumaX = chromaX * 2;
                    var yy = (
                        yPlane[lumaRow0 + lumaX] +
                        yPlane[lumaRow0 + lumaX + 1] +
                        yPlane[lumaRow1 + lumaX] +
                        yPlane[lumaRow1 + lumaX + 1] + 2) >> 2;

                    var uvOffset = uvRow + chromaX * 2;
                    var cbValue = uv[uvOffset] - 128;
                    var crValue = uv[uvOffset + 1] - 128;

                    // V72.4.3.2.17 reference transform, retained exactly in
                    // Q14 integer form but applied directly in the NV12 domain:
                    // Cb' = 0.735107 Cb - 0.893982 Cr - 0.046509 Y
                    // Cr' = -0.133484 Cb + 0.504089 Cr + 0.048767 Y
                    var cbAccumulator =
                        12044 * cbValue -
                        14647 * crValue -
                        762 * yy;
                    var crAccumulator =
                        -2187 * cbValue +
                        8259 * crValue +
                        799 * yy;

                    cbValue =
                        cbAccumulator >= 0
                            ? (cbAccumulator + 8192) >> 14
                            : -(((-cbAccumulator) + 8192) >> 14);
                    crValue =
                        crAccumulator >= 0
                            ? (crAccumulator + 8192) >> 14
                            : -(((-crAccumulator) + 8192) >> 14);

                    uv[uvOffset] =
                        (byte)(Math.Clamp(cbValue, -128, 127) + 128);
                    uv[uvOffset + 1] =
                        (byte)(Math.Clamp(crValue, -128, 127) + 128);
                }
            }
        }

        var trace = Interlocked.Increment(
            ref _v74110DirectReferenceColorTraceCount);
        if (trace <= 16 || (trace & (trace - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[V74.0.110][DIRECT_YUV_REFERENCE_COLOR] " +
                $"count={trace} file='{Path.GetFileName(_moviePath)}' " +
                $"size={width}x{height} matrix=BT709 range=full " +
                $"q14={referenceCalibration} legacy_deblock={legacyDeblock} " +
                "uv_order=UV luma_rewrite=False bgra_roundtrip=False");
        }
    }

    // SHARPEMU_V74_0_109_DIRECT_YUV_CHROMA_REPAIR
    private static long _v74109DirectChromaRepairTraceCount;

    private void RepairDirectNv12ChromaV74109(
        Span<byte> destination,
        int width,
        int height)
    {
        if (width <= 0 || height <= 0 ||
            (width & 1) != 0 || (height & 1) != 0)
        {
            return;
        }

        var yBytes = checked(width * height);
        var chromaWidth = width / 2;
        var chromaHeight = height / 2;
        var planeBytes = checked(chromaWidth * chromaHeight);
        if (destination.Length < checked(yBytes + planeBytes * 2))
        {
            return;
        }

        var scratchBytes = checked(planeBytes * 2);
        if (_v74109DirectChromaRepairBuffer is null ||
            _v74109DirectChromaRepairBuffer.Length < scratchBytes)
        {
            _v74109DirectChromaRepairBuffer =
                GC.AllocateUninitializedArray<byte>(scratchBytes);
        }

        var uPlane = _v74109DirectChromaRepairBuffer.AsSpan(0, planeBytes);
        var vPlane = _v74109DirectChromaRepairBuffer.AsSpan(planeBytes, planeBytes);
        var uv = destination.Slice(yBytes, planeBytes * 2);
        for (var index = 0; index < planeBytes; index++)
        {
            uPlane[index] = uv[index * 2];
            vPlane[index] = uv[index * 2 + 1];
        }

        BinkChromaRepairV7243227.RepairInPlace(
            uPlane,
            vPlane,
            chromaWidth,
            chromaHeight,
            _moviePath);

        for (var index = 0; index < planeBytes; index++)
        {
            uv[index * 2] = uPlane[index];
            uv[index * 2 + 1] = vPlane[index];
        }

        var trace = Interlocked.Increment(
            ref _v74109DirectChromaRepairTraceCount);
        if (trace <= 16 || (trace & (trace - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[V74.0.109][DIRECT_YUV_CHROMA_REPAIR] " +
                $"count={trace} file='{Path.GetFileName(_moviePath)}' " +
                $"size={width}x{height} chroma={chromaWidth}x{chromaHeight} " +
                "luma_untouched=True bgra_roundtrip=False");
        }
    }

    // SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV
    private static long _v74105DirectYuvTraceCount;

    private static void ConvertPackedPgmYuvToNv12V74105(
        ReadOnlySpan<byte> payload,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int sourceChromaHeight,
        int targetWidth,
        int targetHeight,
        Span<byte> destination)
    {
        if (sourceWidth <= 0 || sourceHeight <= 0 ||
            sourceChromaWidth * 2 != sourceWidth ||
            sourceChromaHeight * 2 != sourceHeight ||
            targetWidth <= 0 || targetHeight <= 0 ||
            (targetWidth & 1) != 0 || (targetHeight & 1) != 0)
        {
            destination.Clear();
            return;
        }

        var sourceYBytes = checked(sourceWidth * sourceHeight);
        var requiredPayload = checked(
            sourceYBytes + sourceWidth * sourceChromaHeight);
        var targetYBytes = checked(targetWidth * targetHeight);
        var targetChromaWidth = targetWidth / 2;
        var targetChromaHeight = targetHeight / 2;
        var targetUvBytes = checked(targetChromaWidth * targetChromaHeight * 2);
        if (payload.Length < requiredPayload ||
            destination.Length < checked(targetYBytes + targetUvBytes))
        {
            destination.Clear();
            return;
        }

        var outY = destination[..targetYBytes];
        var outUv = destination.Slice(targetYBytes, targetUvBytes);

        // 3840x2160 -> 1920x1080 is the normal Demon's Souls path. Use an
        // explicit 2x2 box kernel so quality is retained without the generic
        // nested-loop/division overhead.
        if (sourceWidth == targetWidth * 2 &&
            sourceHeight == targetHeight * 2)
        {
            for (var ty = 0; ty < targetHeight; ty++)
            {
                var sy = ty * 2;
                var row0 = sy * sourceWidth;
                var row1 = row0 + sourceWidth;
                var dstRow = ty * targetWidth;
                for (var tx = 0; tx < targetWidth; tx++)
                {
                    var sx = tx * 2;
                    var sum = payload[row0 + sx] + payload[row0 + sx + 1] +
                              payload[row1 + sx] + payload[row1 + sx + 1];
                    outY[dstRow + tx] = (byte)((sum + 2) >> 2);
                }
            }

            // Source PGMYUV chroma rows are [U...][V...]. The source chroma
            // is 1920x1080 and target chroma 960x540, also an exact 2x2 box.
            for (var ty = 0; ty < targetChromaHeight; ty++)
            {
                var sy = ty * 2;
                var packedRow0 = sourceYBytes + sy * sourceWidth;
                var packedRow1 = packedRow0 + sourceWidth;
                var dstRow = ty * targetChromaWidth * 2;
                for (var tx = 0; tx < targetChromaWidth; tx++)
                {
                    var sx = tx * 2;
                    var u = payload[packedRow0 + sx] +
                            payload[packedRow0 + sx + 1] +
                            payload[packedRow1 + sx] +
                            payload[packedRow1 + sx + 1];
                    var v0 = packedRow0 + sourceChromaWidth + sx;
                    var v1 = packedRow1 + sourceChromaWidth + sx;
                    var v = payload[v0] + payload[v0 + 1] +
                            payload[v1] + payload[v1 + 1];
                    var dst = dstRow + tx * 2;
                    outUv[dst] = (byte)((u + 2) >> 2);
                    outUv[dst + 1] = (byte)((v + 2) >> 2);
                }
            }
            return;
        }

        // Generic nearest mapping is retained for non-2x UI assets. It avoids
        // any RGB round-trip and therefore preserves the original YUV values.
        for (var ty = 0; ty < targetHeight; ty++)
        {
            var sy = Math.Min(
                sourceHeight - 1,
                (int)((long)ty * sourceHeight / targetHeight));
            var srcRow = sy * sourceWidth;
            var dstRow = ty * targetWidth;
            for (var tx = 0; tx < targetWidth; tx++)
            {
                var sx = Math.Min(
                    sourceWidth - 1,
                    (int)((long)tx * sourceWidth / targetWidth));
                outY[dstRow + tx] = payload[srcRow + sx];
            }
        }

        for (var ty = 0; ty < targetChromaHeight; ty++)
        {
            var sy = Math.Min(
                sourceChromaHeight - 1,
                (int)((long)ty * sourceChromaHeight / targetChromaHeight));
            var packedRow = sourceYBytes + sy * sourceWidth;
            var dstRow = ty * targetChromaWidth * 2;
            for (var tx = 0; tx < targetChromaWidth; tx++)
            {
                var sx = Math.Min(
                    sourceChromaWidth - 1,
                    (int)((long)tx * sourceChromaWidth / targetChromaWidth));
                var dst = dstRow + tx * 2;
                outUv[dst] = payload[packedRow + sx];
                outUv[dst + 1] = payload[packedRow + sourceChromaWidth + sx];
            }
        }
    }

    // V72.4.3.2.13 PACKED_PGMYUV_BOX
    private static int _v7243213PackedDirectSerial;

    private static void ConvertPackedPgmYuvToBgraV7243213(
        ReadOnlySpan<byte> payload,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int sourceChromaHeight,
        int targetWidth,
        int targetHeight,
        Span<byte> destination,
        bool fullRange,
        bool swapUv)
    {
        if (sourceWidth <= 0 ||
            sourceHeight <= 0 ||
            sourceChromaWidth <= 0 ||
            sourceChromaHeight <= 0 ||
            targetWidth <= 0 ||
            targetHeight <= 0 ||
            sourceChromaWidth * 2 != sourceWidth ||
            sourceChromaHeight * 2 != sourceHeight)
        {
            destination.Clear();
            return;
        }

        var yBytes = checked(sourceWidth * sourceHeight);
        var packedChromaBytes =
            checked(sourceWidth * sourceChromaHeight);
        var requiredPayload =
            checked(yBytes + packedChromaBytes);
        var requiredDestination =
            checked(targetWidth * targetHeight * 4);

        if (payload.Length < requiredPayload ||
            destination.Length < requiredDestination)
        {
            destination.Clear();
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.packed_box_rejected " +
                $"source={sourceWidth}x{sourceHeight} " +
                $"target={targetWidth}x{targetHeight} " +
                $"payload={payload.Length}/{requiredPayload} " +
                $"dest={destination.Length}/{requiredDestination}");
            return;
        }

        var exactLumaScale =
            sourceWidth % targetWidth == 0 &&
            sourceHeight % targetHeight == 0;
        var lumaScaleX =
            exactLumaScale
                ? sourceWidth / targetWidth
                : 0;
        var lumaScaleY =
            exactLumaScale
                ? sourceHeight / targetHeight
                : 0;

        var exactChromaScale =
            sourceChromaWidth % targetWidth == 0 &&
            sourceChromaHeight % targetHeight == 0;
        var chromaScaleX =
            exactChromaScale
                ? sourceChromaWidth / targetWidth
                : 0;
        var chromaScaleY =
            exactChromaScale
                ? sourceChromaHeight / targetHeight
                : 0;

        // V72.4.3.2.13 EXACT_633_FAST
        // V72.4.3.2.17 REFERENCE_COLOR_CALIBRATED_ROW_SPLIT
        // V72.4.3.2.21 REFERENCE_NEUTRAL_GATE
        //
        // NihAV PGMYUV is kept in the decoder's verified row-split form:
        // each chroma row is [U...U][V...V]. V16's byte-interleaved
        // interpretation was rejected by the real V16 playback result.
        //
        // The centered chroma is then corrected by a Q14 linear transform
        // fitted to the user's supplied SharpEmu Demon's Souls reference
        // video at aligned serials 30, 120, 240 and 360. The transform has
        // no constant offset, so black/neutral chroma is not shifted by an
        // arbitrary global white-balance term.
        //
        // Set SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION=0 to disable the
        // reference transform without reverting the patch.
        var v7243217CalibrationSetting =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION");
        var v7243217ReferenceCalibration =
            !string.Equals(
                v7243217CalibrationSetting,
                "0",
                StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(
                v7243217CalibrationSetting,
                "false",
                StringComparison.OrdinalIgnoreCase);

        // Demon's Souls Bink assets are 3840x2160 while the host cap is
        // 640x360.  That is an exact 6x6 luma / 3x3 chroma footprint.
        // V72.4.3.2.12.1 used two nested loops for every output pixel.
        // Keep the same arithmetic, but unroll the 3x3 chroma sum and walk
        // source/output offsets incrementally.
        var exactFast633 =
            exactLumaScale &&
            exactChromaScale &&
            lumaScaleX == 6 &&
            lumaScaleY == 6 &&
            chromaScaleX == 3 &&
            chromaScaleY == 3;

        if (exactFast633)
        {
            for (var targetY = 0;
                 targetY < targetHeight;
                 targetY++)
            {
                var lumaRow0 =
                    (targetY * 6 + 2) * sourceWidth;
                var lumaRow1 =
                    lumaRow0 + sourceWidth;

                var packedRow0 =
                    yBytes +
                    (targetY * 3) * sourceWidth;
                var packedRow1 =
                    packedRow0 + sourceWidth;
                var packedRow2 =
                    packedRow1 + sourceWidth;

                var uRow0 = packedRow0;
                var uRow1 = packedRow1;
                var uRow2 = packedRow2;
                var vRow0 =
                    packedRow0 + sourceChromaWidth;
                var vRow1 =
                    packedRow1 + sourceChromaWidth;
                var vRow2 =
                    packedRow2 + sourceChromaWidth;

                var lumaX = 2;
                var chromaX = 0;
                var output =
                    targetY * targetWidth * 4;

                for (var targetX = 0;
                     targetX < targetWidth;
                     targetX++)
                {
                    var yy =
                        (byte)((
                            payload[lumaRow0 + lumaX] +
                            payload[lumaRow0 + lumaX + 1] +
                            payload[lumaRow1 + lumaX] +
                            payload[lumaRow1 + lumaX + 1] +
                            2) >> 2);

                    // V72.4.3.2.29.0.2 DIRECT_PACKED_BLOCK9_CHROMA
                    // Nine reads per plane, matching the old 3x3 read count,
                    // but sampled one 8x8 Bink chroma block apart.
                    var chromaCenterX = chromaX + 1;
                    var chromaCenterY = targetY * 3 + 1;

                    var uValue =
                        SampleV7243292PackedChromaBlock9(
                            payload,
                            yBytes,
                            sourceWidth,
                            sourceChromaWidth,
                            sourceChromaHeight,
                            chromaCenterX,
                            chromaCenterY,
                            vPlane: false);

                    var vValue =
                        SampleV7243292PackedChromaBlock9(
                            payload,
                            yBytes,
                            sourceWidth,
                            sourceChromaWidth,
                            sourceChromaHeight,
                            chromaCenterX,
                            chromaCenterY,
                            vPlane: true);

                    if (swapUv)
                    {
                        (uValue, vValue) =
                            (vValue, uValue);
                    }

                    var cbValue = uValue - 128;
                    var crValue = vValue - 128;

                    // V72.4.3.2.17 REFERENCE_CHROMA_Q14_EXACT
                    // Model: [Cb, Cr, Y] -> [Cb_ref, Cr_ref].
                    // Q14 coefficients fitted to aligned reference frames:
                    // Cb' = 0.735107 Cb - 0.893982 Cr - 0.046509 Y
                    // Cr' = -0.133484 Cb + 0.504089 Cr + 0.048767 Y
                    if (v7243217ReferenceCalibration && fullRange)
                    {
                        var cbAccumulator =
                            12044 * cbValue -
                            14647 * crValue -
                            762 * yy;
                        var crAccumulator =
                            -2187 * cbValue +
                            8259 * crValue +
                            799 * yy;

                        cbValue =
                            cbAccumulator >= 0
                                ? (cbAccumulator + 8192) >> 14
                                : -(((-cbAccumulator) + 8192) >> 14);
                        crValue =
                            crAccumulator >= 0
                                ? (crAccumulator + 8192) >> 14
                                : -(((-crAccumulator) + 8192) >> 14);

                        cbValue = Math.Clamp(cbValue, -128, 127);
                        crValue = Math.Clamp(crValue, -128, 127);
                    }

                    // V72.4.3.2.21 REFERENCE_NEUTRAL_PRECONVERT
                    ApplyV7243221ReferenceNeutralGate(
                        ref yy,
                        ref cbValue,
                        ref crValue);
                    ConvertBt709Sample(
                        yy,
                        cbValue,
                        crValue,
                        fullRange,
                        out var red,
                        out var green,
                        out var blue);

                    destination[output] =
                        (byte)Math.Clamp(blue, 0, 255);
                    destination[output + 1] =
                        (byte)Math.Clamp(green, 0, 255);
                    destination[output + 2] =
                        (byte)Math.Clamp(red, 0, 255);
                    destination[output + 3] = 255;

                    lumaX += 6;
                    chromaX += 3;
                    output += 4;
                }
            }
        }
        else
        {
        for (var targetY = 0;
             targetY < targetHeight;
             targetY++)
        {
            var lumaY0 =
                exactLumaScale
                    ? targetY * lumaScaleY
                    : (int)(((long)targetY *
                             sourceHeight) /
                            targetHeight);
            var lumaY1 =
                exactLumaScale
                    ? lumaY0 + lumaScaleY
                    : (int)(((long)(targetY + 1) *
                             sourceHeight) /
                            targetHeight);

            if (lumaY1 <= lumaY0)
            {
                lumaY1 = Math.Min(
                    sourceHeight,
                    lumaY0 + 1);
            }

            var centerY0 =
                lumaY0 +
                Math.Max(0, (lumaY1 - lumaY0 - 1) / 2);
            var centerY1 =
                Math.Min(
                    lumaY1 - 1,
                    centerY0 + 1);

            var chromaY0 =
                exactChromaScale
                    ? targetY * chromaScaleY
                    : (int)(((long)targetY *
                             sourceChromaHeight) /
                            targetHeight);
            var chromaY1 =
                exactChromaScale
                    ? chromaY0 + chromaScaleY
                    : (int)(((long)(targetY + 1) *
                             sourceChromaHeight) /
                            targetHeight);

            if (chromaY1 <= chromaY0)
            {
                chromaY1 = Math.Min(
                    sourceChromaHeight,
                    chromaY0 + 1);
            }

            var outputRow =
                targetY * targetWidth * 4;

            for (var targetX = 0;
                 targetX < targetWidth;
                 targetX++)
            {
                var lumaX0 =
                    exactLumaScale
                        ? targetX * lumaScaleX
                        : (int)(((long)targetX *
                                 sourceWidth) /
                                targetWidth);
                var lumaX1 =
                    exactLumaScale
                        ? lumaX0 + lumaScaleX
                        : (int)(((long)(targetX + 1) *
                                 sourceWidth) /
                                targetWidth);

                if (lumaX1 <= lumaX0)
                {
                    lumaX1 = Math.Min(
                        sourceWidth,
                        lumaX0 + 1);
                }

                var centerX0 =
                    lumaX0 +
                    Math.Max(
                        0,
                        (lumaX1 - lumaX0 - 1) / 2);
                var centerX1 =
                    Math.Min(
                        lumaX1 - 1,
                        centerX0 + 1);

                var y00 =
                    payload[
                        centerY0 * sourceWidth +
                        centerX0];
                var y01 =
                    payload[
                        centerY0 * sourceWidth +
                        centerX1];
                var y10 =
                    payload[
                        centerY1 * sourceWidth +
                        centerX0];
                var y11 =
                    payload[
                        centerY1 * sourceWidth +
                        centerX1];

                // V72.4.3.2.13 BUILD FIX:
                // Four byte samples average to 0..255, so preserve the
                // decoder's byte-domain contract explicitly.
                var yy =
                    (byte)((y00 + y01 + y10 + y11 + 2) >> 2);

                var chromaX0 =
                    exactChromaScale
                        ? targetX * chromaScaleX
                        : (int)(((long)targetX *
                                 sourceChromaWidth) /
                                targetWidth);
                var chromaX1 =
                    exactChromaScale
                        ? chromaX0 + chromaScaleX
                        : (int)(((long)(targetX + 1) *
                                 sourceChromaWidth) /
                                targetWidth);

                if (chromaX1 <= chromaX0)
                {
                    chromaX1 = Math.Min(
                        sourceChromaWidth,
                        chromaX0 + 1);
                }

                var sumU = 0;
                var sumV = 0;
                var chromaSamples = 0;

                for (var chromaY = chromaY0;
                     chromaY < chromaY1;
                     chromaY++)
                {
                    var packedRow =
                        yBytes +
                        chromaY * sourceWidth;
                    var uRow = packedRow;
                    var vRow =
                        packedRow + sourceChromaWidth;

                    for (var chromaX = chromaX0;
                         chromaX < chromaX1;
                         chromaX++)
                    {
                        sumU += payload[uRow + chromaX];
                        sumV += payload[vRow + chromaX];
                        chromaSamples++;
                    }
                }

                if (chromaSamples <= 0)
                {
                    chromaSamples = 1;
                    sumU = 128;
                    sumV = 128;
                }

                var uValue =
                    (sumU + chromaSamples / 2) /
                    chromaSamples;
                var vValue =
                    (sumV + chromaSamples / 2) /
                    chromaSamples;

                if (swapUv)
                {
                    (uValue, vValue) =
                        (vValue, uValue);
                }

                var cbValue = uValue - 128;
                var crValue = vValue - 128;

                // V72.4.3.2.17 REFERENCE_CHROMA_Q14_GENERIC
                if (v7243217ReferenceCalibration && fullRange)
                {
                    var cbAccumulator =
                        12044 * cbValue -
                        14647 * crValue -
                        762 * yy;
                    var crAccumulator =
                        -2187 * cbValue +
                        8259 * crValue +
                        799 * yy;

                    cbValue =
                        cbAccumulator >= 0
                            ? (cbAccumulator + 8192) >> 14
                            : -(((-cbAccumulator) + 8192) >> 14);
                    crValue =
                        crAccumulator >= 0
                            ? (crAccumulator + 8192) >> 14
                            : -(((-crAccumulator) + 8192) >> 14);

                    cbValue = Math.Clamp(cbValue, -128, 127);
                    crValue = Math.Clamp(crValue, -128, 127);
                }

                // V72.4.3.2.21 REFERENCE_NEUTRAL_PRECONVERT
                ApplyV7243221ReferenceNeutralGate(
                    ref yy,
                    ref cbValue,
                    ref crValue);
                ConvertBt709Sample(
                    yy,
                    cbValue,
                    crValue,
                    fullRange,
                    out var red,
                    out var green,
                    out var blue);

                var output =
                    outputRow + targetX * 4;

                destination[output] =
                    (byte)Math.Clamp(blue, 0, 255);
                destination[output + 1] =
                    (byte)Math.Clamp(green, 0, 255);
                destination[output + 2] =
                    (byte)Math.Clamp(red, 0, 255);
                destination[output + 3] = 255;
            }
        }

        }

        var serial =
            System.Threading.Interlocked.Increment(
                ref _v7243213PackedDirectSerial);

        // V72.4.3.2.15.1 RAW_CHROMA_LAYOUT_TRUTH_240
        // V14 never reached serial 360 before the first host movie ended.
        // Serial 240 is reached and already shows the green corruption.
        if (serial == 240)
        {
            TryDumpV7243214RawChromaLayoutTruth(
                serial,
                payload,
                sourceWidth,
                sourceHeight,
                sourceChromaWidth,
                sourceChromaHeight,
                targetWidth,
                targetHeight,
                fullRange);
        }

        // V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED
        if (serial == 30 ||
            serial == 120 ||
            serial == 240 ||
            serial == 360 ||
            serial == 600 ||
            serial == 720 ||
            serial == 840 ||
            serial == 1200 ||
            serial == 1800 ||
            serial == 2400 ||
            serial == 3000 ||
            serial == 3600 ||
            serial == 4080)
        {
            TryDumpV7243213PackedFrameTruth(
                serial,
                targetWidth,
                targetHeight,
                destination);
        }

        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_LOG_BINK2") == "1" &&
            (serial <= 3 || serial % 120 == 0))
        {
            var lumaStepX =
                (double)sourceWidth / targetWidth;
            var lumaStepY =
                (double)sourceHeight / targetHeight;
            var chromaStepX =
                (double)sourceChromaWidth / targetWidth;
            var chromaStepY =
                (double)sourceChromaHeight / targetHeight;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.packed_box_fast_scale " +
                $"serial={serial} " +
                $"source={sourceWidth}x{sourceHeight} " +
                $"target={targetWidth}x{targetHeight} " +
                $"luma_step={lumaStepX:F2}x{lumaStepY:F2} " +
                $"chroma_box={chromaStepX:F2}x{chromaStepY:F2} " +
                $"exact_luma={exactLumaScale} " +
                $"exact_chroma={exactChromaScale} " +
                (exactFast633
                    ? "path=exact633-row-split-refcal-neutral-block9 luma=center-2x2 chroma=block9 "
                    : "path=generic-row-split-refcal-neutral luma=center-2x2 chroma=box ") +
                $"layout=row_split_uv " +
                $"reference_calibration={v7243217ReferenceCalibration && fullRange} " +
                $"reference_neutral_gate=True " +
                $"ref=ZtQIS8fJNwI q14=12044,-14647,-762;-2187,8259,799 " +
                $"full_range={fullRange} swap_uv={swapUv}");
        }
    }

    // V72.4.3.2.14 RAW_CHROMA_LAYOUT_TRUTH
    private static int _v7243214RawChromaTruthDumped;

    private enum V7243214ChromaLayout
    {
        RowSplitUv,
        RowSplitVu,
        PlanarUv,
        PlanarVu,
        InterleavedUv,
        InterleavedVu,
    }

    private static void TryDumpV7243214RawChromaLayoutTruth(
        int serial,
        ReadOnlySpan<byte> payload,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int sourceChromaHeight,
        int targetWidth,
        int targetHeight,
        bool fullRange)
    {
        var dumpDirectory =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_RAW_PGMYUV_TRUTH_DIR");

        if (string.IsNullOrWhiteSpace(dumpDirectory) ||
            System.Threading.Interlocked.CompareExchange(
                ref _v7243214RawChromaTruthDumped,
                1,
                0) != 0)
        {
            return;
        }

        try
        {
            var yBytes = checked(sourceWidth * sourceHeight);
            var chromaBytes = checked(
                sourceWidth * sourceChromaHeight);
            var required = checked(yBytes + chromaBytes);

            if (payload.Length < required)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.raw_chroma_truth_failed " +
                    $"serial={serial} reason='payload-too-small' " +
                    $"payload={payload.Length}/{required}");
                return;
            }

            System.IO.Directory.CreateDirectory(
                dumpDirectory);

            var rawPath =
                System.IO.Path.Combine(
                    dumpDirectory,
                    $"frame_{serial:D4}_source.pgmyuv");

            using (var raw =
                new System.IO.FileStream(
                    rawPath,
                    System.IO.FileMode.Create,
                    System.IO.FileAccess.Write,
                    System.IO.FileShare.Read))
            {
                raw.Write(payload[..required]);
            }

            var metaPath =
                System.IO.Path.Combine(
                    dumpDirectory,
                    $"frame_{serial:D4}_source.txt");

            System.IO.File.WriteAllText(
                metaPath,
                "SharpEmu V72.4.3.2.14 RAW CHROMA LAYOUT TRUTH\n" +
                $"serial={serial}\n" +
                $"source={sourceWidth}x{sourceHeight}\n" +
                $"chroma={sourceChromaWidth}x{sourceChromaHeight}\n" +
                $"target={targetWidth}x{targetHeight}\n" +
                $"payload_bytes={required}\n" +
                $"y_bytes={yBytes}\n" +
                $"packed_chroma_bytes={chromaBytes}\n" +
                $"full_range={fullRange}\n" +
                "candidate_layouts=row_split_uv,row_split_vu," +
                "planar_uv,planar_vu,interleaved_uv,interleaved_vu\n",
                new System.Text.UTF8Encoding(false));

            foreach (var layout in
                System.Enum.GetValues<V7243214ChromaLayout>())
            {
                TryWriteV7243214LayoutCandidate(
                    dumpDirectory,
                    serial,
                    payload[..required],
                    sourceWidth,
                    sourceHeight,
                    sourceChromaWidth,
                    sourceChromaHeight,
                    targetWidth,
                    targetHeight,
                    fullRange,
                    layout);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.raw_chroma_truth " +
                $"serial={serial} source={sourceWidth}x{sourceHeight} " +
                $"target={targetWidth}x{targetHeight} bytes={required} " +
                $"dir='{dumpDirectory}'");
        }
        catch (Exception exception) when (
            exception is IOException or
            UnauthorizedAccessException or
            ArgumentException or
            OverflowException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.raw_chroma_truth_failed " +
                $"serial={serial} reason='" +
                exception.Message
                    .Replace('\r', ' ')
                    .Replace('\n', ' ') +
                "'");
        }
    }

    private static void TryWriteV7243214LayoutCandidate(
        string dumpDirectory,
        int serial,
        ReadOnlySpan<byte> payload,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int sourceChromaHeight,
        int targetWidth,
        int targetHeight,
        bool fullRange,
        V7243214ChromaLayout layout)
    {
        if (sourceWidth != sourceChromaWidth * 2 ||
            sourceHeight != sourceChromaHeight * 2 ||
            sourceWidth % targetWidth != 0 ||
            sourceHeight % targetHeight != 0 ||
            sourceChromaWidth % targetWidth != 0 ||
            sourceChromaHeight % targetHeight != 0)
        {
            return;
        }

        var lumaScaleX = sourceWidth / targetWidth;
        var lumaScaleY = sourceHeight / targetHeight;
        var chromaScaleX =
            sourceChromaWidth / targetWidth;
        var chromaScaleY =
            sourceChromaHeight / targetHeight;

        var yBytes = checked(sourceWidth * sourceHeight);
        var planeBytes =
            checked(sourceChromaWidth * sourceChromaHeight);

        var rgb =
            new byte[checked(targetWidth * targetHeight * 3)];

        for (var targetY = 0;
             targetY < targetHeight;
             targetY++)
        {
            var lumaY =
                targetY * lumaScaleY +
                Math.Max(0, (lumaScaleY - 2) / 2);
            var lumaY2 =
                Math.Min(
                    sourceHeight - 1,
                    lumaY + 1);

            var chromaY0 =
                targetY * chromaScaleY;

            for (var targetX = 0;
                 targetX < targetWidth;
                 targetX++)
            {
                var lumaX =
                    targetX * lumaScaleX +
                    Math.Max(0, (lumaScaleX - 2) / 2);
                var lumaX2 =
                    Math.Min(
                        sourceWidth - 1,
                        lumaX + 1);

                var yy =
                    (byte)((
                        payload[lumaY * sourceWidth + lumaX] +
                        payload[lumaY * sourceWidth + lumaX2] +
                        payload[lumaY2 * sourceWidth + lumaX] +
                        payload[lumaY2 * sourceWidth + lumaX2] +
                        2) >> 2);

                var chromaX0 =
                    targetX * chromaScaleX;
                var sumU = 0;
                var sumV = 0;
                var samples = 0;

                for (var dy = 0;
                     dy < chromaScaleY;
                     dy++)
                {
                    var cy = chromaY0 + dy;

                    for (var dx = 0;
                         dx < chromaScaleX;
                         dx++)
                    {
                        var cx = chromaX0 + dx;
                        GetV7243214ChromaSample(
                            payload,
                            yBytes,
                            planeBytes,
                            sourceWidth,
                            sourceChromaWidth,
                            cy,
                            cx,
                            layout,
                            out var u,
                            out var v);

                        sumU += u;
                        sumV += v;
                        samples++;
                    }
                }

                var uValue =
                    (sumU + samples / 2) / samples;
                var vValue =
                    (sumV + samples / 2) / samples;

                ConvertBt709Sample(
                    yy,
                    uValue - 128,
                    vValue - 128,
                    fullRange,
                    out var red,
                    out var green,
                    out var blue);

                var output =
                    (targetY * targetWidth + targetX) * 3;

                rgb[output] =
                    (byte)Math.Clamp(red, 0, 255);
                rgb[output + 1] =
                    (byte)Math.Clamp(green, 0, 255);
                rgb[output + 2] =
                    (byte)Math.Clamp(blue, 0, 255);
            }
        }

        var layoutName =
            layout switch
            {
                V7243214ChromaLayout.RowSplitUv =>
                    "row_split_uv",
                V7243214ChromaLayout.RowSplitVu =>
                    "row_split_vu",
                V7243214ChromaLayout.PlanarUv =>
                    "planar_uv",
                V7243214ChromaLayout.PlanarVu =>
                    "planar_vu",
                V7243214ChromaLayout.InterleavedUv =>
                    "interleaved_uv",
                _ =>
                    "interleaved_vu",
            };

        var path =
            System.IO.Path.Combine(
                dumpDirectory,
                $"frame_{serial:D4}_{layoutName}.ppm");

        using var stream =
            new System.IO.FileStream(
                path,
                System.IO.FileMode.Create,
                System.IO.FileAccess.Write,
                System.IO.FileShare.Read);

        var header =
            System.Text.Encoding.ASCII.GetBytes(
                $"P6\n{targetWidth} {targetHeight}\n255\n");

        stream.Write(header, 0, header.Length);
        stream.Write(rgb, 0, rgb.Length);
    }

    private static void GetV7243214ChromaSample(
        ReadOnlySpan<byte> payload,
        int yBytes,
        int planeBytes,
        int sourceWidth,
        int sourceChromaWidth,
        int chromaY,
        int chromaX,
        V7243214ChromaLayout layout,
        out int u,
        out int v)
    {
        switch (layout)
        {
            case V7243214ChromaLayout.RowSplitUv:
            case V7243214ChromaLayout.RowSplitVu:
            {
                var row =
                    yBytes +
                    chromaY * sourceWidth;
                var first =
                    payload[row + chromaX];
                var second =
                    payload[
                        row +
                        sourceChromaWidth +
                        chromaX];

                if (layout ==
                    V7243214ChromaLayout.RowSplitUv)
                {
                    u = first;
                    v = second;
                }
                else
                {
                    u = second;
                    v = first;
                }

                return;
            }

            case V7243214ChromaLayout.PlanarUv:
            case V7243214ChromaLayout.PlanarVu:
            {
                var offset =
                    chromaY * sourceChromaWidth +
                    chromaX;
                var first =
                    payload[yBytes + offset];
                var second =
                    payload[yBytes + planeBytes + offset];

                if (layout ==
                    V7243214ChromaLayout.PlanarUv)
                {
                    u = first;
                    v = second;
                }
                else
                {
                    u = second;
                    v = first;
                }

                return;
            }

            default:
            {
                var offset =
                    yBytes +
                    chromaY * sourceWidth +
                    chromaX * 2;
                var first = payload[offset];
                var second = payload[offset + 1];

                if (layout ==
                    V7243214ChromaLayout.InterleavedUv)
                {
                    u = first;
                    v = second;
                }
                else
                {
                    u = second;
                    v = first;
                }

                return;
            }
        }
    }

    // V72.4.3.2.21 REFERENCE_NEUTRAL_GATE_HELPER
    //
    // V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX
    //
    // cbValue/crValue reaching this helper are already centered signed chroma
    // values (-128..127). V21/V22 subtracted 128 a second time, so neutral
    // chroma (0,0) was measured as (-128,-128) and almost always rejected.
    //
    // Operate in the correct centered domain. Keep the gate conservative:
    // only bright, genuinely near-neutral samples are pulled toward zero tint.
    private static void ApplyV7243221ReferenceNeutralGate(
        ref byte yy,
        ref int cbValue,
        ref int crValue)
    {
        var yyValue = (int)yy;
        var cbDelta = cbValue;
        var crDelta = crValue;
        var chromaMagnitude =
            Math.Abs(cbDelta) +
            Math.Abs(crDelta);

        if (yyValue < 144 ||
            chromaMagnitude > 32)
        {
            return;
        }

        var lumaStrength =
            Math.Clamp(
                (yyValue - 144) * 3,
                0,
                192);
        var neutralStrength =
            (Math.Clamp(32 - chromaMagnitude, 0, 32) * 255 + 16) /
            32;
        var strength =
            (lumaStrength * neutralStrength + 127) /
            255;

        if (strength <= 0)
        {
            return;
        }

        // Mild highlight lift; do not repeat V22's full-strength washout.
        yyValue +=
            ((255 - yyValue) * strength + 511) /
            1024;

        cbValue =
            (cbDelta * (255 - strength) + 127) /
            255;
        crValue =
            (crDelta * (255 - strength) + 127) /
            255;

        yy = (byte)Math.Clamp(yyValue, 0, 255);
        cbValue = Math.Clamp(cbValue, -128, 127);
        crValue = Math.Clamp(crValue, -128, 127);
    }

    // V72.4.3.2.29.0.2 DIRECT_PACKED_BLOCK9_CHROMA
    //
    // V29's 7x7 box crossed the bad Bink2 chroma boundaries, but performing
    // 49 reads per plane for every output pixel raised conversion from ~20 ms
    // to ~122-126 ms/frame.
    //
    // Use nine samples instead: the current chroma position plus the same
    // position in the eight neighbouring 8x8 source-chroma blocks. This keeps
    // the read count equal to the old 3x3 box (9 reads/plane) while averaging
    // block DC/bias discontinuities across block boundaries.
    private static int SampleV7243292PackedChromaBlock9(
        ReadOnlySpan<byte> payload,
        int yBytes,
        int sourceWidth,
        int sourceChromaWidth,
        int sourceChromaHeight,
        int centerX,
        int centerY,
        bool vPlane)
    {
        var left =
            Math.Max(0, centerX - 8);
        var right =
            Math.Min(sourceChromaWidth - 1, centerX + 8);
        var up =
            Math.Max(0, centerY - 8);
        var down =
            Math.Min(sourceChromaHeight - 1, centerY + 8);

        var centerClampedX =
            Math.Clamp(centerX, 0, sourceChromaWidth - 1);
        var centerClampedY =
            Math.Clamp(centerY, 0, sourceChromaHeight - 1);

        var planeOffset =
            vPlane
                ? sourceChromaWidth
                : 0;

        var upRow =
            yBytes +
            up * sourceWidth +
            planeOffset;
        var centerRow =
            yBytes +
            centerClampedY * sourceWidth +
            planeOffset;
        var downRow =
            yBytes +
            down * sourceWidth +
            planeOffset;

        var sum =
            payload[upRow + left] +
            payload[upRow + centerClampedX] +
            payload[upRow + right] +
            payload[centerRow + left] +
            payload[centerRow + centerClampedX] +
            payload[centerRow + right] +
            payload[downRow + left] +
            payload[downRow + centerClampedX] +
            payload[downRow + right];

        return (sum + 4) / 9;
    }

    private static void TryDumpV7243213PackedFrameTruth(
        int serial,
        int width,
        int height,
        ReadOnlySpan<byte> bgra)
    {
        var dumpDirectory =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_FRAME_TRUTH_DIR");

        if (string.IsNullOrWhiteSpace(dumpDirectory))
        {
            return;
        }

        try
        {
            System.IO.Directory.CreateDirectory(
                dumpDirectory);

            var path =
                System.IO.Path.Combine(
                    dumpDirectory,
                    $"frame_{serial:D4}_packed_box_fast.ppm");

            using var stream =
                new System.IO.FileStream(
                    path,
                    System.IO.FileMode.Create,
                    System.IO.FileAccess.Write,
                    System.IO.FileShare.Read);

            var header =
                System.Text.Encoding.ASCII.GetBytes(
                    $"P6\n{width} {height}\n255\n");

            stream.Write(
                header,
                0,
                header.Length);

            var rgbRow =
                new byte[checked(width * 3)];

            for (var y = 0; y < height; y++)
            {
                var inputRow =
                    y * width * 4;

                for (var x = 0; x < width; x++)
                {
                    var input =
                        inputRow + x * 4;
                    var output = x * 3;

                    rgbRow[output] =
                        bgra[input + 2];
                    rgbRow[output + 1] =
                        bgra[input + 1];
                    rgbRow[output + 2] =
                        bgra[input];
                }

                stream.Write(
                    rgbRow,
                    0,
                    rgbRow.Length);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.packed_box_fast_frame_truth " +
                $"serial={serial} " +
                $"size={width}x{height} " +
                $"path='{path}'");
        }
        catch (Exception exception) when (
            exception is IOException or
            UnauthorizedAccessException or
            ArgumentException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.packed_box_fast_frame_truth_failed " +
                $"serial={serial} reason='" +
                exception.Message
                    .Replace('\r', ' ')
                    .Replace('\n', ' ') +
                "'");
        }
    }

    private static void SwapEqualPlanes(Span<byte> first, Span<byte> second)
    {
        if (first.Length != second.Length)
        {
            throw new ArgumentException("Chroma plane lengths must match.");
        }

        for (var index = 0; index < first.Length; index++)
        {
            (first[index], second[index]) = (second[index], first[index]);
        }
    }
    // V72.4.3.2.2 EXACT_BT709_I420
    // V72.4.3.2.3 GEOMETRY_SAFE_BT709
    // V72.4.3.2.5 SOURCE_TO_OUTPUT_BT709_SCALE
    //
    // NIHAV exposes the decoded/repacked I420 planes at the source movie
    // geometry (for Demon's Souls boot movies: 3840x2160), while the BGRA
    // destination is allocated at the selected host output geometry
    // (for this policy: 640x360). Converting with source width against the
    // smaller destination produced only 60 rows and a nearly black frame.
    //
    // Resolve the destination geometry, then sample the source I420 planes
    // into the destination BGRA frame. This is a scaler, not a crop.
    // V72.4.3.2.6 PGMYUV_LAYOUT_AUTO
    //
    // NihAV PGMYUV stores 4:2:0 chroma side-by-side below Y. Older SharpEmu
    // lineages have also exposed already-deinterleaved U/V spans. Support both
    // representations and choose the smoother chroma interpretation per frame.
    // V72.4.3.2.7.2 FRAME_TRUTH_PLANAR
    //
    // V72.4.3.2.6 selected the already-planar U/V interpretation on
    // 737/741 frames. Lock that verified representation and stop changing
    // chroma layout from frame to frame. The frame-truth probe can dump a
    // handful of downscaled Y/U/V planes plus normal/swapped/luma RGB views
    // so corruption can be located before any further renderer changes.
    private static int _v724327FrameTruthSerial;

    // V72.4.3.2.11 PLANAR_FAST_SCALE
    //
    // V72.4.3.2.10 proved that reinterpreting the two existing chroma spans
    // as U-row/V-row is wrong for the current NihAV streaming output: captured
    // U and V became >99.8% correlated and color regressed to magenta/green.
    //
    // Restore independent planar U/V spans. For 3840x2160 -> 640x360 the
    // scale ratio is exactly 6x6, so the hot path avoids per-pixel division.
    private static void ConvertYuv420ToBgraBt709Exact(
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int width,
        int height,
        int chromaWidth,
        Span<byte> destination,
        bool fullRange)
    {
        if (width <= 0 ||
            height <= 0 ||
            chromaWidth <= 0 ||
            destination.Length < 4)
        {
            destination.Clear();
            return;
        }

        var destinationPixels = destination.Length / 4;
        if (destinationPixels <= 0)
        {
            destination.Clear();
            return;
        }

        var targetWidth = 0;
        var targetHeight = 0;

        if (int.TryParse(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_OUTPUT_MAX_WIDTH"),
                out var configuredWidth) &&
            int.TryParse(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT"),
                out var configuredHeight) &&
            configuredWidth > 0 &&
            configuredHeight > 0 &&
            checked(configuredWidth * configuredHeight) == destinationPixels)
        {
            targetWidth = configuredWidth;
            targetHeight = configuredHeight;
        }

        if (targetWidth <= 0 || targetHeight <= 0)
        {
            var aspect = (double)width / height;
            targetWidth = Math.Max(
                1,
                (int)Math.Round(Math.Sqrt(destinationPixels * aspect)));

            while (targetWidth > 1 &&
                   destinationPixels % targetWidth != 0)
            {
                targetWidth--;
            }

            targetHeight = destinationPixels / targetWidth;
        }

        if (checked(targetWidth * targetHeight) != destinationPixels)
        {
            destination.Clear();
            return;
        }

        var sourceChromaHeight = (height + 1) / 2;
        var requiredY = checked(width * height);
        var requiredChroma = checked(
            chromaWidth * sourceChromaHeight);

        if (yPlane.Length < requiredY ||
            uPlane.Length < requiredChroma ||
            vPlane.Length < requiredChroma)
        {
            destination.Clear();
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.planar_fast_rejected " +
                $"source={width}x{height} " +
                $"chroma={chromaWidth}x{sourceChromaHeight} " +
                $"y={yPlane.Length}/{requiredY} " +
                $"u={uPlane.Length}/{requiredChroma} " +
                $"v={vPlane.Length}/{requiredChroma}");
            return;
        }

        var exactScale =
            width % targetWidth == 0 &&
            height % targetHeight == 0;

        var scaleX = exactScale
            ? width / targetWidth
            : 0;
        var scaleY = exactScale
            ? height / targetHeight
            : 0;

        for (var targetY = 0; targetY < targetHeight; targetY++)
        {
            var sourceY = exactScale
                ? targetY * scaleY
                : (int)(((long)targetY * height) / targetHeight);

            sourceY = Math.Min(sourceY, height - 1);

            var sourceLumaRow = sourceY * width;
            var sourceChromaRow =
                Math.Min(sourceY >> 1, sourceChromaHeight - 1) *
                chromaWidth;
            var targetRow = targetY * targetWidth * 4;

            if (exactScale)
            {
                var sourceX = 0;
                for (var targetX = 0;
                     targetX < targetWidth;
                     targetX++, sourceX += scaleX)
                {
                    var yy = yPlane[sourceLumaRow + sourceX];
                    var chromaIndex =
                        sourceChromaRow +
                        Math.Min(sourceX >> 1, chromaWidth - 1);

                    ConvertBt709Sample(
                        yy,
                        (int)uPlane[chromaIndex] - 128,
                        (int)vPlane[chromaIndex] - 128,
                        fullRange,
                        out var red,
                        out var green,
                        out var blue);

                    var output = targetRow + targetX * 4;
                    destination[output] =
                        (byte)Math.Clamp(blue, 0, 255);
                    destination[output + 1] =
                        (byte)Math.Clamp(green, 0, 255);
                    destination[output + 2] =
                        (byte)Math.Clamp(red, 0, 255);
                    destination[output + 3] = 255;
                }
            }
            else
            {
                for (var targetX = 0;
                     targetX < targetWidth;
                     targetX++)
                {
                    var sourceX = Math.Min(
                        width - 1,
                        (int)(((long)targetX * width) /
                              targetWidth));

                    var yy = yPlane[sourceLumaRow + sourceX];
                    var chromaIndex =
                        sourceChromaRow +
                        Math.Min(sourceX >> 1, chromaWidth - 1);

                    ConvertBt709Sample(
                        yy,
                        (int)uPlane[chromaIndex] - 128,
                        (int)vPlane[chromaIndex] - 128,
                        fullRange,
                        out var red,
                        out var green,
                        out var blue);

                    var output = targetRow + targetX * 4;
                    destination[output] =
                        (byte)Math.Clamp(blue, 0, 255);
                    destination[output + 1] =
                        (byte)Math.Clamp(green, 0, 255);
                    destination[output + 2] =
                        (byte)Math.Clamp(red, 0, 255);
                    destination[output + 3] = 255;
                }
            }
        }

        var frameTruthSerial =
            System.Threading.Interlocked.Increment(
                ref _v724327FrameTruthSerial);

        if (frameTruthSerial == 30 ||
            frameTruthSerial == 120 ||
            frameTruthSerial == 240 ||
            frameTruthSerial == 360 ||
            frameTruthSerial == 600 ||
            frameTruthSerial == 720)
        {
            TryDumpV7243211PlanarFrameTruth(
                frameTruthSerial,
                yPlane,
                uPlane,
                vPlane,
                width,
                height,
                chromaWidth,
                targetWidth,
                targetHeight,
                destination,
                fullRange);
        }

        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_LOG_BINK2") == "1" &&
            (frameTruthSerial <= 3 ||
             frameTruthSerial % 120 == 0))
        {
            var scaleDescription = exactScale
                ? $"{scaleX}x{scaleY}"
                : "fractional";

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.planar_fast_scale " +
                $"serial={frameTruthSerial} " +
                $"source={width}x{height} " +
                $"target={targetWidth}x{targetHeight} " +
                $"chroma={chromaWidth}x{sourceChromaHeight} " +
                $"exact_scale={exactScale} " +
                $"step={scaleDescription} layout=planar");

            Console.Error.WriteLine(
                $"[LOADER][TRACE] bink2.bt709_source_scale " +
                $"source={width}x{height} " +
                $"target={targetWidth}x{targetHeight} " +
                $"layout=planar-fast " +
                $"dest_bytes={destination.Length} " +
                $"full_range={fullRange} serial={frameTruthSerial}");
        }
    }

    private static void TryDumpV7243211PlanarFrameTruth(
        int serial,
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int targetWidth,
        int targetHeight,
        ReadOnlySpan<byte> normalBgra,
        bool fullRange)
    {
        var dumpDirectory =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_FRAME_TRUTH_DIR");

        if (string.IsNullOrWhiteSpace(dumpDirectory))
        {
            return;
        }

        try
        {
            System.IO.Directory.CreateDirectory(dumpDirectory);

            var prefix = System.IO.Path.Combine(
                dumpDirectory,
                $"frame_{serial:D4}");

            var targetChromaWidth = (targetWidth + 1) / 2;
            var targetChromaHeight = (targetHeight + 1) / 2;
            var sourceChromaHeight = (sourceHeight + 1) / 2;

            var targetY = new byte[
                checked(targetWidth * targetHeight)];
            var targetU = new byte[
                checked(targetChromaWidth * targetChromaHeight)];
            var targetV = new byte[targetU.Length];

            var exactYScale =
                sourceWidth % targetWidth == 0 &&
                sourceHeight % targetHeight == 0;
            var yScaleX = exactYScale
                ? sourceWidth / targetWidth
                : 0;
            var yScaleY = exactYScale
                ? sourceHeight / targetHeight
                : 0;

            for (var y = 0; y < targetHeight; y++)
            {
                var sourceY = exactYScale
                    ? y * yScaleY
                    : Math.Min(
                        sourceHeight - 1,
                        (int)(((long)y * sourceHeight) /
                              targetHeight));

                var sourceRow = sourceY * sourceWidth;
                var targetRow = y * targetWidth;

                if (exactYScale)
                {
                    var sourceX = 0;
                    for (var x = 0;
                         x < targetWidth;
                         x++, sourceX += yScaleX)
                    {
                        targetY[targetRow + x] =
                            yPlane[sourceRow + sourceX];
                    }
                }
                else
                {
                    for (var x = 0; x < targetWidth; x++)
                    {
                        var sourceX = Math.Min(
                            sourceWidth - 1,
                            (int)(((long)x * sourceWidth) /
                                  targetWidth));

                        targetY[targetRow + x] =
                            yPlane[sourceRow + sourceX];
                    }
                }
            }

            var exactChromaScale =
                sourceChromaWidth % targetChromaWidth == 0 &&
                sourceChromaHeight % targetChromaHeight == 0;
            var chromaScaleX = exactChromaScale
                ? sourceChromaWidth / targetChromaWidth
                : 0;
            var chromaScaleY = exactChromaScale
                ? sourceChromaHeight / targetChromaHeight
                : 0;

            for (var y = 0; y < targetChromaHeight; y++)
            {
                var sourceY = exactChromaScale
                    ? y * chromaScaleY
                    : Math.Min(
                        sourceChromaHeight - 1,
                        (int)(((long)y * sourceChromaHeight) /
                              targetChromaHeight));

                var sourceRow = sourceY * sourceChromaWidth;
                var targetRow = y * targetChromaWidth;

                if (exactChromaScale)
                {
                    var sourceX = 0;
                    for (var x = 0;
                         x < targetChromaWidth;
                         x++, sourceX += chromaScaleX)
                    {
                        var source = sourceRow + sourceX;
                        targetU[targetRow + x] = uPlane[source];
                        targetV[targetRow + x] = vPlane[source];
                    }
                }
                else
                {
                    for (var x = 0; x < targetChromaWidth; x++)
                    {
                        var sourceX = Math.Min(
                            sourceChromaWidth - 1,
                            (int)(((long)x * sourceChromaWidth) /
                                  targetChromaWidth));

                        var source = sourceRow + sourceX;
                        targetU[targetRow + x] = uPlane[source];
                        targetV[targetRow + x] = vPlane[source];
                    }
                }
            }

            WriteV724327Pgm(
                prefix + "_Y.pgm",
                targetWidth,
                targetHeight,
                targetY);
            WriteV724327Pgm(
                prefix + "_U.pgm",
                targetChromaWidth,
                targetChromaHeight,
                targetU);
            WriteV724327Pgm(
                prefix + "_V.pgm",
                targetChromaWidth,
                targetChromaHeight,
                targetV);

            WriteV724327PpmFromBgra(
                prefix + "_normal.ppm",
                targetWidth,
                targetHeight,
                normalBgra);

            var swappedBgra = new byte[normalBgra.Length];
            RenderV724327ProbeBgra(
                targetY,
                targetU,
                targetV,
                targetWidth,
                targetHeight,
                fullRange,
                swapUv: true,
                neutralChroma: false,
                swappedBgra);
            WriteV724327PpmFromBgra(
                prefix + "_swapped.ppm",
                targetWidth,
                targetHeight,
                swappedBgra);

            var lumaBgra = new byte[normalBgra.Length];
            RenderV724327ProbeBgra(
                targetY,
                targetU,
                targetV,
                targetWidth,
                targetHeight,
                fullRange,
                swapUv: false,
                neutralChroma: true,
                lumaBgra);
            WriteV724327PpmFromBgra(
                prefix + "_luma.ppm",
                targetWidth,
                targetHeight,
                lumaBgra);

            GetV724327PlaneStats(
                targetY,
                out var yMin,
                out var yMax,
                out var yMean);
            GetV724327PlaneStats(
                targetU,
                out var uMin,
                out var uMax,
                out var uMean);
            GetV724327PlaneStats(
                targetV,
                out var vMin,
                out var vMax,
                out var vMean);

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.frame_truth_dump " +
                $"serial={serial} " +
                $"source={sourceWidth}x{sourceHeight} " +
                $"target={targetWidth}x{targetHeight} " +
                $"layout=planar-fast " +
                $"y={yMin}-{yMax}:{yMean:F2} " +
                $"u={uMin}-{uMax}:{uMean:F2} " +
                $"v={vMin}-{vMax}:{vMean:F2} " +
                $"dir='{dumpDirectory}'");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.frame_truth_dump_failed " +
                $"serial={serial} error='{ex.Message}'");
        }
    }

    // [V72.4.3.2.15][RAW_PGMYUV_TRUTH]
    private static void TryDumpV7243215RawChromaTruth(
        string framePath,
        ReadOnlySpan<byte> packedPayload,
        int width,
        int height,
        int chromaWidth,
        int chromaHeight)
    {
        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_RAW_CHROMA_TRUTH") != "1")
        {
            return;
        }

        var serial = Interlocked.Increment(ref _v7243215RawTruthSerial);
        if (serial != 30 && serial != 120 && serial != 240)
        {
            return;
        }

        var dumpDirectory = Environment.GetEnvironmentVariable(
            "SHARPEMU_BINK_RAW_CHROMA_TRUTH_DIR");
        if (string.IsNullOrWhiteSpace(dumpDirectory))
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(dumpDirectory);
            var prefix = Path.Combine(
                dumpDirectory,
                $"frame_{serial:D4}");
            var yBytes = checked(width * height);
            var chromaBytes = checked(chromaWidth * chromaHeight);
            var required = checked(yBytes + 2 * chromaBytes);
            if (packedPayload.Length < required)
            {
                return;
            }

            // Preserve the original PGMYUV geometry: full-width luma followed
            // by rows containing U on the left and V on the right.
            var pgmPath = prefix + "_packed_pgmyuv.pgm";
            using (var stream = new FileStream(
                       pgmPath,
                       FileMode.Create,
                       FileAccess.Write,
                       FileShare.Read))
            {
                var header = Encoding.ASCII.GetBytes(
                    $"P5\n{width} {height + chromaHeight}\n255\n");
                stream.Write(header);
                stream.Write(packedPayload[..required]);
            }

            long uSum = 0;
            long vSum = 0;
            var uMin = 255;
            var uMax = 0;
            var vMin = 255;
            var vMax = 0;
            long samples = 0;

            for (var cy = 0; cy < chromaHeight; cy++)
            {
                var rowStart = yBytes + cy * width;
                for (var cx = 0; cx < chromaWidth; cx++)
                {
                    var u = packedPayload[rowStart + cx];
                    var v = packedPayload[rowStart + chromaWidth + cx];
                    uSum += u;
                    vSum += v;
                    uMin = Math.Min(uMin, u);
                    uMax = Math.Max(uMax, u);
                    vMin = Math.Min(vMin, v);
                    vMax = Math.Max(vMax, v);
                    samples++;
                }
            }

            WriteV7243215RawCandidate(
                prefix + "_normal_full.ppm", packedPayload,
                width, height, chromaWidth, true, false);
            WriteV7243215RawCandidate(
                prefix + "_normal_limited.ppm", packedPayload,
                width, height, chromaWidth, false, false);
            WriteV7243215RawCandidate(
                prefix + "_swapped_full.ppm", packedPayload,
                width, height, chromaWidth, true, true);
            WriteV7243215RawCandidate(
                prefix + "_swapped_limited.ppm", packedPayload,
                width, height, chromaWidth, false, true);

            var uMean = samples == 0 ? 0.0 : (double)uSum / samples;
            var vMean = samples == 0 ? 0.0 : (double)vSum / samples;
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.raw_chroma_truth " +
                $"serial={serial} file='{Path.GetFileName(framePath)}' " +
                $"packed_bytes={required} layout=pgmyuv-side-by-side " +
                $"u_min={uMin} u_max={uMax} u_mean={uMean:F3} " +
                $"v_min={vMin} v_max={vMax} v_mean={vMean:F3} " +
                "candidates=normal_full,normal_limited," +
                "swapped_full,swapped_limited");
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.raw_chroma_truth_failed " +
                $"serial={serial} type={ex.GetType().Name} " +
                $"message='{ex.Message}'");
        }
    }

    private static void WriteV7243215RawCandidate(
        string path,
        ReadOnlySpan<byte> packedPayload,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        bool fullRange,
        bool swapUv)
    {
        var targetWidth = Math.Min(sourceWidth, 640);
        var targetHeight = Math.Max(
            1,
            (int)Math.Round(
                sourceHeight * (targetWidth / (double)sourceWidth)));
        if (targetHeight > 360)
        {
            targetHeight = 360;
            targetWidth = Math.Max(
                1,
                (int)Math.Round(
                    sourceWidth * (targetHeight / (double)sourceHeight)));
        }

        var rgb = new byte[checked(targetWidth * targetHeight * 3)];
        var yBytes = checked(sourceWidth * sourceHeight);

        for (var ty = 0; ty < targetHeight; ty++)
        {
            var sy = Math.Min(
                sourceHeight - 1,
                (int)(((long)ty * sourceHeight) / targetHeight));
            var yRow = sy * sourceWidth;
            var cRow = yBytes + (sy >> 1) * sourceWidth;
            var targetRow = ty * targetWidth * 3;

            for (var tx = 0; tx < targetWidth; tx++)
            {
                var sx = Math.Min(
                    sourceWidth - 1,
                    (int)(((long)tx * sourceWidth) / targetWidth));
                var cx = Math.Min(sourceChromaWidth - 1, sx >> 1);
                var first = packedPayload[cRow + cx];
                var second = packedPayload[cRow + sourceChromaWidth + cx];
                var u = swapUv ? second : first;
                var v = swapUv ? first : second;

                ConvertBt709Sample(
                    packedPayload[yRow + sx],
                    u - 128,
                    v - 128,
                    fullRange,
                    out var red,
                    out var green,
                    out var blue);

                var output = targetRow + tx * 3;
                rgb[output] = (byte)Math.Clamp(red, 0, 255);
                rgb[output + 1] = (byte)Math.Clamp(green, 0, 255);
                rgb[output + 2] = (byte)Math.Clamp(blue, 0, 255);
            }
        }

        using var stream = new FileStream(
            path, FileMode.Create, FileAccess.Write, FileShare.Read);
        var header = Encoding.ASCII.GetBytes(
            $"P6\n{targetWidth} {targetHeight}\n255\n");
        stream.Write(header);
        stream.Write(rgb);
    }

    private static void ConvertBt709Sample(
        byte yy,
        int cb,
        int cr,
        bool fullRange,
        out int red,
        out int green,
        out int blue)
    {
        if (fullRange)
        {
            red = yy + ((403 * cr + 128) >> 8);
            green = yy - ((48 * cb + 120 * cr + 128) >> 8);
            blue = yy + ((475 * cb + 128) >> 8);
            return;
        }

        var c = Math.Max((int)yy - 16, 0);
        red = (298 * c + 459 * cr + 128) >> 8;
        green = (298 * c - 55 * cb - 136 * cr + 128) >> 8;
        blue = (298 * c + 541 * cb + 128) >> 8;
    }

    private static void TryDumpV724327FrameTruth(
        int serial,
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int sourceWidth,
        int sourceHeight,
        int sourceChromaWidth,
        int targetWidth,
        int targetHeight,
        ReadOnlySpan<byte> normalBgra,
        bool fullRange)
    {
        var dumpDirectory =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_FRAME_TRUTH_DIR");

        if (string.IsNullOrWhiteSpace(dumpDirectory))
        {
            return;
        }

        try
        {
            System.IO.Directory.CreateDirectory(dumpDirectory);

            var prefix = System.IO.Path.Combine(
                dumpDirectory,
                $"frame_{serial:D4}");

            var targetChromaWidth = (targetWidth + 1) / 2;
            var targetChromaHeight = (targetHeight + 1) / 2;

            var targetY = new byte[checked(targetWidth * targetHeight)];
            var targetU = new byte[checked(
                targetChromaWidth * targetChromaHeight)];
            var targetV = new byte[targetU.Length];

            for (var y = 0; y < targetHeight; y++)
            {
                var sourceY = Math.Min(
                    sourceHeight - 1,
                    (int)(((long)y * sourceHeight) / targetHeight));
                var sourceRow = sourceY * sourceWidth;
                var targetRow = y * targetWidth;

                for (var x = 0; x < targetWidth; x++)
                {
                    var sourceX = Math.Min(
                        sourceWidth - 1,
                        (int)(((long)x * sourceWidth) / targetWidth));
                    targetY[targetRow + x] =
                        yPlane[sourceRow + sourceX];
                }
            }

            var sourceChromaHeight = (sourceHeight + 1) / 2;

            for (var y = 0; y < targetChromaHeight; y++)
            {
                var sourceY = Math.Min(
                    sourceChromaHeight - 1,
                    (int)(((long)y * sourceChromaHeight) /
                          targetChromaHeight));
                var sourceRow = sourceY * sourceChromaWidth;
                var targetRow = y * targetChromaWidth;

                for (var x = 0; x < targetChromaWidth; x++)
                {
                    var sourceX = Math.Min(
                        sourceChromaWidth - 1,
                        (int)(((long)x * sourceChromaWidth) /
                              targetChromaWidth));
                    var source = sourceRow + sourceX;
                    targetU[targetRow + x] = uPlane[source];
                    targetV[targetRow + x] = vPlane[source];
                }
            }

            WriteV724327Pgm(
                prefix + "_Y.pgm",
                targetWidth,
                targetHeight,
                targetY);
            WriteV724327Pgm(
                prefix + "_U.pgm",
                targetChromaWidth,
                targetChromaHeight,
                targetU);
            WriteV724327Pgm(
                prefix + "_V.pgm",
                targetChromaWidth,
                targetChromaHeight,
                targetV);

            WriteV724327PpmFromBgra(
                prefix + "_normal.ppm",
                targetWidth,
                targetHeight,
                normalBgra);

            var swappedBgra = new byte[normalBgra.Length];
            RenderV724327ProbeBgra(
                targetY,
                targetU,
                targetV,
                targetWidth,
                targetHeight,
                fullRange,
                swapUv: true,
                neutralChroma: false,
                swappedBgra);
            WriteV724327PpmFromBgra(
                prefix + "_swapped.ppm",
                targetWidth,
                targetHeight,
                swappedBgra);

            var lumaBgra = new byte[normalBgra.Length];
            RenderV724327ProbeBgra(
                targetY,
                targetU,
                targetV,
                targetWidth,
                targetHeight,
                fullRange,
                swapUv: false,
                neutralChroma: true,
                lumaBgra);
            WriteV724327PpmFromBgra(
                prefix + "_luma.ppm",
                targetWidth,
                targetHeight,
                lumaBgra);

            GetV724327PlaneStats(
                targetY,
                out var yMin,
                out var yMax,
                out var yMean);
            GetV724327PlaneStats(
                targetU,
                out var uMin,
                out var uMax,
                out var uMean);
            GetV724327PlaneStats(
                targetV,
                out var vMin,
                out var vMax,
                out var vMean);

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.frame_truth_dump " +
                $"serial={serial} source={sourceWidth}x{sourceHeight} " +
                $"target={targetWidth}x{targetHeight} layout=planar " +
                $"y={yMin}-{yMax}:{yMean:F2} " +
                $"u={uMin}-{uMax}:{uMean:F2} " +
                $"v={vMin}-{vMax}:{vMean:F2} " +
                $"dir='{dumpDirectory}'");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.frame_truth_dump_failed " +
                $"serial={serial} error='{ex.Message}'");
        }
    }

    private static void RenderV724327ProbeBgra(
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int width,
        int height,
        bool fullRange,
        bool swapUv,
        bool neutralChroma,
        Span<byte> destination)
    {
        var chromaWidth = (width + 1) / 2;

        for (var y = 0; y < height; y++)
        {
            var yRow = y * width;
            var chromaRow = (y >> 1) * chromaWidth;
            var outputRow = yRow * 4;

            for (var x = 0; x < width; x++)
            {
                var yy = yPlane[yRow + x];
                var chroma = chromaRow + (x >> 1);

                var u = neutralChroma
                    ? 128
                    : uPlane[chroma];
                var v = neutralChroma
                    ? 128
                    : vPlane[chroma];

                if (swapUv)
                {
                    (u, v) = (v, u);
                }

                ConvertBt709Sample(
                    yy,
                    (int)u - 128,
                    (int)v - 128,
                    fullRange,
                    out var red,
                    out var green,
                    out var blue);

                var output = outputRow + x * 4;
                destination[output] =
                    (byte)Math.Clamp(blue, 0, 255);
                destination[output + 1] =
                    (byte)Math.Clamp(green, 0, 255);
                destination[output + 2] =
                    (byte)Math.Clamp(red, 0, 255);
                destination[output + 3] = 255;
            }
        }
    }

    private static void GetV724327PlaneStats(
        ReadOnlySpan<byte> plane,
        out int minimum,
        out int maximum,
        out double mean)
    {
        if (plane.IsEmpty)
        {
            minimum = 0;
            maximum = 0;
            mean = 0;
            return;
        }

        var min = 255;
        var max = 0;
        long sum = 0;

        foreach (var value in plane)
        {
            min = Math.Min(min, value);
            max = Math.Max(max, value);
            sum += value;
        }

        minimum = min;
        maximum = max;
        mean = (double)sum / plane.Length;
    }

    private static void WriteV724327Pgm(
        string path,
        int width,
        int height,
        ReadOnlySpan<byte> pixels)
    {
        var header = System.Text.Encoding.ASCII.GetBytes(
            $"P5\n{width} {height}\n255\n");

        using var stream = new System.IO.FileStream(
            path,
            System.IO.FileMode.Create,
            System.IO.FileAccess.Write,
            System.IO.FileShare.Read);

        stream.Write(header);
        stream.Write(pixels);
    }

    private static void WriteV724327PpmFromBgra(
        string path,
        int width,
        int height,
        ReadOnlySpan<byte> bgra)
    {
        var rgb = new byte[checked(width * height * 3)];

        for (var pixel = 0; pixel < width * height; pixel++)
        {
            var source = pixel * 4;
            var destination = pixel * 3;

            rgb[destination] = bgra[source + 2];
            rgb[destination + 1] = bgra[source + 1];
            rgb[destination + 2] = bgra[source];
        }

        var header = System.Text.Encoding.ASCII.GetBytes(
            $"P6\n{width} {height}\n255\n");

        using var stream = new System.IO.FileStream(
            path,
            System.IO.FileMode.Create,
            System.IO.FileAccess.Write,
            System.IO.FileShare.Read);

        stream.Write(header);
        stream.Write(rgb);
    }

    private static byte ReadCombinedChromaByte(
        ReadOnlySpan<byte> firstHalf,
        ReadOnlySpan<byte> secondHalf,
        int index)
    {
        if ((uint)index < (uint)firstHalf.Length)
        {
            return firstHalf[index];
        }

        var secondIndex = index - firstHalf.Length;
        if ((uint)secondIndex < (uint)secondHalf.Length)
        {
            return secondHalf[secondIndex];
        }

        return 128;
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

        // [V70.4.1.0][LOW_LATENCY_SWSCALE]
        process.StartInfo.ArgumentList.Add("-fflags");
        process.StartInfo.ArgumentList.Add("nobuffer");
        process.StartInfo.ArgumentList.Add("-flags");
        process.StartInfo.ArgumentList.Add("low_delay");
        process.StartInfo.ArgumentList.Add("-f");
        process.StartInfo.ArgumentList.Add("rawvideo");
        process.StartInfo.ArgumentList.Add("-pix_fmt");
        process.StartInfo.ArgumentList.Add("yuv420p");
        process.StartInfo.ArgumentList.Add("-video_size");
        process.StartInfo.ArgumentList.Add($"{_sourceWidth}x{_sourceHeight}");
        process.StartInfo.ArgumentList.Add("-framerate");
        process.StartInfo.ArgumentList.Add(
            $"{FramesPerSecondNumerator}/{FramesPerSecondDenominator}");
        // [V70.4.0][BINK2_FULL_RANGE_FFMPEG]
        // RAD Bink 2 uses full-range 0..255. Preserve that through the raw I420
        // pipe and convert only pixel format/matrix to host BGRA.
        var ffmpegInputRange = _fullRange ? "pc" : "tv";
        process.StartInfo.ArgumentList.Add("-color_range");
        process.StartInfo.ArgumentList.Add(ffmpegInputRange);
        process.StartInfo.ArgumentList.Add("-colorspace");
        process.StartInfo.ArgumentList.Add("bt709");
        process.StartInfo.ArgumentList.Add("-i");
        process.StartInfo.ArgumentList.Add("pipe:0");
        process.StartInfo.ArgumentList.Add("-vf");
        process.StartInfo.ArgumentList.Add(
            $"scale={Width}:{Height}:" +
            "flags=bilinear+accurate_rnd+full_chroma_int:" +
            "in_color_matrix=bt709:out_color_matrix=bt709:" +
            $"in_range={ffmpegInputRange}:out_range=pc");
        process.StartInfo.ArgumentList.Add("-pix_fmt");
        process.StartInfo.ArgumentList.Add("bgra");
        process.StartInfo.ArgumentList.Add("-f");
        process.StartInfo.ArgumentList.Add("rawvideo");
        process.StartInfo.ArgumentList.Add("-fps_mode");
        process.StartInfo.ArgumentList.Add("passthrough");
        process.StartInfo.ArgumentList.Add("-flush_packets");
        process.StartInfo.ArgumentList.Add("1");
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
            "matrix=BT709 range=" + (_fullRange ? "full" : "limited") + " chroma=bilinear pixfmt=bgra");

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

    // [V70.4.1.0][GREEN_FALLBACK_REPAIR]
    private void TryRepairGreenFallback(
        ReadOnlySpan<byte> yPlane,
        ReadOnlySpan<byte> uPlane,
        ReadOnlySpan<byte> vPlane,
        int sourceWidth,
        int sourceHeight,
        int chromaWidth,
        Span<byte> destination,
        bool useFullRange)
    {
        // [V70.4.2.0][FORCED_UV_RECOVERY]
        // Standalone validation can explicitly force the alternate chroma
        // order. This runs before the existing heuristic/decision logic and
        // therefore does not depend on that logic's exact source formatting.
        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_FORCE_UV_SWAP") == "1")
        {
            ConvertYuv420ToBgra(
                yPlane,
                vPlane,
                uPlane,
                sourceWidth,
                sourceHeight,
                chromaWidth,
                destination,
                useFullRange);

            if (!_forcedUvRecoveryLogged)
            {
                _forcedUvRecoveryLogged = true;
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.fallback_chroma_forced uv_swap=True");
            }
            return;
        }

        if (Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_AUTO_UV_REPAIR") != "1")
        {
            return;
        }

        if (_fallbackSwapUvDecision == false)
        {
            return;
        }

        if (_fallbackSwapUvDecision == true)
        {
            ConvertYuv420ToBgra(
                yPlane,
                vPlane,
                uPlane,
                sourceWidth,
                sourceHeight,
                chromaWidth,
                destination,
                useFullRange);
            return;
        }

        var normalScore = MeasureGreenCast(destination);
        if (normalScore < 28.0)
        {
            _fallbackSwapUvDecision = false;
            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.fallback_chroma normal score={normalScore:F1}");
            return;
        }

        if (_fallbackColorScratch is null ||
            _fallbackColorScratch.Length < destination.Length)
        {
            _fallbackColorScratch =
                GC.AllocateUninitializedArray<byte>(destination.Length);
        }

        var alternate = _fallbackColorScratch.AsSpan(0, destination.Length);
        ConvertYuv420ToBgra(
            yPlane,
            vPlane,
            uPlane,
            sourceWidth,
            sourceHeight,
            chromaWidth,
            alternate,
            useFullRange);

        var swappedScore = MeasureGreenCast(alternate);
        var chooseSwap = swappedScore + 12.0 < normalScore;
        _fallbackSwapUvDecision = chooseSwap;

        if (chooseSwap)
        {
            alternate.CopyTo(destination);
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.fallback_chroma_auto " +
            $"normal_green={normalScore:F1} swapped_green={swappedScore:F1} " +
            $"uv_swap={chooseSwap}");
    }

    private static double MeasureGreenCast(ReadOnlySpan<byte> bgra)
    {
        if (bgra.Length < 4)
        {
            return 0.0;
        }

        long red = 0;
        long green = 0;
        long blue = 0;
        long count = 0;
        var pixelCount = bgra.Length / 4;
        var step = Math.Max(1, pixelCount / 4096);

        for (var pixel = 0; pixel < pixelCount; pixel += step)
        {
            var offset = pixel * 4;
            blue += bgra[offset];
            green += bgra[offset + 1];
            red += bgra[offset + 2];
            count++;
        }

        if (count == 0)
        {
            return 0.0;
        }

        var meanRed = red / (double)count;
        var meanGreen = green / (double)count;
        var meanBlue = blue / (double)count;
        return meanGreen - ((meanRed + meanBlue) * 0.5);
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
