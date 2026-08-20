// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace SharpEmu.Logging;

public static class SharpEmuLog
{
    private static readonly ConcurrentDictionary<string, SharpEmuLogger> LoggerByCategory =
        new(StringComparer.Ordinal);
    private static readonly object ConfigurationSync = new();
    private static readonly long StartTimestamp = Stopwatch.GetTimestamp();

    private static volatile LogLevel _minimumLevel = ResolveMinimumLevelFromEnvironment();
    private static bool _fileCapturesAllLevels;
    private static long _sequence;
    private static ISharpEmuLogSink _sink = ResolveSinkFromEnvironment();

    /// <summary>
    /// Entries below this level are dropped. When a SHARPEMU_LOG_FILE sink is
    /// active it only limits the console — the file receives every level.
    /// <see cref="LogLevel.None"/> disables logging entirely, file included.
    /// </summary>
    public static LogLevel MinimumLevel
    {
        get => _minimumLevel;
        set => _minimumLevel = value;
    }

    public static ISharpEmuLogSink Sink
    {
        get
        {
            lock (ConfigurationSync)
            {
                return _sink;
            }
        }

        set
        {
            ArgumentNullException.ThrowIfNull(value);
            lock (ConfigurationSync)
            {
                if (ReferenceEquals(_sink, value))
                {
                    return;
                }

                _fileCapturesAllLevels = false;

                if (_sink is IDisposable disposable)
                {
                    try
                    {
                        disposable.Dispose();
                    }
                    catch
                    {
                    }
                }

                _sink = value;
            }
        }
    }

    public static void Configure(LogLevel? minimumLevel = null, ISharpEmuLogSink? sink = null)
    {
        if (minimumLevel.HasValue)
        {
            _minimumLevel = minimumLevel.Value;
        }

        if (sink is not null)
        {
            Sink = sink;
        }
    }

    /// <summary>
    /// Adds ambient fields to all log entries produced inside the returned scope.
    /// Example:
    /// using var _ = SharpEmuLog.BeginScope("gpu.submit",
    ///     ("queue", queueId), ("submit", submitId), ("guest_pc", $"0x{pc:X}"));
    /// </summary>
    public static IDisposable BeginScope(
        string name,
        params (string Key, object? Value)[] fields)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        return LogContext.Push(name, operationId: null, ToPairs(fields));
    }

    /// <summary>
    /// Starts a correlated operation. Every log inside the scope receives a
    /// compact operation id plus the supplied diagnostic fields.
    /// </summary>
    public static IDisposable BeginOperation(
        string name,
        params (string Key, object? Value)[] fields)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var operationId = Convert.ToHexString(Guid.NewGuid().ToByteArray().AsSpan(0, 6)).ToLowerInvariant();
        return LogContext.Push(name, operationId, ToPairs(fields));
    }

    /// <summary>
    /// Adds a process-wide diagnostic field, useful for title_id, game_version,
    /// cpu_backend, gpu_name, driver_version and similar stable run metadata.
    /// Passing null removes the field.
    /// </summary>
    public static void SetGlobalContext(string key, object? value) => LogContext.SetGlobal(key, value);

    public static void ClearGlobalContext(string key) => LogContext.ClearGlobal(key);

    /// <summary>
    /// Disposes the active sink if it implements IDisposable.
    /// Call at shutdown to flush file buffers.
    /// </summary>
    public static void Shutdown()
    {
        lock (ConfigurationSync)
        {
            if (_sink is IDisposable disposable)
            {
                disposable.Dispose();
            }
        }
    }

    public static SharpEmuLogger For(string category)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(category);
        return LoggerByCategory.GetOrAdd(category, static key => new SharpEmuLogger(key));
    }

    public static bool TryParseLevel(string? text, out LogLevel level)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            level = default;
            return false;
        }

        var normalized = text.Trim();
        if (Enum.TryParse<LogLevel>(normalized, ignoreCase: true, out level) &&
            Enum.IsDefined(level))
        {
            return true;
        }

        if (string.Equals(normalized, "warn", StringComparison.OrdinalIgnoreCase))
        {
            level = LogLevel.Warning;
            return true;
        }

        if (string.Equals(normalized, "fatal", StringComparison.OrdinalIgnoreCase))
        {
            level = LogLevel.Critical;
            return true;
        }

        level = default;
        return false;
    }

    internal static bool IsEnabled(LogLevel level)
    {
        var minimum = _minimumLevel;
        if (minimum == LogLevel.None)
        {
            return false;
        }

        return _fileCapturesAllLevels || level >= minimum;
    }

    internal static void Write(
        LogLevel level,
        string category,
        string message,
        Exception? exception,
        string sourceFilePath,
        int sourceLine,
        string sourceMemberName)
    {
        if (!IsEnabled(level))
        {
            return;
        }

        var context = LogContext.Capture();
        var elapsedMs = Stopwatch.GetElapsedTime(StartTimestamp).TotalMilliseconds;
        var entry = new LogEntry(
            DateTimeOffset.Now,
            level,
            category,
            message,
            Path.GetFileName(sourceFilePath),
            sourceLine,
            sourceMemberName,
            exception,
            Sequence: Interlocked.Increment(ref _sequence),
            ElapsedMilliseconds: elapsedMs,
            ProcessId: Environment.ProcessId,
            ManagedThreadId: Environment.CurrentManagedThreadId,
            ThreadName: Thread.CurrentThread.Name,
            OperationId: context.OperationId,
            ScopeName: context.ScopeName,
            Context: context.Fields);

        ISharpEmuLogSink sink;
        lock (ConfigurationSync)
        {
            sink = _sink;
        }

        sink.Write(in entry);
    }

    private static IEnumerable<KeyValuePair<string, object?>> ToPairs(
        (string Key, object? Value)[]? fields)
    {
        if (fields is null)
        {
            yield break;
        }

        foreach (var field in fields)
        {
            yield return new KeyValuePair<string, object?>(field.Key, field.Value);
        }
    }

    private static LogLevel ResolveMinimumLevelFromEnvironment()
    {
        var raw = Environment.GetEnvironmentVariable("SHARPEMU_LOG_LEVEL");
        return TryParseLevel(raw, out var level) ? level : LogLevel.Info;
    }

    private static bool ResolveColorEnabledFromEnvironment()
    {
        if (Console.IsOutputRedirected)
        {
            return false;
        }

        var raw = Environment.GetEnvironmentVariable("SHARPEMU_LOG_NO_COLOR");
        return !IsTrueLike(raw);
    }

    private static ISharpEmuLogSink ResolveSinkFromEnvironment()
    {
        var consoleSink = new ConsoleLogSink(
            useColors: ResolveColorEnabledFromEnvironment(),
            includeTimestamp: false);

        var logFilePath = Environment.GetEnvironmentVariable("SHARPEMU_LOG_FILE");
        if (!string.IsNullOrWhiteSpace(logFilePath))
        {
            try
            {
                var fileSink = new FileLogSink(logFilePath, append: true, includeTimestamp: true);
                _fileCapturesAllLevels = true;
                return new CompositeLogSink(new MinimumLevelFilterSink(consoleSink), fileSink);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[SHARPEMU_LOG] Failed to open log file '{logFilePath}': {ex.Message}");
            }
        }

        return consoleSink;
    }

    private sealed class MinimumLevelFilterSink : ISharpEmuLogSink
    {
        private readonly ISharpEmuLogSink _inner;

        internal MinimumLevelFilterSink(ISharpEmuLogSink inner) => _inner = inner;

        public void Write(in LogEntry entry)
        {
            if (entry.Level >= _minimumLevel)
            {
                _inner.Write(in entry);
            }
        }
    }

    private static bool IsTrueLike(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        return text.Trim() switch
        {
            "1" => true,
            "true" => true,
            "TRUE" => true,
            "yes" => true,
            "YES" => true,
            "on" => true,
            "ON" => true,
            _ => false,
        };
    }
}
