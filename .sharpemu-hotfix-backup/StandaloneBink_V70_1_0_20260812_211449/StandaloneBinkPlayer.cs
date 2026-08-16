// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using SharpEmu.Libs.VideoOut;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Standalone host-side Bink2 playback entry point used by the CLI --play-bink mode.
/// It deliberately bypasses SharpEmuRuntime/SelfLoader: a .bk2 file is media, not
/// an ELF/SELF guest image.
/// </summary>
public static class StandaloneBinkPlayer
{
    public const string VersionMarker = "SHARPEMU_STANDALONE_BINK_V70_0";

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

        if (!NihavBink2Decoder.TryOpen(
                moviePath,
                maximumWidth: 1920,
                maximumHeight: 1080,
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

                    // The presenter owns the array reference asynchronously. Do not
                    // hand it the decode buffer that the next frame will overwrite.
                    var presentationFrame = GC.AllocateUninitializedArray<byte>(frameBytes);
                    decodeBuffer.AsSpan().CopyTo(presentationFrame);
                    VulkanVideoPresenter.Submit(presentationFrame, width, height);

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
                VulkanVideoPresenter.RequestClose();
                return 4;
            }

            Console.Error.WriteLine(
                $"[BINK-STANDALONE] EOF: frames_presented={frameIndex}");

            // Leave the final frame visible briefly and then close the host window.
            Thread.Sleep(250);
            VulkanVideoPresenter.RequestClose();
            Thread.Sleep(100);
            return frameIndex > 0 ? 0 : 5;
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
