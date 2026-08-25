// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.0.10: log/count shader translations that exceed a soft budget (default 40ms).

namespace SharpEmu.Libs.Gpu.Vulkan;

internal static class VulkanShaderCompileBudgetV7610
{
    private static readonly double BudgetMs =
        double.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_SHADER_TRANSLATE_BUDGET_MS"),
            out var ms)
            ? Math.Clamp(ms, 5.0, 500.0)
            : 40.0;

    private static long _overBudget;
    private static long _total;

    internal static void Note(string stage, ulong address, long startTicks, bool success)
    {
        if (startTicks == 0)
        {
            return;
        }

        Interlocked.Increment(ref _total);
        var elapsed = (System.Diagnostics.Stopwatch.GetTimestamp() - startTicks) *
            1000.0 / System.Diagnostics.Stopwatch.Frequency;
        if (elapsed < BudgetMs)
        {
            return;
        }

        var n = Interlocked.Increment(ref _overBudget);
        if (n <= 8 || n % 32 == 0)
        {
            Console.Error.WriteLine(
                $"[SHADER-BUDGET][V76.0.10] n={n} stage={stage} " +
                $"addr=0x{address:X16} ms={elapsed:F1} ok={(success ? 1 : 0)} " +
                $"budget_ms={BudgetMs:F0}");
        }
    }
}
