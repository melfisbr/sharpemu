// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    // SHARPEMU_DBFZ_APR_TRACE_GATE_V1_8_2_1
    //
    // V1.7.5 payload tracing remains available, but it is diagnostic evidence,
    // not required game semantics. Keep the branch at the import call site so
    // normal dispatch never enters the large trace helper.
    private static readonly bool DbfzAprPayloadTraceEnabledV1821 =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_APR_PAYLOAD_TRACE"),
            "1",
            StringComparison.Ordinal);
}
