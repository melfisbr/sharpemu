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
    public const string VersionMarker = "SHARPEMU_STANDALONE_BINK_V70_1_0";

    private const uint DefaultMaximumWidth = 1280;
    private const uint DefaultMaximumHeight = 720;
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

        // The in-process LUT converter is currently faster and deterministic at
        // the 720p compatibility ceiling. It also consumes the corrected PGMYUV
        // planar repack from V70.1.0. Users can explicitly opt into FFmpeg later.
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_COLOR") is null)
        {
            Environment.SetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_COLOR", "0");
        }

        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_YUV_FULL_RANGE") is null)
        {
            Environment.SetEnvironmentVariable("SHARPEMU_BINK_YUV_FULL_RANGE", "1");
        }

        string? audioDirectory = null;
        string? wavePath = null;
        try
        {
            wavePath = TryExtractAudio(moviePath, out audioDirectory);

            if (!NihavBink2Decoder.TryOpen(
                    moviePath,
                    maximumWidth: DefaultMaximumWidth,
                    maximumHeight: DefaultMaximumHeight,
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
                var frameDurationTicks =
                    Stopwatch.Frequency * (double)fpsDenominator / fpsNumerator;

                Console.Error.WriteLine(
                    $"[BINK-STANDALONE] Ready: {width}x{height} " +
                    $"fps={fpsNumerator}/{fpsDenominator} bytes_per_frame={frameBytes}");

                if (wavePath is not null)
                {
                    StartWaveAudio(wavePath);
                }

                long frameIndex = 0;
                long playbackStart = 0;
                try
                {
                    while (decoder.TryDecodeNextFrame(decodeBuffer))
                    {
                        if (frameIndex == 0)
                        {
                            playbackStart = Stopwatch.GetTimestamp();
                        }
                        else
                        {
                            WaitUntil(playbackStart + (long)(frameIndex * frameDurationTicks));
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

        var toolPath = FindNihavTool();
        if (toolPath is null)
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] nihav-tool not found; continuing without audio.");
            return null;
        }

        sessionDirectory = Path.Combine(
            Path.GetTempPath(),
            "sharpemu-bink-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(sessionDirectory);
        var prefix = Path.Combine(sessionDirectory, "audio");

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = toolPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        process.StartInfo.ArgumentList.Add("-vn");
        process.StartInfo.ArgumentList.Add("-apfx");
        process.StartInfo.ArgumentList.Add(prefix);
        process.StartInfo.ArgumentList.Add("-ignerr");
        process.StartInfo.ArgumentList.Add(moviePath);

        Console.Error.WriteLine("[BINK-STANDALONE][AUDIO] Extracting Bink audio...");
        if (!process.Start())
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] Could not start nihav-tool audio extraction.");
            return null;
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(120_000))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] Audio extraction timed out; continuing without audio.");
            return null;
        }

        try { Task.WaitAll([stdoutTask, stderrTask], 2_000); } catch { }

        var waves = Directory
            .EnumerateFiles(sessionDirectory, "audio*.wav")
            .OrderBy(static value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (waves.Length == 0)
        {
            Console.Error.WriteLine(
                "[BINK-STANDALONE][AUDIO] No decoded WAV track was produced.");
            return null;
        }

        Console.Error.WriteLine(
            $"[BINK-STANDALONE][AUDIO] Ready: {Path.GetFileName(waves[0])} tracks={waves.Length}");
        return waves[0];
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

    private static void WaitUntil(long targetTimestamp)
    {
        while (true)
        {
            var remaining = targetTimestamp - Stopwatch.GetTimestamp();
            if (remaining <= 0)
            {
                return;
            }

            var remainingMilliseconds =
                remaining * 1000.0 / Stopwatch.Frequency;
            if (remainingMilliseconds >= 2.0)
            {
                Thread.Sleep(Math.Max(1, (int)remainingMilliseconds - 1));
            }
            else
            {
                Thread.SpinWait(128);
            }
        }
    }
}
