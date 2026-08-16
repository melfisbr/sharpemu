// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.7: RAD playback through the SharpEmu embedded-host API.
///
/// The official RAD decoder is retained, but its HWND is hosted as a child of
/// the SharpEmu window.  Attract external audio is anchored only after the RAD
/// renderer has been embedded and has started consuming CPU, eliminating the
/// V31.6 race where WinMM audio started before the RAD process/window was ready.
/// </summary>
internal sealed class RadBinkExternalPlaybackV7243231 : IDisposable
{
    private readonly Process _process;
    private readonly IRadBinkHostApi _hostApi;
    private readonly Stopwatch _elapsed = Stopwatch.StartNew();
    private readonly bool _usesSharpEmuAttractAudio;
    private bool _disposed;

    private RadBinkExternalPlaybackV7243231(
        Process process,
        IRadBinkHostApi hostApi,
        string toolPath,
        string moviePath,
        int audioTrackCount,
        uint[] audioTrackIds,
        bool usesSharpEmuAttractAudio)
    {
        _process = process;
        _hostApi = hostApi;
        ToolPath = toolPath;
        MoviePath = moviePath;
        AudioTrackCount = audioTrackCount;
        AudioTrackIds = audioTrackIds;
        _usesSharpEmuAttractAudio = usesSharpEmuAttractAudio;
    }

    internal string ToolPath { get; }
    internal string MoviePath { get; }
    internal int AudioTrackCount { get; }
    internal IReadOnlyList<uint> AudioTrackIds { get; }
    internal bool UsesSharpEmuAttractAudio => _usesSharpEmuAttractAudio;
    internal bool IsEmbedded => _hostApi.IsEmbedded;
    internal double ElapsedSeconds => _elapsed.Elapsed.TotalSeconds;

    internal bool IsFinished
    {
        get
        {
            if (_disposed)
            {
                return true;
            }

            try
            {
                return _process.HasExited;
            }
            catch
            {
                return true;
            }
        }
    }

    internal int? ExitCode
    {
        get
        {
            if (!IsFinished)
            {
                return null;
            }

            try
            {
                return _process.ExitCode;
            }
            catch
            {
                return null;
            }
        }
    }

    internal static bool TryStart(
        string moviePath,
        out RadBinkExternalPlaybackV7243231? playback)
    {
        playback = null;

        if (!OperatingSystem.IsWindows() ||
            string.IsNullOrWhiteSpace(moviePath) ||
            !File.Exists(moviePath))
        {
            return false;
        }

        var toolPath = ResolveToolPath();
        if (string.IsNullOrWhiteSpace(toolPath) ||
            !File.Exists(toolPath))
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_required_missing " +
                "SHARPEMU_RADVIDEO64/radvideo64.path does not resolve.");
            return false;
        }

        var headerKnown = TryReadBinkAudioTrackIds(
            moviePath,
            out var audioTrackIds);
        var audioTrackCount = headerKnown ? audioTrackIds.Length : -1;
        var fileName = Path.GetFileName(moviePath);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_audio_header " +
            $"file='{fileName}' known={headerKnown} " +
            $"tracks={audioTrackCount} " +
            $"ids='{(headerKnown ? string.Join(";", audioTrackIds) : "unknown")}'");

        if (string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
                "1.0000");
            _ = BinkDemonSoulsIntroAudioV7243227.PrepareAttach(moviePath);
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_prewarm " +
                "tempo=1.0000 source=external-at9-stems");
        }

        Process? process = null;
        IRadBinkHostApi? hostApi = null;

        try
        {
            var windowsBeforeLaunch =
                RadBinkEmbeddedHostApiV72432317
                    .CaptureTopLevelWindowSnapshot();

            var start = new ProcessStartInfo
            {
                FileName = toolPath,
                WorkingDirectory =
                    Path.GetDirectoryName(toolPath) ??
                    AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = false,
            };

            start.ArgumentList.Add("binkplay");
            start.ArgumentList.Add(moviePath);
            // /I2 = no player caption/non-client chrome.  The HWND is still
            // created so SharpEmu can reparent it as a child window.
            start.ArgumentList.Add("/I2");

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_command " +
                "syntax='radvideo64.exe binkplay <movie> /I2' " +
                $"file='{fileName}'");

            process = new Process
            {
                StartInfo = start,
                EnableRaisingEvents = true,
            };

            if (!process.Start())
            {
                process.Dispose();
                return false;
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_required_started " +
                $"pid={process.Id} file='{fileName}' " +
                $"tool='{toolPath}'");

            // Strict integrated-host policy: if we cannot turn the RAD window
            // into a SharpEmu child HWND, kill the player rather than leaving a
            // separate external window on the desktop.
            if (!RadBinkEmbeddedHostApiV72432317.TryAttach(
                    process,
                    windowsBeforeLaunch,
                    moviePath,
                    out var embeddedHost) ||
                embeddedHost is null)
            {
                TryKill(process);
                process.Dispose();
                Console.Error.WriteLine(
                    "[LOADER][ERROR] bink2.rad_embedded_host_required_failed " +
                    $"file='{fileName}' external_window_forbidden=True");
                return false;
            }

            hostApi = embeddedHost;

            var usesSharpEmuAttractAudio = false;

            // The V31.6 result proved that attract_movie has zero Bink audio
            // tracks.  Start the external AT9 mix only AFTER the player HWND is
            // embedded and the RAD process has crossed the playback anchor.
            // V31.6 did this before rad_required_started/rad_host readiness,
            // which necessarily allowed audio to lead the first visible frame.
            if (headerKnown &&
                audioTrackIds.Length == 0 &&
                string.Equals(
                    fileName,
                    "attract_movie.bk2",
                    StringComparison.OrdinalIgnoreCase))
            {
                Environment.SetEnvironmentVariable(
                    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
                    "1.0000");

                var disposition =
                    BinkDemonSoulsIntroAudioV7243227.PrepareAttach(moviePath);

                usesSharpEmuAttractAudio =
                    disposition !=
                    BinkDemonSoulsIntroAudioV7243227
                        .AttachDisposition.NotHandled;

                if (usesSharpEmuAttractAudio)
                {
                    _ = BinkDemonSoulsIntroAudioV7243227
                        .NotifyPresentationStarted(moviePath);

                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.rad_attract_audio_sidecar " +
                        "file='attract_movie.bk2' tracks=0 " +
                        "source=external-at9-stems offset_s=12.000 tempo=1.0000 " +
                        $"anchor_ms={embeddedHost.PlaybackAnchorMilliseconds:F1} " +
                        "anchor=rad-embedded-playback-ready");
                }
                else
                {
                    Console.Error.WriteLine(
                        "[LOADER][WARN] bink2.rad_attract_audio_unavailable " +
                        "file='attract_movie.bk2' tracks=0");
                }
            }

            playback =
                new RadBinkExternalPlaybackV7243231(
                    process,
                    embeddedHost,
                    toolPath,
                    moviePath,
                    audioTrackCount,
                    audioTrackIds,
                    usesSharpEmuAttractAudio);

            return true;
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            IOException)
        {
            hostApi?.Dispose();
            if (process is not null)
            {
                TryKill(process);
                process.Dispose();
            }

            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_required_start_failed " +
                $"file='{fileName}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
            return false;
        }
    }

    private static bool TryReadBinkAudioTrackIds(
        string moviePath,
        out uint[] trackIds)
    {
        trackIds = Array.Empty<uint>();

        try
        {
            using var stream = new FileStream(
                moviePath,
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

            stream.Position = 40;
            var count = reader.ReadUInt32();
            if (count > 256)
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

            var tableBytes = checked((long)count * 12L);
            if (stream.Position + tableBytes > stream.Length)
            {
                return false;
            }

            stream.Position += checked((long)count * 4L);
            stream.Position += checked((long)count * 4L);

            trackIds = new uint[(int)count];
            for (var index = 0; index < trackIds.Length; index++)
            {
                trackIds[index] = reader.ReadUInt32();
            }

            return true;
        }
        catch (Exception ex) when (
            ex is IOException or
            UnauthorizedAccessException or
            OverflowException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.rad_audio_header_failed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
            trackIds = Array.Empty<uint>();
            return false;
        }
    }

    private static string? ResolveToolPath()
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_RADVIDEO64");

        if (IsExecutable(configured))
        {
            return Path.GetFullPath(configured!);
        }

        var configFile =
            Path.Combine(
                AppContext.BaseDirectory,
                "plugins",
                "bink2",
                "radvideo64.path");

        try
        {
            if (File.Exists(configFile))
            {
                var configuredFile =
                    File.ReadAllText(configFile).Trim().Trim('"');

                if (IsExecutable(configuredFile))
                {
                    return Path.GetFullPath(configuredFile);
                }
            }
        }
        catch (IOException)
        {
        }

        var path = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(path))
        {
            foreach (var entry in path.Split(
                         Path.PathSeparator,
                         StringSplitOptions.RemoveEmptyEntries |
                         StringSplitOptions.TrimEntries))
            {
                try
                {
                    var candidate =
                        Path.Combine(entry, "radvideo64.exe");
                    if (File.Exists(candidate))
                    {
                        return Path.GetFullPath(candidate);
                    }
                }
                catch
                {
                }
            }
        }

        return null;
    }

    private static bool IsExecutable(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        File.Exists(path) &&
        string.Equals(
            Path.GetFileName(path),
            "radvideo64.exe",
            StringComparison.OrdinalIgnoreCase);

    private static void TryKill(Process process)
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
    }

    private static string Sanitize(string? text) =>
        string.IsNullOrWhiteSpace(text)
            ? string.Empty
            : text.Replace('\r', ' ').Replace('\n', ' ').Trim();

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _elapsed.Stop();

        if (_usesSharpEmuAttractAudio)
        {
            BinkDemonSoulsIntroAudioV7243227.StopForMovie(MoviePath);
        }

        // Kill first while it is still parented to SharpEmu; this prevents the
        // renderer HWND from becoming a desktop top-level window during teardown.
        TryKill(_process);
        _hostApi.Dispose();
        _process.Dispose();
    }
}
