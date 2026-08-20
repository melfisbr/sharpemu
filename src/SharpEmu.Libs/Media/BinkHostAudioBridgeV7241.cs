// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0

using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-side audio companion for NIHAV-backed Bink2 playback.
///
/// Order:
///  1. explicit/same-name WAV sidecar;
///  2. NIHAV audio-only extraction;
///  3. FFmpeg audio-only extraction.
///
/// Extraction runs on a background thread so the movie decoder is never
/// blocked. A generation token prevents late audio from an old movie from
/// starting after the bridge has already advanced to the next movie.
/// </summary>
internal static class BinkHostAudioBridgeV7241
{
    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;

    private static readonly object Gate = new();
    private static readonly Dictionary<string, string> CachedWavByMovie =
        new(StringComparer.OrdinalIgnoreCase);

    private static long _generation;

    // V72.4.3.2.24 AUDIO_PRESENTATION_SYNC
    // Audio may be extracted while the video full-cache is being filled, but
    // playback starts only when the first frame of that movie is submitted.
    private static long _presentationRequestedGeneration;
    private static string? _presentationRequestedMovie;

    public static void TryStart(string hostPath)
    {
        if (!OperatingSystem.IsWindows() ||
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(hostPath) ||
            !File.Exists(hostPath) ||
            !string.Equals(
                Path.GetExtension(hostPath),
                ".bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        // V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO
        //
        // The game eboot starts opening video and music through separate
        // state-machine actions. Demon's Souls resolves its opening music/SFX/
        // VO from external AT9 banks rather than embedded logo_intro audio.
        var v7243227IntroAttach =
            BinkDemonSoulsIntroAudioV7243227.PrepareAttach(hostPath);

        long generation;
        lock (Gate)
        {
            // Always advance the base generation so a late extraction from the
            // previous Bink movie can never overwrite the external timeline.
            generation = ++_generation;

            if (v7243227IntroAttach !=
                BinkDemonSoulsIntroAudioV7243227.AttachDisposition.ContinueTimeline)
            {
                _ = PlaySound(null, IntPtr.Zero, 0);
            }

            if (v7243227IntroAttach !=
                BinkDemonSoulsIntroAudioV7243227.AttachDisposition.NotHandled)
            {
                return;
            }

            if (CachedWavByMovie.TryGetValue(hostPath, out var cached) &&
                IsPlayableWave(cached))
            {
                // V72.4.3.2.24: cache is ready, but do not start before the
                // first video frame is actually submitted.
                TryStartPreparedLocked(hostPath, cached, "cache", generation);
                return;
            }
        }

        if (TryResolveSidecar(hostPath, out var sidecar))
        {
            lock (Gate)
            {
                if (generation != _generation)
                {
                    return;
                }

                CachedWavByMovie[hostPath] = sidecar;
                TryStartPreparedLocked(hostPath, sidecar, "sidecar", generation);
            }

            return;
        }

        var thread = new Thread(
            () => ExtractAndStart(hostPath, generation))
        {
            IsBackground = true,
            Name = "SharpEmu-BinkAudio",
        };
        thread.Start();
    }

    private static void ExtractAndStart(string moviePath, long generation)
    {
        try
        {
            var requestedTrack = ParseTrackIndex();
            if (TryExtractWithNihav(
                    moviePath,
                    requestedTrack,
                    out var nihavWave,
                    out var nihavDetail))
            {
                TryStartExtracted(
                    moviePath,
                    nihavWave,
                    "nihav",
                    generation);
                return;
            }

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.audio_nihav_unavailable " +
                $"file='{Path.GetFileName(moviePath)}' detail='{Sanitize(nihavDetail)}'");

            if (TryExtractWithFfmpeg(
                    moviePath,
                    requestedTrack,
                    out var ffmpegWave,
                    out var ffmpegDetail))
            {
                TryStartExtracted(
                    moviePath,
                    ffmpegWave,
                    "ffmpeg",
                    generation);
                return;
            }

            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.audio_unavailable " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"nihav='{Sanitize(nihavDetail)}' ffmpeg='{Sanitize(ffmpegDetail)}'");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] bink2.audio_bridge_error " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
        }
    }

    private static void TryStartExtracted(
        string moviePath,
        string wavePath,
        string backend,
        long generation)
    {
        lock (Gate)
        {
            if (generation != _generation)
            {
                TryDeleteTemporaryWave(wavePath);
                return;
            }

            CachedWavByMovie[moviePath] = wavePath;
            TryStartPreparedLocked(moviePath, wavePath, backend, generation);
        }
    }

    // SHARPEMU_BINK_OPTIONS_SKIP_AUDIO_STOP_V1_0
    // Options/Start skip must stop the current host audio at the same boundary
    // as video teardown. Advancing the generation also prevents a late NIHAV/
    // FFmpeg extraction from starting after the movie was skipped.
    public static void StopForOptionsSkip(string hostPath)
    {
        lock (Gate)
        {
            _generation++;
            _presentationRequestedGeneration = 0;
            _presentationRequestedMovie = null;

            if (OperatingSystem.IsWindows())
            {
                _ = PlaySound(null, IntPtr.Zero, 0);
            }
        }

        BinkDemonSoulsIntroAudioV7243227.StopForMovie(hostPath);

        Console.Error.WriteLine(
            "[OPTIONS-SKIP][V1.0] audio_stopped " +
            $"file='{Path.GetFileName(hostPath)}'");
    }
    public static void NotifyPresentationStarted(string moviePath)
    {
        // V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO_PRESENT
        // The existing V24 HostMovieBridge hook calls this exactly on the first
        // presented frame. External intro audio therefore shares that same
        // presentation boundary instead of starting at file-open time.
        if (BinkDemonSoulsIntroAudioV7243227.NotifyPresentationStarted(moviePath))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return;
        }

        lock (Gate)
        {
            _presentationRequestedGeneration = _generation;
            _presentationRequestedMovie = moviePath;

            if (CachedWavByMovie.TryGetValue(moviePath, out var cached) &&
                IsPlayableWave(cached))
            {
                StartWaveLocked(
                    moviePath,
                    cached,
                    "presentation-sync",
                    _generation);
            }
        }
    }

    private static void TryStartPreparedLocked(
        string moviePath,
        string wavePath,
        string backend,
        long generation)
    {
        if (generation != _presentationRequestedGeneration ||
            !string.Equals(
                moviePath,
                _presentationRequestedMovie,
                StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.audio_prepared " +
                $"file='{Path.GetFileName(moviePath)}' backend={backend}");
            return;
        }

        StartWaveLocked(moviePath, wavePath, backend, generation);
    }

    private static void StartWaveLocked(
        string moviePath,
        string wavePath,
        string backend,
        long generation)
    {
        if (generation != _generation ||
            !IsPlayableWave(wavePath))
        {
            return;
        }

        var started = PlaySound(
            wavePath,
            IntPtr.Zero,
            SndFilename | SndAsync | SndNodefault);

        Console.Error.WriteLine(
            started
                ? $"[LOADER][INFO] bink2.audio_start " +
                  $"file='{Path.GetFileName(moviePath)}' backend={backend} " +
                  $"wav='{wavePath}'"
                : $"[LOADER][WARN] bink2.audio_play_failed " +
                  $"file='{Path.GetFileName(moviePath)}' backend={backend} " +
                  $"wav='{wavePath}'");
    }

    private static bool TryResolveSidecar(
        string moviePath,
        out string wavePath)
    {
        wavePath = string.Empty;

        var explicitWave =
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUDIO_FILE");
        if (!string.IsNullOrWhiteSpace(explicitWave) &&
            IsPlayableWave(explicitWave))
        {
            wavePath = Path.GetFullPath(explicitWave);
            return true;
        }

        var directory = Path.GetDirectoryName(moviePath);
        var stem = Path.GetFileNameWithoutExtension(moviePath);
        if (string.IsNullOrWhiteSpace(directory) ||
            string.IsNullOrWhiteSpace(stem))
        {
            return false;
        }

        var candidates = new[]
        {
            Path.Combine(directory, stem + ".wav"),
            Path.Combine(directory, stem + "_audio.wav"),
            Path.Combine(directory, "audio", stem + ".wav"),
        };

        foreach (var candidate in candidates)
        {
            if (IsPlayableWave(candidate))
            {
                wavePath = candidate;
                return true;
            }
        }

        return false;
    }

    private static bool TryExtractWithNihav(
        string moviePath,
        int requestedTrack,
        out string wavePath,
        out string detail)
    {
        wavePath = string.Empty;
        detail = "nihav-tool not found";

        var tool = ResolveNihavTool();
        if (tool is null)
        {
            return false;
        }

        var prefix = Path.Combine(
            Path.GetTempPath(),
            "sharpemu-bink-audio-" +
            Environment.ProcessId.ToString() + "-" +
            Guid.NewGuid().ToString("N") + "-");

        var arguments =
            "-vn -apfx " + QuoteArgument(prefix) + " " +
            QuoteArgument(moviePath);

        var result = RunTool(
            tool,
            arguments,
            timeoutMilliseconds: 30000);

        var expected = prefix + requestedTrack.ToString("D2") + ".wav";
        if (IsPlayableWave(expected))
        {
            wavePath = expected;
            detail = "track=" + requestedTrack.ToString();
            return true;
        }

        // Some NIHAV tool revisions use a slightly different numeric suffix.
        var directory = Path.GetDirectoryName(prefix) ?? Path.GetTempPath();
        var prefixName = Path.GetFileName(prefix);
        var produced = Directory
            .EnumerateFiles(directory, prefixName + "*.wav")
            .OrderBy(static path => path, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault(IsPlayableWave);

        if (produced is not null)
        {
            wavePath = produced;
            detail =
                "requested=" + requestedTrack.ToString() +
                " selected='" + Path.GetFileName(produced) + "'";
            return true;
        }

        detail =
            "exit=" + result.ExitCode.ToString() +
            " timeout=" + result.TimedOut.ToString() +
            " stderr='" + Sanitize(result.StandardError) + "'";

        return false;
    }

    private static bool TryExtractWithFfmpeg(
        string moviePath,
        int requestedTrack,
        out string wavePath,
        out string detail)
    {
        wavePath = string.Empty;
        detail = "ffmpeg not found";

        var tool = ResolveFfmpegTool();
        if (tool is null)
        {
            return false;
        }

        var output = Path.Combine(
            Path.GetTempPath(),
            "sharpemu-bink-audio-" +
            Environment.ProcessId.ToString() + "-" +
            Guid.NewGuid().ToString("N") + ".wav");

        var arguments =
            "-hide_banner -loglevel error " +
            "-probesize 100M -analyzeduration 100M " +
            "-i " + QuoteArgument(moviePath) + " " +
            "-map 0:a:" + requestedTrack.ToString() + " " +
            "-vn -c:a pcm_s16le -y " + QuoteArgument(output);

        var result = RunTool(
            tool,
            arguments,
            timeoutMilliseconds: 30000);

        if (result.ExitCode == 0 &&
            !result.TimedOut &&
            IsPlayableWave(output))
        {
            wavePath = output;
            detail = "track=" + requestedTrack.ToString();
            return true;
        }

        TryDeleteTemporaryWave(output);
        detail =
            "exit=" + result.ExitCode.ToString() +
            " timeout=" + result.TimedOut.ToString() +
            " stderr='" + Sanitize(result.StandardError) + "'";

        return false;
    }

    private static int ParseTrackIndex()
    {
        var raw = Environment.GetEnvironmentVariable(
            "SHARPEMU_BINK_AUDIO_TRACK");

        return int.TryParse(raw, out var track) && track >= 0 && track < 32
            ? track
            : 0;
    }

    private static string? ResolveNihavTool()
    {
        var explicitTool =
            Environment.GetEnvironmentVariable("SHARPEMU_NIHAV_TOOL");
        if (!string.IsNullOrWhiteSpace(explicitTool) &&
            File.Exists(explicitTool))
        {
            return Path.GetFullPath(explicitTool);
        }

        var candidates = new[]
        {
            Path.Combine(
                AppContext.BaseDirectory,
                "plugins",
                "bink2",
                "nihav-tool.exe"),
            Path.Combine(
                AppContext.BaseDirectory,
                "nihav-tool.exe"),
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static string? ResolveFfmpegTool()
    {
        var explicitTool =
            Environment.GetEnvironmentVariable("SHARPEMU_FFMPEG_EXE");
        if (!string.IsNullOrWhiteSpace(explicitTool) &&
            File.Exists(explicitTool))
        {
            return Path.GetFullPath(explicitTool);
        }

        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, "tools", "ffmpeg.exe"),
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        // Let CreateProcess resolve PATH when FFmpeg is installed globally.
        return "ffmpeg.exe";
    }

    private static ToolResult RunTool(
        string fileName,
        string arguments,
        int timeoutMilliseconds)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                },
            };

            if (!process.Start())
            {
                return new ToolResult(
                    -1,
                    false,
                    string.Empty,
                    "process did not start");
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();

            var exited = process.WaitForExit(timeoutMilliseconds);
            if (!exited)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                }

                _ = process.WaitForExit(2000);
            }

            var stdout = TryGetTaskResult(stdoutTask);
            var stderr = TryGetTaskResult(stderrTask);

            return new ToolResult(
                exited ? process.ExitCode : -1,
                !exited,
                stdout,
                stderr);
        }
        catch (Exception ex)
        {
            return new ToolResult(
                -1,
                false,
                string.Empty,
                ex.GetType().Name + ": " + ex.Message);
        }
    }

    private static string TryGetTaskResult(Task<string> task)
    {
        try
        {
            return task.Wait(2000) ? task.Result : string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static bool IsPlayableWave(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) ||
            !File.Exists(path))
        {
            return false;
        }

        try
        {
            var info = new FileInfo(path);
            if (info.Length <= 44)
            {
                return false;
            }

            Span<byte> header = stackalloc byte[12];
            using var stream = File.OpenRead(path);
            if (stream.Read(header) != header.Length)
            {
                return false;
            }

            return header[0] == (byte)'R' &&
                   header[1] == (byte)'I' &&
                   header[2] == (byte)'F' &&
                   header[3] == (byte)'F' &&
                   header[8] == (byte)'W' &&
                   header[9] == (byte)'A' &&
                   header[10] == (byte)'V' &&
                   header[11] == (byte)'E';
        }
        catch
        {
            return false;
        }
    }

    private static void TryDeleteTemporaryWave(string path)
    {
        try
        {
            if (path.StartsWith(
                    Path.GetTempPath(),
                    StringComparison.OrdinalIgnoreCase) &&
                File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static string QuoteArgument(string value) =>
        "\"" + value.Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";

    private static string Sanitize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value
            .Replace("\r", " ", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal)
            .Trim();

        return normalized.Length <= 360
            ? normalized
            : normalized[..360];
    }

    private readonly record struct ToolResult(
        int ExitCode,
        bool TimedOut,
        string StandardOutput,
        string StandardError);

    [DllImport(
        "winmm.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PlaySound(
        string? pszSound,
        IntPtr hmod,
        uint fdwSound);
}

