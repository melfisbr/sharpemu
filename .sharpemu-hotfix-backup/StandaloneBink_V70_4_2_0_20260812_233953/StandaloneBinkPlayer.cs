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
    public const string VersionMarker = "SHARPEMU_STANDALONE_BINK_V70_4_1_0";

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

        // [V70.7.1][NIHAV_ONLY_KB2J_DEFAULT]
        // The installed FFmpeg explicitly reports "Bink 2 video is not implemented"
        // for KB2j. Do not probe that known-dead decoder by default.
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_FFMPEG") is null)
        {
            Environment.SetEnvironmentVariable("SHARPEMU_BINK_DIRECT_FFMPEG", "0");
        }

        // [V70.4.0][RAD_BINK2_COLOR]
        // RAD documents Bink 2 as full-range YUV (0..255). Do not auto-detect
        // range from an early dark frame and do not force limited/video range.
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_YUV_FULL_RANGE", "1");
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_AUTO_RANGE", "0");

        // Prefer the persistent native FFmpeg swscale converter after the
        // corrected PGMYUV -> I420 repack. V70.4 also patches that converter to
        // use pc/full input range rather than tv/limited input range.
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_COLOR", "1");

        // The game creates four Bink async workers. Our host bridge uses one
        // nihav-tool producer, so give that process AboveNormal priority and let
        // the decoder's own realtime deadline/catch-up own movie pacing.
        // [V70.4.1.0][NIHAV_HIGH_PRIORITY]
        // The measured producer wait is the dominant cost (hundreds of ms per
        // frame), not file reading or BGRA conversion. Give the external Bink2
        // producer high scheduling priority in standalone validation.
        Environment.SetEnvironmentVariable("SHARPEMU_NIHAV_FAST_PRIORITY", "3");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_REALTIME_DEADLINE", "1");

        // [V70.4.1.0][COLOR_RECOVERY]
        // V70.4.0.1.1 proved that the full-range FFmpeg path starts but the
        // first frame times out and falls back to the in-process converter.
        // Give native swscale enough startup time and enable the fallback's
        // conservative green-cast/UV repair only for standalone playback.
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_FRAME_TIMEOUT_MS", "15000");
        Environment.SetEnvironmentVariable("SHARPEMU_BINK_AUTO_UV_REPAIR", "1");

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
            // [V70.4.1.0][SIDECAR_AUDIO_DISCOVERY]
            // Some game cinematics keep audio outside the BK2. Prefer a nearby
            // WAV sidecar before invoking embedded-track decoders.
            wavePath = TryFindSidecarAudio(moviePath);
            if (wavePath is null)
            {
                wavePath = TryExtractAudio(moviePath, out audioDirectory);
            }

            var maximumWidth = ReadPositiveUIntEnvironment(
                "SHARPEMU_BINK_STANDALONE_WIDTH",
                DefaultMaximumWidth);
            var maximumHeight = ReadPositiveUIntEnvironment(
                "SHARPEMU_BINK_STANDALONE_HEIGHT",
                DefaultMaximumHeight);

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

                // [V70.4.1.0][STANDALONE_HARD_DEADLINE]
                // The V70.4.0.1.1 measurement showed producer wait growing to
                // ~392 ms/frame. A decoder that cannot produce 30 fps must not
                // turn a 30-fps movie into slow motion. Standalone playback
                // therefore owns a final wall-clock stop at the BK2 nominal
                // duration, independent of how many frames were produced.
                TryReadBinkTiming(
                    moviePath,
                    out var nominalFrameCount,
                    out var nominalFpsNumerator,
                    out var nominalFpsDenominator);
                var nominalDurationSeconds =
                    nominalFrameCount > 0 &&
                    nominalFpsNumerator > 0
                        ? nominalFrameCount *
                          (double)Math.Max(1u, nominalFpsDenominator) /
                          nominalFpsNumerator
                        : 0.0;
                var playbackClock = new Stopwatch();

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
                        if (!playbackClock.IsRunning)
                        {
                            playbackClock.Start();
                        }

                        if (!audioStarted && wavePath is not null)
                        {
                            StartWaveAudio(wavePath);
                            audioStarted = true;
                        }

                        if (nominalDurationSeconds > 0.0 &&
                            playbackClock.Elapsed.TotalSeconds >=
                                nominalDurationSeconds +
                                (double)fpsDenominator / fpsNumerator)
                        {
                            Console.Error.WriteLine(
                                "[BINK-STANDALONE][SYNC] hard realtime deadline " +
                                $"elapsed={playbackClock.Elapsed.TotalSeconds:F3}s " +
                                $"nominal={nominalDurationSeconds:F3}s " +
                                $"frames_presented={frameIndex}");
                            break;
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

    private static string? TryFindSidecarAudio(string moviePath)
    {
        var directory = Path.GetDirectoryName(moviePath);
        if (string.IsNullOrWhiteSpace(directory))
        {
            return null;
        }

        var stem = Path.GetFileNameWithoutExtension(moviePath);
        var candidates = new[]
        {
            Path.Combine(directory, stem + ".wav"),
            Path.Combine(directory, stem + ".audio.wav"),
            Path.Combine(directory, "audio", stem + ".wav"),
            Path.Combine(directory, "sound", stem + ".wav"),
            Path.Combine(Path.GetDirectoryName(directory) ?? directory, "audio", stem + ".wav"),
        };

        foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(candidate) && new FileInfo(candidate).Length > 44)
            {
                var full = Path.GetFullPath(candidate);
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE][AUDIO] Sidecar WAV discovered: {full}");
                return full;
            }
        }

        return null;
    }

    private static bool TryReadBinkTiming(
        string moviePath,
        out uint frameCount,
        out uint fpsNumerator,
        out uint fpsDenominator)
    {
        frameCount = 0;
        fpsNumerator = 0;
        fpsDenominator = 0;
        Span<byte> header = stackalloc byte[0x24];

        try
        {
            using var stream = File.OpenRead(moviePath);
            stream.ReadExactly(header);
        }
        catch
        {
            return false;
        }

        if (!header[..3].SequenceEqual("KB2"u8))
        {
            return false;
        }

        frameCount =
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
                header.Slice(8, 4));
        fpsNumerator =
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
                header.Slice(0x1C, 4));
        fpsDenominator =
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(
                header.Slice(0x20, 4));

        return frameCount > 0 && fpsNumerator > 0 && fpsDenominator > 0;
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
            LogToolDiagnostic(sessionDirectory, "nihav_stderr.log", "NIHAV");
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
            LogToolDiagnostic(sessionDirectory, "ffmpeg_stderr.log", "FFmpeg");
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

    private static void LogToolDiagnostic(
        string directory,
        string fileName,
        string toolName)
    {
        try
        {
            var path = Path.Combine(directory, fileName);
            if (!File.Exists(path))
            {
                return;
            }

            var text = File.ReadAllText(path)
                .Replace('\r', ' ')
                .Replace('\n', ' ')
                .Trim();
            if (text.Length > 600)
            {
                text = text[..600];
            }

            if (!string.IsNullOrWhiteSpace(text))
            {
                Console.Error.WriteLine(
                    $"[BINK-STANDALONE][AUDIO] {toolName} detail: {text}");
            }
        }
        catch
        {
        }
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
