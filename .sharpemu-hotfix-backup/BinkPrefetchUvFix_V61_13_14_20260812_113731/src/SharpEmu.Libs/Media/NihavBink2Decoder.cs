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
    private readonly double _chunkSeconds;
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

        // [V61.13.13][NIHAV_SINGLE_PASS]
        // KB2 seeking is not reliable in the external decoder used by this
        // compatibility path. The old 1-second slicing repeatedly restarted
        // from the beginning of the movie. Single-pass mode decodes the whole
        // BK2 once and then consumes the generated frames sequentially.
        _singlePass = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_SINGLE_PASS"),
            "1",
            StringComparison.Ordinal);

        // [V61.13.13][BT709]
        // HD/4K Bink material is treated as Rec.709 by default. Set
        // SHARPEMU_NIHAV_COLOR_MATRIX=601 to restore the legacy matrix.
        var colorMatrix =
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_COLOR_MATRIX");
        _bt709 = !string.Equals(
            colorMatrix,
            "601",
            StringComparison.OrdinalIgnoreCase) &&
            _sourceWidth >= 1280;

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

        var (outputWidth, outputHeight) = FitWithin(
            sourceWidth,
            sourceHeight,
            maximumWidth,
            maximumHeight);
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
            // Decode the first slice synchronously so attaching the bridge is
            // proof that this particular KB2 stream can actually be decoded,
            // not merely that the helper executable exists.
            if (!candidate.DecodeNextChunk())
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
                var framePath = _chunkFrames[_chunkFrameIndex++];
                if (!TryReadFrame(framePath, destination[..requiredBytes]))
                {
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

    private bool TryReadFrame(string path, Span<byte> destination)
    {
        byte[] fileBytes;
        try
        {
            fileBytes = File.ReadAllBytes(path);
        }
        catch (IOException)
        {
            return false;
        }

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

            ConvertRgb24ToBgra(
                fileBytes.AsSpan(payloadOffset, required),
                width,
                sourceHeight,
                destination);
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

        var payload = fileBytes.AsSpan(payloadOffset, requiredPayload);
        var yPlane = payload[..yBytes];
        var firstChroma = payload.Slice(yBytes, chromaBytes);
        var secondChroma = payload.Slice(yBytes + chromaBytes, chromaBytes);
        var uPlane = _swapUv ? secondChroma : firstChroma;
        var vPlane = _swapUv ? firstChroma : secondChroma;
        ConvertYuv420ToBgra(
            yPlane,
            uPlane,
            vPlane,
            visibleWidth,
            visibleHeight,
            chromaWidth,
            destination);
        return true;
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
                var luma = yPlane[sourceY * sourceWidth + sourceX];
                var chromaOffset = (sourceY / 2) * chromaWidth + (sourceX / 2);
                var u = uPlane[chromaOffset];
                var v = vPlane[chromaOffset];

                byte r;
                byte g;
                byte b;

                // [V61.13.13][YUV_MATRIX]
                // PGMYUV is Y + U + V. The prior path already read U/V in
                // that order, but always converted with BT.601 coefficients.
                // Use BT.709 for HD/4K Bink content; retain BT.601 as an
                // explicit compatibility fallback.
                var d = u - 128;
                var e = v - 128;
                if (_fullRange)
                {
                    if (_bt709)
                    {
                        r = ClampByte(luma + ((403 * e) >> 8));
                        g = ClampByte(luma - ((48 * d + 120 * e) >> 8));
                        b = ClampByte(luma + ((475 * d) >> 8));
                    }
                    else
                    {
                        r = ClampByte(luma + ((359 * e) >> 8));
                        g = ClampByte(luma - ((88 * d + 183 * e) >> 8));
                        b = ClampByte(luma + ((454 * d) >> 8));
                    }
                }
                else
                {
                    var c = Math.Max(0, luma - 16);
                    if (_bt709)
                    {
                        r = ClampByte((298 * c + 459 * e + 128) >> 8);
                        g = ClampByte((298 * c - 55 * d - 136 * e + 128) >> 8);
                        b = ClampByte((298 * c + 541 * d + 128) >> 8);
                    }
                    else
                    {
                        r = ClampByte((298 * c + 409 * e + 128) >> 8);
                        g = ClampByte((298 * c - 100 * d - 208 * e + 128) >> 8);
                        b = ClampByte((298 * c + 516 * d + 128) >> 8);
                    }
                }

                var destinationOffset = (y * outputWidth + x) * 4;
                destination[destinationOffset] = b;
                destination[destinationOffset + 1] = g;
                destination[destinationOffset + 2] = r;
                destination[destinationOffset + 3] = 0xFF;
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

        CleanupConsumedChunk();
        TryDeleteDirectory(_sessionRoot);
    }
}
