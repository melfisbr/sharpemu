// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Libs.Kernel;

/// <summary>
/// Compatibility type retained for source compatibility.
///
/// The complete POSIX and scePthread mutex/condition export family, including
/// the libc startup aliases, is implemented by
/// <see cref="KernelPthreadCompatExports"/>. Keeping this type empty prevents
/// duplicate SysAbiExport registrations while allowing older source references
/// to continue compiling.
/// </summary>
public static class KernelPthreadLibcStartupExports
{
}
