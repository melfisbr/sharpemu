// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Runtime.InteropServices;
using SharpEmu.Libs.VideoOut;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Standalone host-side Bink2 playback entry point used by the CLI --play-bink mode.
/// V70.1.0 adds host WAV audio extraction/playback and uses the proven 720p
/// compatibility decode ceiling for realtime playback.
/// </summary>
public static class StandaloneBinkPlayer
{
    public const string VersionMarker = "SHARPEMU_STANDALONE_BINK_V70_6_1";

    private const uint DefaultMaximumWidth = 960;
    private const uint DefaultMaximumHeight = 540;
    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;

    [DllImport("winmm.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PlaySound(
        string? pszSound,
        nint hmod,
        uint fdwSound);

    public static int Play(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            Console.Error.WriteLine("[BINK-STANDALONE][ERROR] Movie path is empty.");
            return 2;
        }

        var moviePath = Path.GetFullPath(path);
        if (!File.Exists(moviePath))
        {
            Console.Error.WriteLine($"[BINK-STANDALONE][ERROR] File not found: {moviePath}");
            return 2;
        }

        Console.Error.WriteLine($"[BINK-STANDALONE] Opening: {moviePath}");

        // [V70.4.0][RAD_BINK2_COLOR]
        // RAD documents Bink 2 as full-range YUV (0..255). Do not auto-detect
        // range from an early dark frame and do not force limited/video range.
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_YUV_FULL_RANGE", "1");
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_AUTO_RANGE", "0");

        // [V70.4.2][LUT_REALTIME]
        // V70.4 runtime telemetry showed the persistent FFmpeg color pipe
        // averaging ~20-193 ms/frame at 960x540, while the corrected in-process
        // LUT path previously averaged ~13 ms/frame at the same size.
        // Keep Bink2 full-range + BT.709 semantics, but use the faster LUT path.
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_COLOR", "0");

        // [V70.5.0][PRODUCER_PREFETCH_DEFAULTS]
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_FAST_PRIORITY", "3");
        if (Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES") is null)
        {
            Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES", "12");
        }
        if (Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS") is null)
        {
            Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS", "8");
        }
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_REALTIME_DEADLINE", "1");

        // Apply the standalone cap at both API and decoder-environment levels.
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_WIDTH") is null)
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_BINK_OUTPUT_MAX_WIDTH",
                DefaultMaximumWidth.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT") is null)
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT",
                DefaultMaximumHeight.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }

        string? audioDirectory = null;
        string? wavePath = null;
        try
        {
            wavePath = TryExtractAudio(moviePath, out audioDirectory);

            var maximumWidth = ReadPositiveUIntEnvironment(
                "SHARPEMU_BINK_STANDALONE_WIDTH",
                DefaultMaximumWidth);
            var maximumHeight = ReadPositiveUIntEnvironment(
                "SHARPEMU_BINK_STANDALONE_HEIGHT",
                DefaultMaximumHeight);

            // [V70.6.1][FFMPEG_RAWVIDEO_PIPE]
            // Prefer an in-memory decoded-frame transport. This removes the
            // NIHAV -> PGMYUV file -> directory polling roundtrip that V70.5
            // proved cannot sustain this 4K source in realtime. If the local
            // FFmpeg build cannot decode this Bink2 variant, fall back to NIHAV.
            if (!string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_FFMPEG"),
                    "0",
                    StringComparison.OrdinalIgnoreCase))
            {
                var directFfmpeg = FindFfmpegTool();
                if (directFfmpeg is not null &&
                    TryPlayViaFfmpegRawVideo(
                        directFfmpeg,
                        moviePath,
                        maximumWidth,
                        maximumHeight,
                        wavePath,
                        out var directResult))
                {
                    return directResult;
                }

                Console.Error.WriteLine(
                    "[BINK-STANDALONE] FFmpeg rawvideo pipe unavailable for this BK2/build; " +
                    "falling back to NIHAV streaming.");
            }

            if (!NihavBink2Decoder.TryOpen(
                    moviePath,
                    maximumWidth: maximumWidth,
                    maximumHeight: maximumHeight,
                    out var decoder) || decoder is null)
            {
                Console.Error.WriteLine(
                    "[BINK-STANDALONE][ERROR] Could not open Bink2 stream. " +
                    "Verify KB2 format and plugins\\bink2\\nihav-tool.exe.");
                return 3;
            }

            using (decoder)
            {
                var width = decoder.Width;
                var height = decoder.Height;
                var fpsNumerator = Math.Max(1u, decoder.FramesPerSecondNumerator);
                var fpsDenominator = Math.Max(1u, decoder.FramesPerSecondDenominator);
                var frameBytes = checked((int)((ulong)width * height * 4));
                var decodeBuffer = GC.AllocateUninitializedArray<byte>(frameBytes);

                Console.Error.WriteLine(
                    $"[BINK-STANDALONE] Ready: {width}x{height} " +
                    $"fps={fpsNumerator}/{fpsDenominator} bytes_per_frame={frameBytes}");

                var audioStarted = false;
                long frameIndex = 0;
                try
                {
                    while (decoder.TryDecodeNextFrame(decodeBuffer))
                    {
                        // [V70.4.0][SINGLE_MOVIE_CLOCK]
                        // NihavBink2Decoder already selects frames against the
                        // movie clock and implements realtime deadline/catch-up.
                        // Do not add a second sleep/rebase clock here.
                        if (!audioStarted && wavePath is not null)
                        {
                            StartWaveAudio(wavePath);
                            audioStarted = true;
                        }

                        var presentationFrame =
                            GC.AllocateUninitializedArray<byte>(frameBytes);
                        decodeBuffer.AsSpan().CopyTo(presentationFrame);
                        VulkanVideoPresenter.Submit(
                            presentationFrame,
                            width,
                            height);

                        frameIndex++;
                        if (frameIndex <= 3 || frameIndex % 120 == 0)
                        {
                            Console.Error.WriteLine(
                                $"[BINK-STANDALONE] frame={frameIndex} size={width}x{height}");
                        }
                    }
                }
                catch (Exception exception)
                {
                    Console.Error.WriteLine(
                        $"[BINK-STANDALONE][ERROR] Playback failed: {exception}");
                    StopWaveAudio();
                    VulkanVideoPresenter.RequestClose();
                    return 4;
                }

                Console.Error.WriteLine(
                    $"[BINK-STANDALONE] EOF: frames_presented={frameIndex}");

                StopWaveAudio();
                Thread.Sleep(250);
                VulkanVideoPresenter.RequestClose();
                Thread.Sleep(100);
                return frameIndex > 0 ? 0 : 5;
            }
        }
        finally
        {
            StopWaveAudio();
            if (audioDirectory is not null)
            {
                try
                {
                    Directory.Delete(audioDirectory, recursive: true);
                }
                catch
                {
                }
            }
        }
    }

    private static string? TryExtractAudio(
        string moviePath,
        out string? sessionDirectory)
    {
        sessionDirectory = null;
        if (!OperatingSystem.IsWindows())
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] Host WAV playback currently requires Windows.");
            return null;
        }

        var explicitAudio =
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUDIO_FILE");
        if (!string.IsNullOrWhiteSpace(explicitAudio))
        {
            var explicitPath = Path.GetFullPath(explicitAudio);
            if (File.Exists(explicitPath) &&
                string.Equals(
                    Path.GetExtension(explicitPath),
                    ".wav",
                    StringComparison.OrdinalIgnoreCase))
            {
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE][AUDIO] Explicit WAV: {explicitPath}");
                return explicitPath;
            }

            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] Explicit audio path is not an existing WAV: {explicitPath}");
        }

        var requestedTrack = 0;
        _ = int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUDIO_TRACK"),
            out requestedTrack);
        requestedTrack = Math.Max(0, requestedTrack);

        sessionDirectory = Path.Combine(
            Path.GetTempPath(),
            "sharpemu-bink-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(sessionDirectory);

        // NIHAV is the same Bink-family tool used for video. -vn asks it to
        // decode audio only; -apfx writes one WAV per decoded audio stream.
        var nihavTool = FindNihavTool();
        if (nihavTool is not null)
        {
            var prefix = Path.Combine(sessionDirectory, "nihav_audio");
            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] Probing NIHAV audio tracks; requested={requestedTrack}...");
            var nihavExit = RunTool(
                nihavTool,
                ["-vn", "-apfx", prefix, "-ignerr", moviePath],
                sessionDirectory,
                "nihav");

            var nihavWaves = Directory
                .EnumerateFiles(sessionDirectory, "nihav_audio*.wav")
                .OrderBy(static value => value, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            if (nihavWaves.Length > 0)
            {
                var selected = Math.Min(requestedTrack, nihavWaves.Length - 1);
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE][AUDIO] NIHAV tracks={nihavWaves.Length} " +
                    $"selected={selected} file={Path.GetFileName(nihavWaves[selected])}");
                return nihavWaves[selected];
            }

            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] NIHAV exposed no WAV tracks (exit={nihavExit}).");
        }

        // FFmpeg has Bink Audio DCT/RDFT decoders. Use it as a host-only
        // fallback when the installed NIHAV build does not expose the track.
        var ffmpeg = FindFfmpegTool();
        if (ffmpeg is not null)
        {
            var ffmpegWave = Path.Combine(sessionDirectory, "bink_audio.wav");
            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] Probing FFmpeg audio stream {requestedTrack}...");

            var ffmpegExit = RunTool(
                ffmpeg,
                [
                    "-hide_banner",
                    "-loglevel", "info",
                    "-y",
                    "-i", moviePath,
                    "-map", $"0:a:{requestedTrack}?",
                    "-vn",
                    "-c:a", "pcm_s16le",
                    ffmpegWave,
                ],
                sessionDirectory,
                "ffmpeg");

            if (ffmpegExit == 0 &&
                File.Exists(ffmpegWave) &&
                new FileInfo(ffmpegWave).Length > 44)
            {
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE][AUDIO] FFmpeg track ready: {Path.GetFileName(ffmpegWave)}");
                return ffmpegWave;
            }

            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] FFmpeg produced no playable WAV (exit={ffmpegExit}).");
        }
        else
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] FFmpeg CLI not found; " +
                "set SHARPEMU_FFMPEG_TOOL or SHARPEMU_FFMPEG.");
        }

        // A BK2 is allowed to be video-only; Demon's Souls also has an
        // independent sound-bank/AudioOut2 pipeline. Do not manufacture silence
        // or assume a codec failure means an embedded track definitely exists.
        Console.Error.WriteLine(
            "[BINK-STANDALONE][AUDIO] No embedded audio track was exposed by the available decoders. " +
            "Playback continues as video-only. Set SHARPEMU_BINK_AUDIO_FILE to a WAV sidecar if required.");
        return null;
    }

    private static bool TryPlayViaFfmpegRawVideo(
        string ffmpeg,
        string moviePath,
        uint width,
        uint height,
        string? wavePath,
        out int result)
    {
        result = 0;
        var fps = ProbeFfmpegFramesPerSecond(ffmpeg, moviePath);
        if (fps <= 1.0 || fps > 240.0)
        {
            fps = 30.0;
        }

        var frameBytes = checked((int)((ulong)width * height * 4));
        var frame = GC.AllocateUninitializedArray<byte>(frameBytes);

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            WorkingDirectory = AppContext.BaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        foreach (var argument in new[]
        {
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin",
            "-i", moviePath,
            "-map", "0:v:0",
            "-an",
            "-vf",
            $"scale={width}:{height}:flags=bilinear:in_color_matrix=bt709:out_color_matrix=bt709:in_range=pc:out_range=pc",
            "-pix_fmt", "bgra",
            // [V70.6.1][NO_FFMPEG_VSYNC_OPTION]
            // The bundled/located FFmpeg build used on the user's host does
            // not expose -vsync. Rawvideo is intentionally unpaced here; the
            // SharpEmu host clock below owns presentation timing.
            "-f", "rawvideo",
            "pipe:1",
        })
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        try
        {
            Console.Error.WriteLine(
                $"[BINK-STANDALONE] Trying FFmpeg rawvideo pipe: {width}x{height} " +
                $"fps={fps:0.###} matrix=BT709 range=full pixfmt=bgra");

            if (!process.Start())
            {
                return false;
            }

            try
            {
                process.PriorityClass = ProcessPriorityClass.High;
            }
            catch
            {
            }

            var stderrTask = process.StandardError.ReadToEndAsync();
            var stdout = process.StandardOutput.BaseStream;
            var frameDurationTicks = Stopwatch.Frequency / fps;
            long playbackStart = 0;
            long frameIndex = 0;
            var audioStarted = false;

            while (ReadExactFrame(stdout, frame))
            {
                var now = Stopwatch.GetTimestamp();
                if (frameIndex == 0)
                {
                    playbackStart = now;
                    Console.Error.WriteLine(
                        $"[LOADER][INFO] bink2.ffmpeg_pipe_ready " +
                        $"file='{Path.GetFileName(moviePath)}' output={width}x{height} " +
                        $"fps={fps:0.###} matrix=BT709 range=full pixfmt=bgra transport=stdout");

                    if (wavePath is not null)
                    {
                        StartWaveAudio(wavePath);
                        audioStarted = true;
                    }
                }
                else
                {
                    var target = playbackStart + (long)(frameIndex * frameDurationTicks);
                    var lateness = now - target;
                    var twoFrames = (long)(frameDurationTicks * 2.0);
                    if (lateness > twoFrames)
                    {
                        playbackStart = now - (long)(frameIndex * frameDurationTicks);
                    }
                    else
                    {
                        WaitUntilTimestamp(target);
                    }
                }

                var presentationFrame = GC.AllocateUninitializedArray<byte>(frameBytes);
                frame.AsSpan().CopyTo(presentationFrame);
                VulkanVideoPresenter.Submit(presentationFrame, width, height);
                frameIndex++;

                if (frameIndex <= 3 || frameIndex % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[BINK-STANDALONE] ffmpeg_pipe_frame={frameIndex} size={width}x{height}");
                }
            }

            if (!process.HasExited)
            {
                process.WaitForExit(5_000);
            }
            try { stderrTask.Wait(2_000); } catch { }
            var stderr = stderrTask.IsCompletedSuccessfully
                ? stderrTask.Result
                : string.Empty;

            if (frameIndex == 0)
            {
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE] FFmpeg rawvideo pipe produced no frames. " +
                    $"exit={(process.HasExited ? process.ExitCode : -1)} " +
                    $"detail={CompactDiagnostic(stderr)}");
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch
                {
                }
                return false;
            }

            Console.Error.WriteLine(
                $"[BINK-STANDALONE] FFmpeg pipe EOF: frames_presented={frameIndex} " +
                $"exit={(process.HasExited ? process.ExitCode : 0)}");
            if (audioStarted)
            {
                StopWaveAudio();
            }
            Thread.Sleep(250);
            VulkanVideoPresenter.RequestClose();
            Thread.Sleep(100);
            result = 0;
            return true;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                $"[BINK-STANDALONE] FFmpeg rawvideo pipe failed: {exception.Message}");
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
            }
            return false;
        }
    }

    private static bool ReadExactFrame(Stream stream, byte[] buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = stream.Read(buffer, offset, buffer.Length - offset);
            if (read <= 0)
            {
                return false;
            }
            offset += read;
        }
        return true;
    }

    private static double ProbeFfmpegFramesPerSecond(
        string ffmpeg,
        string moviePath)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        process.StartInfo.ArgumentList.Add("-hide_banner");
        process.StartInfo.ArgumentList.Add("-i");
        process.StartInfo.ArgumentList.Add(moviePath);

        try
        {
            if (!process.Start())
            {
                return 30.0;
            }
            var stderrTask = process.StandardError.ReadToEndAsync();
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            if (!process.WaitForExit(5_000))
            {
                try { process.Kill(entireProcessTree: true); } catch { }
            }
            try { Task.WaitAll([stderrTask, stdoutTask], 1_000); } catch { }
            var probe = stderrTask.IsCompletedSuccessfully ? stderrTask.Result : string.Empty;
            var match = System.Text.RegularExpressions.Regex.Match(
                probe,
                @"(?<![0-9.])(?<fps>[0-9]+(?:\.[0-9]+)?)\s+fps\b",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (match.Success &&
                double.TryParse(
                    match.Groups["fps"].Value,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var fps))
            {
                return fps;
            }
        }
        catch
        {
        }
        return 30.0;
    }

    private static void WaitUntilTimestamp(long targetTimestamp)
    {
        while (true)
        {
            var remaining = targetTimestamp - Stopwatch.GetTimestamp();
            if (remaining <= 0)
            {
                return;
            }
            var milliseconds = remaining * 1000.0 / Stopwatch.Frequency;
            if (milliseconds >= 2.0)
            {
                Thread.Sleep(Math.Max(1, (int)milliseconds - 1));
            }
            else
            {
                Thread.SpinWait(128);
            }
        }
    }

    private static string CompactDiagnostic(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "none";
        }
        var compact = string.Join(
            " ",
            value.Split(
                ['\r', '\n'],
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        return compact.Length <= 320 ? compact : compact[..320];
    }

    private static int RunTool(
        string tool,
        IReadOnlyList<string> arguments,
        string workingDirectory,
        string logPrefix)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = tool,
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        try
        {
            if (!process.Start())
            {
                return -1;
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(180_000))
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                return -2;
            }

            try { Task.WaitAll([stdoutTask, stderrTask], 2_000); } catch { }
            try
            {
                File.WriteAllText(
                    Path.Combine(workingDirectory, logPrefix + "_stdout.log"),
                    stdoutTask.IsCompletedSuccessfully ? stdoutTask.Result : string.Empty);
                File.WriteAllText(
                    Path.Combine(workingDirectory, logPrefix + "_stderr.log"),
                    stderrTask.IsCompletedSuccessfully ? stderrTask.Result : string.Empty);
            }
            catch
            {
            }

            return process.ExitCode;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] Tool '{Path.GetFileName(tool)}' failed: {exception.Message}");
            return -3;
        }
    }

    private static string? FindFfmpegTool()
    {
        var configured =
            Environment.GetEnvironmentVariable("SHARPEMU_FFMPEG_TOOL");
        if (string.IsNullOrWhiteSpace(configured))
        {
            configured = Environment.GetEnvironmentVariable("SHARPEMU_FFMPEG");
        }
        if (!string.IsNullOrWhiteSpace(configured) &&
            File.Exists(configured))
        {
            return Path.GetFullPath(configured);
        }

        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "plugins", "ffmpeg", "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, "plugins", "bink2", "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe"),
        };

        var local = candidates.FirstOrDefault(File.Exists);
        if (local is not null)
        {
            return local;
        }

        try
        {
            using var where = Process.Start(new ProcessStartInfo
            {
                FileName = "where.exe",
                Arguments = "ffmpeg.exe",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            });
            if (where is null)
            {
                return null;
            }

            var firstLine = where.StandardOutput.ReadLine();
            where.WaitForExit(2_000);
            return where.ExitCode == 0 &&
                   !string.IsNullOrWhiteSpace(firstLine) &&
                   File.Exists(firstLine)
                ? firstLine
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static string? FindNihavTool()
    {
        var configured =
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_TOOL");
        if (!string.IsNullOrWhiteSpace(configured) &&
            File.Exists(configured))
        {
            return Path.GetFullPath(configured);
        }

        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "plugins", "bink2", "nihav-tool.exe"),
            Path.Combine(AppContext.BaseDirectory, "plugins", "bink2", "nihav_tool.exe"),
            Path.Combine(AppContext.BaseDirectory, "nihav-tool.exe"),
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static void StartWaveAudio(string wavePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        if (PlaySound(
                wavePath,
                0,
                SndFilename | SndAsync | SndNodefault))
        {
            Console.Error.WriteLine(
                $"[BINK-STANDALONE][AUDIO] Playing: {Path.GetFileName(wavePath)}");
        }
        else
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] Windows waveOut playback could not start.");
        }
    }

    private static void StopWaveAudio()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                PlaySound(null, 0, 0);
            }
            catch
            {
            }
        }
    }

    private static uint ReadPositiveUIntEnvironment(
        string name,
        uint fallback)
    {
        return uint.TryParse(
                   Environment.GetEnvironmentVariable(name),
                   out var value) &&
               value > 0
            ? value
            : fallback;
    }

}
