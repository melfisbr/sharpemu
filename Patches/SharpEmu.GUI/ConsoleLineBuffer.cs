// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;

namespace SharpEmu.GUI;

/// <summary>
/// Thread-safe bounded queue for emulator console output. When producers outrun
/// the UI, oldest pending lines are discarded instead of allowing unbounded RAM
/// growth. The UI reports the number discarded on the next flush.
/// </summary>
internal sealed class ConsoleLineBuffer
{
    private readonly object _gate = new();
    private readonly Queue<(string Line, bool IsError)> _lines = new();
    private readonly int _capacity;
    private long _droppedCount;

    public ConsoleLineBuffer(int capacity)
    {
        if (capacity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(capacity));
        }

        _capacity = capacity;
    }

    public bool IsEmpty
    {
        get
        {
            lock (_gate)
            {
                return _lines.Count == 0;
            }
        }
    }

    public void Enqueue(string line, bool isError)
    {
        lock (_gate)
        {
            while (_lines.Count >= _capacity)
            {
                _lines.Dequeue();
                _droppedCount++;
            }

            _lines.Enqueue((line, isError));
        }
    }

    public bool TryDequeue(out (string Line, bool IsError) pending)
    {
        lock (_gate)
        {
            if (_lines.Count == 0)
            {
                pending = default;
                return false;
            }

            pending = _lines.Dequeue();
            return true;
        }
    }

    public long ExchangeDroppedCount()
    {
        lock (_gate)
        {
            var dropped = _droppedCount;
            _droppedCount = 0;
            return dropped;
        }
    }
}
