// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;

namespace SharpEmu.Logging;

/// <summary>
/// Lightweight ambient diagnostic context. Values flow through async calls via
/// AsyncLocal and are copied into LogEntry only when an entry is emitted.
/// </summary>
internal static class LogContext
{
    private sealed class ScopeNode
    {
        public ScopeNode(
            ScopeNode? parent,
            string? name,
            string? operationId,
            IReadOnlyDictionary<string, string>? fields)
        {
            Parent = parent;
            Name = name;
            OperationId = operationId;
            Fields = fields;
        }

        public ScopeNode? Parent { get; }
        public string? Name { get; }
        public string? OperationId { get; }
        public IReadOnlyDictionary<string, string>? Fields { get; }
    }

    private sealed class ScopeLease : IDisposable
    {
        private readonly ScopeNode? _previous;
        private bool _disposed;

        public ScopeLease(ScopeNode? previous) => _previous = previous;

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            Current.Value = _previous;
        }
    }

    private static readonly AsyncLocal<ScopeNode?> Current = new();
    private static readonly ConcurrentDictionary<string, string> Global =
        new(StringComparer.Ordinal);

    public static IDisposable Push(
        string? name,
        string? operationId,
        IEnumerable<KeyValuePair<string, object?>>? fields)
    {
        var normalized = Normalize(fields);
        var previous = Current.Value;
        Current.Value = new ScopeNode(previous, name, operationId, normalized);
        return new ScopeLease(previous);
    }

    public static void SetGlobal(string key, object? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        if (value is null)
        {
            Global.TryRemove(key, out _);
            return;
        }

        Global[key] = FormatValue(value);
    }

    public static void ClearGlobal(string key)
    {
        if (!string.IsNullOrWhiteSpace(key))
        {
            Global.TryRemove(key, out _);
        }
    }

    public static LogContextSnapshot Capture()
    {
        var node = Current.Value;
        string? scopeName = null;
        string? operationId = null;
        Dictionary<string, string>? fields = null;

        if (!Global.IsEmpty)
        {
            fields = new Dictionary<string, string>(Global, StringComparer.Ordinal);
        }

        // Walk from inner to outer. Inner scopes win for duplicate keys.
        for (var cursor = node; cursor is not null; cursor = cursor.Parent)
        {
            scopeName ??= cursor.Name;
            operationId ??= cursor.OperationId;

            if (cursor.Fields is null || cursor.Fields.Count == 0)
            {
                continue;
            }

            fields ??= new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var pair in cursor.Fields)
            {
                fields.TryAdd(pair.Key, pair.Value);
            }
        }

        return new LogContextSnapshot(scopeName, operationId, fields);
    }

    private static IReadOnlyDictionary<string, string>? Normalize(
        IEnumerable<KeyValuePair<string, object?>>? fields)
    {
        if (fields is null)
        {
            return null;
        }

        Dictionary<string, string>? result = null;
        foreach (var pair in fields)
        {
            if (string.IsNullOrWhiteSpace(pair.Key) || pair.Value is null)
            {
                continue;
            }

            result ??= new Dictionary<string, string>(StringComparer.Ordinal);
            result[pair.Key] = FormatValue(pair.Value);
        }

        return result;
    }

    private static string FormatValue(object value)
    {
        if (value is IFormattable formattable)
        {
            return formattable.ToString(null, CultureInfo.InvariantCulture) ?? string.Empty;
        }

        return value.ToString() ?? string.Empty;
    }
}

internal readonly record struct LogContextSnapshot(
    string? ScopeName,
    string? OperationId,
    IReadOnlyDictionary<string, string>? Fields);
