// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using SharpEmu.HLE;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    /// <summary>
    /// V48.0: pure libc math is computational progress, not a scheduler/import
    /// boundary that by itself proves a deadlock. These functions are
    /// deterministic leaf work with no blocking semantics.
    ///
    /// This classification is deliberately based on the resolved export name,
    /// not on a title or NID. It therefore applies equally to any guest that
    /// legitimately performs high-frequency scalar math through HLE.
    /// </summary>
    private static bool IsPureLibcMathProgressBoundaryV48(ExportedFunction? export)
    {
        if (export is null ||
            !string.Equals(export.LibraryName, "libc", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return export.Name switch
        {
            "sin" or "sinf" or
            "cos" or "cosf" or
            "tan" or "tanf" or
            "sincos" or "sincosf" or
            "asin" or "asinf" or
            "acos" or "acosf" or
            "atan" or "atanf" or
            "atan2" or "atan2f" or
            "sqrt" or "sqrtf" or
            "cbrt" or "cbrtf" or
            "floor" or "floorf" or
            "ceil" or "ceilf" or
            "trunc" or "truncf" or
            "round" or "roundf" or
            "fabs" or "fabsf" or
            "fmin" or "fminf" or
            "fmax" or "fmaxf" or
            "fmod" or "fmodf" or
            "pow" or "powf" or
            "exp" or "expf" or
            "exp2" or "exp2f" or
            "log" or "logf" or
            "log2" or "log2f" or
            "log10" or "log10f"
                => true,
            _ => false,
        };
    }
}
