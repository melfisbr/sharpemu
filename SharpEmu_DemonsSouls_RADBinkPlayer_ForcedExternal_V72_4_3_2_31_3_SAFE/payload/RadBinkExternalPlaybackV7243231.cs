// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.3: external official RAD Video Tools Bink player.
/// The executable remains user-supplied and is never redistributed by SharpEmu.
/// RAD owns video timing, color conversion and embedded Bink audio.
/// </summary>
internal sealed class RadBinkExternalPlaybackV7243231 : IDisposable
{
    private readonly Process _process;
    private readonly Stopwatch _elapsed = Stopwatch.StartNew();
    private bool _disposed;

    private RadBinkExternalPlaybackV7243231(
        Process process,
        string toolPath,
        string moviePath)
    {
        _process = process;
        ToolPath = toolPath;
        MoviePath = moviePath;
    }

    internal string ToolPath { get; }
    internal string MoviePath { get; }
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

        try
        {
            var start = new ProcessStartInfo
            {
                FileName = toolPath,
                WorkingDirectory =
                    Path.GetDirectoryName(toolPath) ??
                    AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = false,
            };

            // Official RAD Video Tools command-line player:
            //   radvideo64.exe binkplay <movie.bk2>
            //
            // No SharpEmu sidecar WAV is started in RAD mode. The RAD player
            // is the single clock and owns the Bink audio stream.
            start.ArgumentList.Add("binkplay");
            start.ArgumentList.Add(moviePath);
            start.ArgumentList.Add("/#");

            var process = new Process
            {
                StartInfo = start,
                EnableRaisingEvents = true,
            };

            if (!process.Start())
            {
                process.Dispose();
                return false;
            }

            playback =
                new RadBinkExternalPlaybackV7243231(
                    process,
                    toolPath,
                    moviePath);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_required_started " +
                $"pid={process.Id} file='{Path.GetFileName(moviePath)}' " +
                $"tool='{toolPath}'");
            return true;
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            IOException)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_required_start_failed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
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

        var path =
            Environment.GetEnvironmentVariable("PATH");

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

        try
        {
            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
                _process.WaitForExit(2_000);
            }
        }
        catch {
        }

        _process.Dispose();
    }
}
