// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Core.Cpu.Debugging;

namespace SharpEmu.Core.Cpu;

public readonly struct CpuExecutionOptions
{
    public bool EnableDisasmDiagnostics { get; init; }

    public CpuExecutionEngine CpuEngine { get; init; }

    public bool StrictDynlibResolution { get; init; }

    public int ImportTraceLimit { get; init; }

    /// <summary>
    /// ELF DT_INIT / DT_INIT_ARRAY routines have no status-return contract.
    /// When enabled, a normal RET to the host is considered successful even if
    /// RAX contains a non-zero residual value. Traps, faults and forced guest
    /// exits are still treated as execution failures.
    /// </summary>
    public bool IgnoreGuestReturnValue { get; init; }

    /// <summary>
    /// An optional debugger attached to this execution session. When set, the
    /// dispatcher notifies it at each frame boundary via
    /// <see cref="ICpuDebugHook.OnFrameEnter"/> / <see cref="ICpuDebugHook.OnFrameExit"/>.
    /// Null when no debugger is attached, which is the default and imposes no
    /// runtime cost.
    /// </summary>
    public ICpuDebugHook? DebugHook { get; init; }
}
