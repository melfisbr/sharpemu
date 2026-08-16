// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_RECENT_IMPORT_HOTPATH_V1_8_7
    private static readonly bool FullRecentImportDiagnosticsV187 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_FULL_RECENT_IMPORT_DIAGNOSTICS"),
            "1",
            StringComparison.Ordinal);

    // RecentImportTrace is diagnostic-only. Exact LastImportNid, return RIP,
    // GPR arguments, import count and result continue to be updated by the
    // existing guest-thread state on every import.
    private static bool ShouldCaptureRecentImportTraceV187(long dispatchIndex) =>
        FullRecentImportDiagnosticsV187 ||
        dispatchIndex < 4096 ||
        (dispatchIndex & 0x7FL) == 0;
}
