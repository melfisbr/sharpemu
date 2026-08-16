// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.5: corrected external RAD Video Tools BinkPlay launcher.
///
/// radvideo64.exe is the RAD front-end and "binkplay" selects the command-line
/// Bink player. BinkPlay has its own switch set; V31.4 incorrectly appended
/// "/#", which opened BinkPlay's syntax/help dialog and returned exit code 1.
///
/// The executable remains user-supplied and is never redistributed by SharpEmu.
/// This class is intentionally an EXTERNAL-PROCESS bridge. A true in-process
/// SharpEmu decoder requires the licensed/runtime Bink API and is audited by
/// RUN_6_RAD_RUNTIME_AUDIT.cmd.
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

            // V72.4.3.2.31.5 RAD_BINKPLAY_CLI_FIX
            //
            // Correct BinkPlay invocation:
            //   radvideo64.exe binkplay "<movie.bk2>"
            //
            // Do NOT append "/#". That is not part of the BinkPlay syntax
            // displayed by RAD Video Tools 2026.06 and caused V31.4 to show
            // the syntax dialog instead of playing the movie.
            start.ArgumentList.Add("binkplay");
            start.ArgumentList.Add(moviePath);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_command " +
                "syntax='radvideo64.exe binkplay <movie>' " +
                $"file='{Path.GetFileName(moviePath)}'");

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
        catch
        {
        }

        _process.Dispose();
    }
}
