// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V31.7.18: creates a local cached Bink derivative in which the exact
/// Demon's Souls attract WAV is mixed into the BK2 by the user's installed
/// RAD Video Tools.  The game file is never modified.
///
/// This intentionally uses RAD's binkmix command rather than scheduling a
/// separate host audio device.  Once mixed, Bink owns both video and audio
/// timing in one stream.
/// </summary>
internal static class DemonSoulsAttractBinkMuxV31718
{
    internal readonly record struct BinkInfo(
        uint FrameCount,
        uint Width,
        uint Height,
        uint FpsNumerator,
        uint FpsDenominator,
        uint[] AudioTrackIds);

    internal static bool TryGetOrCreate(
        string radVideo64,
        string originalMovie,
        string exactWave,
        out string playbackMovie,
        out BinkInfo outputInfo)
    {
        playbackMovie = originalMovie;
        outputInfo = default;

        if (!OperatingSystem.IsWindows() ||
            string.IsNullOrWhiteSpace(radVideo64) ||
            !File.Exists(radVideo64) ||
            !string.Equals(
                Path.GetFileName(radVideo64),
                "radvideo64.exe",
                StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(originalMovie) ||
            !File.Exists(originalMovie) ||
            string.IsNullOrWhiteSpace(exactWave) ||
            !File.Exists(exactWave))
        {
            return false;
        }

        if (!string.Equals(
                Path.GetFileName(originalMovie),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!TryReadBinkInfo(originalMovie, out var sourceInfo) ||
            sourceInfo.FrameCount == 0 ||
            sourceInfo.FpsNumerator == 0 ||
            sourceInfo.FpsDenominator == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_attract_binkmix_unavailable " +
                "reason=invalid-source-bink-header");
            return false;
        }

        try
        {
            var source = new FileInfo(originalMovie);
            var wave = new FileInfo(exactWave);

            var keyText =
                $"{source.FullName}|{source.Length}|{source.LastWriteTimeUtc.Ticks}|" +
                $"{wave.FullName}|{wave.Length}|{wave.LastWriteTimeUtc.Ticks}|" +
                $"{sourceInfo.FrameCount}|{sourceInfo.FpsNumerator}|{sourceInfo.FpsDenominator}|" +
                "v317204-fact-tail"; // V31.7.20.4_FACT_TAIL_BINK_CACHE_KEY

            var digest = SHA256.HashData(Encoding.UTF8.GetBytes(keyText));
            var key = Convert.ToHexString(digest.AsSpan(0, 8)).ToLowerInvariant();

            var cacheDirectory = GetCacheDirectory();
            Directory.CreateDirectory(cacheDirectory);

            var cached = Path.Combine(
                cacheDirectory,
                $"attract_movie-v317204-fact-tail-audio-{key}.bk2");

            if (TryValidateOutput(cached, sourceInfo, out outputInfo))
            {
                playbackMovie = cached;
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.ds_attract_binkmix_cache_hit " +
                    $"file='attract_movie.bk2' cached='{cached}' " +
                    $"tracks={outputInfo.AudioTrackIds.Length} " +
                    $"ids='{string.Join(";", outputInfo.AudioTrackIds)}' " +
                    $"frames={outputInfo.FrameCount} " +
                    $"fps={outputInfo.FpsNumerator}/{outputInfo.FpsDenominator}");
                return true;
            }

            TryDelete(cached);

            var temporary =
                cached + ".tmp-" + Guid.NewGuid().ToString("N") + ".bk2";

            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = radVideo64,
                WorkingDirectory =
                    Path.GetDirectoryName(radVideo64) ??
                    AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                // V31.7.20_HIDDEN_BINKMIX
                // radvideo64 is a GUI process: CreateNoWindow only affects a
                // console window. STARTF_USESHOWWINDOW/SW_HIDE is supplied by
                // ProcessStartInfo.WindowStyle so its progress UI never flashes.
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };

            // RAD documents the modern command as:
            // radvideo64.exe binkmix input.bk2 audio.wav output.bk2
            // /# tells the standalone tool to exit instead of waiting on its
            // completion UI, which is required for unattended cache creation.
            process.StartInfo.ArgumentList.Add("binkmix");
            process.StartInfo.ArgumentList.Add(originalMovie);
            process.StartInfo.ArgumentList.Add(exactWave);
            process.StartInfo.ArgumentList.Add(temporary);
            process.StartInfo.ArgumentList.Add("/#");

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_attract_binkmix_startup_hidden " +
                "window_style=Hidden create_no_window=True");
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_attract_binkmix_begin " +
                "file='attract_movie.bk2' " +
                $"wave='{exactWave}' temp='{temporary}'");

            if (!process.Start())
            {
                TryDelete(temporary);
                return false;
            }

            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();

            if (!process.WaitForExit(300_000))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                }

                TryDelete(temporary);
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_binkmix_failed " +
                    "reason=timeout timeout_ms=300000");
                return false;
            }

            Task.WaitAll(stdout, stderr);

            if (process.ExitCode != 0)
            {
                TryDelete(temporary);
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_binkmix_failed " +
                    $"reason=exit-code exit={process.ExitCode} " +
                    $"detail='{Sanitize(stderr.Result)}'");
                return false;
            }

            if (!TryValidateOutput(
                    temporary,
                    sourceInfo,
                    out var temporaryInfo))
            {
                TryDelete(temporary);
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_binkmix_failed " +
                    "reason=output-validation");
                return false;
            }

            File.Move(temporary, cached, true);
            outputInfo = temporaryInfo;
            playbackMovie = cached;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_attract_binkmix_cache_created " +
                $"file='attract_movie.bk2' cached='{cached}' " +
                $"tracks={outputInfo.AudioTrackIds.Length} " +
                $"ids='{string.Join(";", outputInfo.AudioTrackIds)}' " +
                $"frames={outputInfo.FrameCount} " +
                $"fps={outputInfo.FpsNumerator}/{outputInfo.FpsDenominator} " +
                $"wave_bytes={wave.Length}");

            return true;
        }
        catch (Exception ex) when (
            ex is IOException or
            UnauthorizedAccessException or
            InvalidOperationException or
            System.ComponentModel.Win32Exception)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_attract_binkmix_failed " +
                $"reason=exception type={ex.GetType().Name} " +
                $"message='{Sanitize(ex.Message)}'");
            playbackMovie = originalMovie;
            outputInfo = default;
            return false;
        }
    }

    private static bool TryValidateOutput(
        string path,
        BinkInfo source,
        out BinkInfo output)
    {
        output = default;

        if (!TryReadBinkInfo(path, out output))
        {
            return false;
        }

        return output.FrameCount == source.FrameCount &&
               output.Width == source.Width &&
               output.Height == source.Height &&
               output.FpsNumerator == source.FpsNumerator &&
               output.FpsDenominator == source.FpsDenominator &&
               output.AudioTrackIds.Length > 0;
    }

    internal static bool TryReadBinkInfo(
        string path,
        out BinkInfo info)
    {
        info = default;

        try
        {
            if (!File.Exists(path))
            {
                return false;
            }

            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite);
            using var reader = new BinaryReader(
                stream,
                Encoding.ASCII,
                leaveOpen: false);

            if (stream.Length < 48)
            {
                return false;
            }

            var tagBytes = reader.ReadBytes(4);
            if (tagBytes.Length != 4)
            {
                return false;
            }

            var tag = Encoding.ASCII.GetString(tagBytes);
            var isBink1 = tag.StartsWith("BIK", StringComparison.Ordinal);
            var isBink2 = tag.StartsWith("KB2", StringComparison.Ordinal);
            if (!isBink1 && !isBink2)
            {
                return false;
            }

            stream.Position = 8;
            var frames = reader.ReadUInt32();

            stream.Position = 20;
            var width = reader.ReadUInt32();
            var height = reader.ReadUInt32();
            var fpsNumerator = reader.ReadUInt32();
            var fpsDenominator = reader.ReadUInt32();

            if (frames == 0 ||
                width == 0 ||
                height == 0 ||
                fpsNumerator == 0 ||
                fpsDenominator == 0)
            {
                return false;
            }

            stream.Position = 40;
            var trackCount = reader.ReadUInt32();
            if (trackCount > 256)
            {
                return false;
            }

            var revision = tag[3];
            var hasNewField =
                (isBink1 && revision == 'k') ||
                (isBink2 &&
                 (revision == 'i' ||
                  revision == 'j' ||
                  revision == 'k'));

            if (hasNewField)
            {
                if (stream.Position + 4 > stream.Length)
                {
                    return false;
                }

                _ = reader.ReadUInt32();
            }

            var tableBytes = checked((long)trackCount * 12L);
            if (stream.Position + tableBytes > stream.Length)
            {
                return false;
            }

            stream.Position += checked((long)trackCount * 4L);
            stream.Position += checked((long)trackCount * 4L);

            var ids = new uint[(int)trackCount];
            for (var index = 0; index < ids.Length; index++)
            {
                ids[index] = reader.ReadUInt32();
            }

            info = new BinkInfo(
                frames,
                width,
                height,
                fpsNumerator,
                fpsDenominator,
                ids);
            return true;
        }
        catch (Exception ex) when (
            ex is IOException or
            UnauthorizedAccessException or
            OverflowException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_attract_binkmix_header_failed " +
                $"file='{Path.GetFileName(path)}' " +
                $"type={ex.GetType().Name}");
            info = default;
            return false;
        }
    }

    private static string GetCacheDirectory()
    {
        var local = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);

        if (string.IsNullOrWhiteSpace(local))
        {
            local = Path.GetTempPath();
        }

        return Path.Combine(
            local,
            "SharpEmu",
            "MediaCache",
            "DemonSouls");
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static string Sanitize(string? text) =>
        string.IsNullOrWhiteSpace(text)
            ? string.Empty
            : text.Replace('\r', ' ').Replace('\n', ' ').Trim();
}
