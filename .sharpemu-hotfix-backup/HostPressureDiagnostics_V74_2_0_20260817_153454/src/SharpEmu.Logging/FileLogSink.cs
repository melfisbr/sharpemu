// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SharpEmu.Logging;

public sealed class FileLogSink : ISharpEmuLogSink, IDisposable
{
    private static readonly TimeSpan FlushInterval = TimeSpan.FromMilliseconds(500);

    private readonly object _sync = new();
    private readonly StreamWriter _writer;
    private readonly Timer _flushTimer;
    private bool _disposed;

    public FileLogSink(string path, bool append = true, bool includeTimestamp = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var fileStream = new FileStream(
            path,
            append ? FileMode.Append : FileMode.Create,
            FileAccess.Write,
            FileShare.Read,
            bufferSize: 65536,
            FileOptions.SequentialScan);

        _writer = new StreamWriter(fileStream, Encoding.UTF8, bufferSize: 65536)
        {
            AutoFlush = false
        };

        IncludeTimestamp = includeTimestamp;
        _flushTimer = new Timer(
            static state => ((FileLogSink)state!).FlushBuffered(),
            this,
            FlushInterval,
            FlushInterval);
    }

    public bool IncludeTimestamp { get; set; }

    /// <summary>
    /// Include sequence, monotonic elapsed time, PID/TID, operation/scope and
    /// structured diagnostic context in file output.
    /// </summary>
    public bool IncludeExecutionContext { get; set; } = true;

    public void Write(in LogEntry entry)
    {
        lock (_sync)
        {
            if (_disposed)
            {
                return;
            }

            if (IncludeTimestamp)
            {
                _writer.Write('[');
                _writer.Write(entry.Timestamp.ToString("yyyy-MM-dd HH:mm:ss.fff zzz"));
                _writer.Write(']');
            }

            _writer.Write('[');
            _writer.Write(ToLevelLabel(entry.Level));
            _writer.Write(']');
            _writer.Write('[');
            _writer.Write(entry.Category);
            _writer.Write(']');

            if (IncludeExecutionContext)
            {
                WriteExecutionContext(entry);
            }

            _writer.Write(' ');
            _writer.Write(entry.SourceFileName);
            if (entry.SourceLine > 0)
            {
                _writer.Write(':');
                _writer.Write(entry.SourceLine);
            }

            if (!string.IsNullOrWhiteSpace(entry.SourceMemberName))
            {
                _writer.Write('#');
                _writer.Write(entry.SourceMemberName);
            }

            _writer.Write(' ');
            _writer.WriteLine(entry.Message);

            if (entry.Exception is not null)
            {
                _writer.Write("[EXCEPTION] ");
                _writer.Write(entry.Exception.GetType().FullName);
                _writer.Write(": ");
                _writer.WriteLine(entry.Exception.Message);
                _writer.WriteLine(entry.Exception);
            }

            if (entry.Level >= LogLevel.Error)
            {
                _writer.Flush();
            }
        }
    }

    private void WriteExecutionContext(in LogEntry entry)
    {
        if (entry.Sequence > 0)
        {
            _writer.Write("[seq=");
            _writer.Write(entry.Sequence);
            _writer.Write(']');
        }

        _writer.Write("[+");
        _writer.Write(entry.ElapsedMilliseconds.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
        _writer.Write("ms]");

        if (entry.ProcessId > 0)
        {
            _writer.Write("[pid=");
            _writer.Write(entry.ProcessId);
            _writer.Write(']');
        }

        if (entry.ManagedThreadId > 0)
        {
            _writer.Write("[tid=");
            _writer.Write(entry.ManagedThreadId);
            _writer.Write(']');
        }

        if (!string.IsNullOrWhiteSpace(entry.ThreadName))
        {
            _writer.Write("[thread=");
            WriteEscaped(entry.ThreadName);
            _writer.Write(']');
        }

        if (!string.IsNullOrWhiteSpace(entry.OperationId))
        {
            _writer.Write("[op=");
            WriteEscaped(entry.OperationId);
            _writer.Write(']');
        }

        if (!string.IsNullOrWhiteSpace(entry.ScopeName))
        {
            _writer.Write("[scope=");
            WriteEscaped(entry.ScopeName);
            _writer.Write(']');
        }

        if (entry.Context is not null)
        {
            foreach (var pair in entry.Context)
            {
                _writer.Write('[');
                WriteEscaped(pair.Key);
                _writer.Write('=');
                WriteEscaped(pair.Value);
                _writer.Write(']');
            }
        }
    }

    private void WriteEscaped(string value)
    {
        foreach (var ch in value)
        {
            switch (ch)
            {
                case '\r':
                    _writer.Write("\\r");
                    break;
                case '\n':
                    _writer.Write("\\n");
                    break;
                case ']':
                    _writer.Write("\\]");
                    break;
                default:
                    _writer.Write(ch);
                    break;
            }
        }
    }

    private void FlushBuffered()
    {
        lock (_sync)
        {
            if (_disposed)
            {
                return;
            }

            _writer.Flush();
        }
    }

    public void Dispose()
    {
        _flushTimer.Dispose();

        lock (_sync)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _writer.Flush();
            _writer.Dispose();
        }
    }

    private static string ToLevelLabel(LogLevel level) => level switch
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
