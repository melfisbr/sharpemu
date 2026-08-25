// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Globalization;
using System.Text;

namespace SharpEmu.Libs.Media;

internal static class BinkIntroHarnessTrace
{
    private static readonly object Gate = new();
    private static long _sequence;

    internal static bool Enabled =>
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_INTRO_HARNESS"),
            "1",
            StringComparison.Ordinal);

    internal static void Event(string stage, string? detail = null)
    {
        if (!Enabled) return;

        try
        {
            var sequence = Interlocked.Increment(ref _sequence);
            var path = Environment.GetEnvironmentVariable("SHARPEMU_BINK_HARNESS_LOG");
            if (string.IsNullOrWhiteSpace(path))
                path = Path.Combine(Path.GetTempPath(), "SharpEmu_BinkIntroHarness.log");

            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
                Directory.CreateDirectory(directory);

            var line =
                DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) +
                " #" + sequence.ToString(CultureInfo.InvariantCulture) +
                " tid=" + Environment.CurrentManagedThreadId.ToString(CultureInfo.InvariantCulture) +
                " [" + stage + "]" +
                (string.IsNullOrEmpty(detail) ? "" : " " + detail) +
                Environment.NewLine;

            lock (Gate)
                File.AppendAllText(path, line, new UTF8Encoding(false));
        }
        catch
        {
            // Diagnostics must never affect guest execution.
        }
    }
}
