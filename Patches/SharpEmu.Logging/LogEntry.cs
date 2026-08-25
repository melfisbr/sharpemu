// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;

namespace SharpEmu.Logging;

/// <summary>
/// Immutable event passed to log sinks. The execution/correlation fields are
/// intentionally optional so existing callers that construct LogEntry directly
/// remain source compatible.
/// </summary>
public readonly record struct LogEntry(
    DateTimeOffset Timestamp,
    LogLevel Level,
    string Category,
    string Message,
    string SourceFileName,
    int SourceLine,
    string SourceMemberName,
    Exception? Exception = null,
    long Sequence = 0,
    double ElapsedMilliseconds = 0,
    int ProcessId = 0,
    int ManagedThreadId = 0,
    string? ThreadName = null,
    string? OperationId = null,
    string? ScopeName = null,
    IReadOnlyDictionary<string, string>? Context = null);
