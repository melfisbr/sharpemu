// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_IMPORT_DIAGNOSTIC_HOTPATH_V1_8_4
    private static readonly bool FullImportStackDiagnosticsV184 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_FULL_IMPORT_STACK_DIAGNOSTICS"),
            "1",
            StringComparison.Ordinal);

    private static readonly bool AmprHotTraceEnabledV184 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_LOG_AMPR"),
            "1",
            StringComparison.Ordinal);

    private static bool ShouldCaptureFullImportStackV184(long dispatchIndex) =>
        FullImportStackDiagnosticsV184 ||
        dispatchIndex < 4096 ||
        (dispatchIndex & 0xFFL) == 0;
}
