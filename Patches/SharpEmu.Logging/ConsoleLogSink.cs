// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.IO;

namespace SharpEmu.Logging;

public sealed class ConsoleLogSink : ISharpEmuLogSink
{
    private readonly object _sync = new();

    public ConsoleLogSink(bool useColors = true, bool includeTimestamp = false)
    {
        UseColors = useColors;
        IncludeTimestamp = includeTimestamp;
    }

    public bool UseColors { get; set; }
    public bool IncludeTimestamp { get; set; }

    /// <summary>
    /// Console stays compact by default. Set SHARPEMU_LOG_CONSOLE_CONTEXT=1
    /// to show sequence/thread/correlation information interactively.
    /// </summary>
    public bool IncludeExecutionContext { get; set; } =
        IsTrueLike(Environment.GetEnvironmentVariable("SHARPEMU_LOG_CONSOLE_CONTEXT"));

    public void Write(in LogEntry entry)
    {
        lock (_sync)
        {
            var writer = entry.Level >= LogLevel.Error ? Console.Error : Console.Out;

            if (IncludeTimestamp)
            {
                writer.Write('[');
                writer.Write(entry.Timestamp.ToString("HH:mm:ss.fff"));
                writer.Write(']');
            }

            var levelLabel = ToLevelLabel(entry.Level);
            WriteLevelSegment(writer, levelLabel, entry.Level);
            writer.Write('[');
            writer.Write(entry.Category);
            writer.Write(']');

            if (IncludeExecutionContext)
            {
                writer.Write("[#");
                writer.Write(entry.Sequence);
                writer.Write("][t");
                writer.Write(entry.ManagedThreadId);
                writer.Write(']');

                if (!string.IsNullOrWhiteSpace(entry.OperationId))
                {
                    writer.Write("[op=");
                    writer.Write(entry.OperationId);
                    writer.Write(']');
                }
            }

            writer.Write(' ');
            writer.Write(entry.SourceFileName);
            if (entry.SourceLine > 0)
            {
                writer.Write(':');
                writer.Write(entry.SourceLine);
            }

            if (!string.IsNullOrWhiteSpace(entry.SourceMemberName))
            {
                writer.Write('#');
                writer.Write(entry.SourceMemberName);
            }

            writer.Write(' ');
            WriteMessageSegment(writer, entry.Message);
            writer.WriteLine();

            if (entry.Exception is not null)
            {
                writer.WriteLine(entry.Exception);
            }
        }
    }

    private static string ToLevelLabel(LogLevel level)
    {
        return level switch
        {
            LogLevel.Trace => "TRACE",
            LogLevel.Debug => "DEBUG",
            LogLevel.Info => "INFO",
            LogLevel.Warning => "WARNING",
            LogLevel.Error => "ERROR",
            LogLevel.Critical => "CRITICAL",
            _ => "LOG",
        };
    }

    private void WriteLevelSegment(TextWriter writer, string label, LogLevel level)
    {
        if (!UseColors)
        {
            writer.Write('[');
            writer.Write(label);
            writer.Write(']');
            return;
        }

        var originalColor = Console.ForegroundColor;
        Console.ForegroundColor = GetLevelColor(level);
        writer.Write('[');
        writer.Write(label);
        writer.Write(']');
        Console.ForegroundColor = originalColor;
    }

    private static ConsoleColor GetLevelColor(LogLevel level)
    {
        return level switch
        {
            LogLevel.Trace => ConsoleColor.DarkGray,
            LogLevel.Debug => ConsoleColor.Gray,
            LogLevel.Info => ConsoleColor.Blue,
            LogLevel.Warning => ConsoleColor.Yellow,
            LogLevel.Error => ConsoleColor.Red,
            LogLevel.Critical => ConsoleColor.DarkRed,
            _ => ConsoleColor.White,
        };
    }

    private void WriteMessageSegment(TextWriter writer, string message)
    {
        if (!UseColors || !TryGetMessageColor(message, out var messageColor))
        {
            writer.Write(message);
            return;
        }

        var originalColor = Console.ForegroundColor;
        Console.ForegroundColor = messageColor;
        writer.Write(message);
        Console.ForegroundColor = originalColor;
    }

    private static bool TryGetMessageColor(string message, out ConsoleColor color)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            color = default;
            return false;
        }

        if (ContainsIgnoreCase(message, "unresolved import") ||
            ContainsIgnoreCase(message, "unresolved symbol") ||
            ContainsIgnoreCase(message, "unsupported vector opcode") ||
            ContainsIgnoreCase(message, "shader") && ContainsIgnoreCase(message, "error") ||
            ContainsIgnoreCase(message, "hot_unresolved_imports=") ||
            ContainsIgnoreCase(message, "unresolved_imports_hit="))
        {
            color = ConsoleColor.Red;
            return true;
        }

        if (ContainsIgnoreCase(message, "syscall") ||
            ContainsIgnoreCase(message, "UnhandledSyscall") ||
            ContainsIgnoreCase(message, "stall") ||
            ContainsIgnoreCase(message, "timeout") ||
            ContainsIgnoreCase(message, "deadlock"))
        {
            color = ConsoleColor.DarkYellow;
            return true;
        }

        if (ContainsIgnoreCase(message, "Import trace") ||
            ContainsIgnoreCase(message, "import_stub_return") ||
            ContainsIgnoreCase(message, "last_import=") ||
            ContainsIgnoreCase(message, "hot_imports=") ||
            ContainsIgnoreCase(message, "resolved import") ||
            ContainsIgnoreCase(message, "present") ||
            ContainsIgnoreCase(message, "flip"))
        {
            color = ConsoleColor.Blue;
            return true;
        }

        color = default;
        return false;
    }

    private static bool ContainsIgnoreCase(string text, string value)
    {
        return text.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static bool IsTrueLike(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        return text.Trim().Equals("1", StringComparison.OrdinalIgnoreCase) ||
               text.Trim().Equals("true", StringComparison.OrdinalIgnoreCase) ||
               text.Trim().Equals("yes", StringComparison.OrdinalIgnoreCase) ||
               text.Trim().Equals("on", StringComparison.OrdinalIgnoreCase);
    }
}
