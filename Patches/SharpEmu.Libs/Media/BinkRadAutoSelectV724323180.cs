// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.IO;
using System.Runtime.CompilerServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.8: select the RAD compatibility backend for normal SharpEmu
/// launches when the user already has RAD Video Tools installed/configured.
/// Explicit SHARPEMU_BINK_MODE values always win.
/// </summary>
internal static class BinkRadAutoSelectV724323180
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (BinkGuestOwnedRuntimeV7600.Enabled)
        {
            return;
        }

        if (!OperatingSystem.IsWindows() ||
            !string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE")))
        {
            return;
        }

        var configured = Environment.GetEnvironmentVariable("SHARPEMU_RADVIDEO64");
        if (IsRadVideo64(configured))
        {
            SelectRad("environment");
            return;
        }

        var configFile = Path.Combine(
            AppContext.BaseDirectory,
            "plugins",
            "bink2",
            "radvideo64.path");

        try
        {
            if (!File.Exists(configFile))
            {
                return;
            }

            var path = File.ReadAllText(configFile).Trim().Trim('"');
            if (IsRadVideo64(path))
            {
                Environment.SetEnvironmentVariable(
                    "SHARPEMU_RADVIDEO64",
                    Path.GetFullPath(path),
                    EnvironmentVariableTarget.Process);
                SelectRad("radvideo64.path");
            }
        }
        catch (IOException)
        {
        }
    }

    private static void SelectRad(string source)
    {
        Environment.SetEnvironmentVariable(
            "SHARPEMU_BINK_MODE",
            "rad",
            EnvironmentVariableTarget.Process);
        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.rad_auto_selected source={source} " +
            "decode_owner=official-rad embedded_required=True");
    }

    private static bool IsRadVideo64(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        try
        {
            var candidate = path.Trim().Trim('"');
            return File.Exists(candidate) &&
                   string.Equals(
                       Path.GetFileName(candidate),
                       "radvideo64.exe",
                       StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }
}
