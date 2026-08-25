// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;
using SharpEmu.HLE.Host;

namespace SharpEmu.Libs.Ime;

/// <summary>
/// PS-style IME surface rendered by SharpEmu inside the SDL/Vulkan game window.
/// It is emulator-owned system UI, matching the role of libSceImeDialog on PS5;
/// no WinForms, PowerShell child window or external desktop surface is used.
/// </summary>
internal static class ImeInWindowOverlay
{
    public const int PanelWidth = 900;
    public const int PanelHeight = 500;

    private const int GlyphColumns = 5;
    private const int GlyphRows = 7;
    private const int GlyphScale = 2;
    private const int CellWidth = (GlyphColumns + 1) * GlyphScale;
    private const int LineHeight = (GlyphRows + 2) * GlyphScale;

    private static readonly object Gate = new();

    private static readonly string[][] KeyRows =
    [
        ["1","2","3","4","5","6","7","8","9","0","@"],
        ["Q","W","E","R","T","Y","U","I","O","P","#"],
        ["A","S","D","F","G","H","J","K","L","'","/"],
        ["Z","X","C","V","B","N","M",",",".","?","!"],
        ["SPACE","BACK","DONE"],
    ];

    private static bool _active;
    private static bool _resultReady;
    private static bool _canceled;
    private static long _generation;
    private static int _maxTextLength = 16;
    private static string _text = string.Empty;
    private static int _selectedRow;
    private static int _selectedColumn;
    private static HostGamepadButtons _lastButtons;
    private static long _openCount;
    private static long _inputCount;
    private static long _resultCount;

    public static bool Active
    {
        get
        {
            lock (Gate)
            {
                return _active;
            }
        }
    }

    public static void Open(long generation, string initialText, uint maxTextLength)
    {
        lock (Gate)
        {
            _generation = generation;
            _maxTextLength = Math.Clamp(checked((int)Math.Min(maxTextLength, 512u)), 1, 512);
            _text = initialText.Length <= _maxTextLength
                ? initialText
                : initialText[.._maxTextLength];
            _selectedRow = 0;
            _selectedColumn = 0;
            _resultReady = false;
            _canceled = false;
            _lastButtons = HostGamepadButtons.None;
            _active = true;
        }

        var count = Interlocked.Increment(ref _openCount);
        Console.Error.WriteLine(
            $"[V74.0.88][IME_IN_WINDOW] open count={count} generation={generation} " +
            $"max={maxTextLength} initial_chars={initialText.Length} backend=sdl-vulkan-overlay");
    }

    public static void Close(long generation)
    {
        lock (Gate)
        {
            if (_generation != generation)
            {
                return;
            }

            _active = false;
            _resultReady = false;
            _lastButtons = HostGamepadButtons.None;
        }
    }

    public static bool TryTakeResult(out ImeOverlayResult result)
    {
        lock (Gate)
        {
            if (!_resultReady)
            {
                result = default;
                return false;
            }

            result = new ImeOverlayResult(_generation, _text, _canceled);
            _resultReady = false;
            _active = false;
            _lastButtons = HostGamepadButtons.None;
        }

        var count = Interlocked.Increment(ref _resultCount);
        Console.Error.WriteLine(
            $"[V74.0.88][IME_IN_WINDOW] result count={count} generation={result.Generation} " +
            $"canceled={result.Canceled} chars={result.Text.Length}");
        return true;
    }

    public static void InsertCharacter(char value)
    {
        lock (Gate)
        {
            if (!_active || _text.Length >= _maxTextLength || char.IsControl(value))
            {
                return;
            }

            _text += value;
        }

        TraceInput("character");
    }

    public static void InsertSpace()
    {
        InsertCharacter(' ');
    }

    public static void Backspace()
    {
        lock (Gate)
        {
            if (!_active || _text.Length == 0)
            {
                return;
            }

            _text = _text[..^1];
        }

        TraceInput("backspace");
    }

    public static void Confirm()
    {
        lock (Gate)
        {
            if (!_active)
            {
                return;
            }

            _canceled = false;
            _resultReady = true;
        }

        TraceInput("done");
    }

    public static void Cancel()
    {
        lock (Gate)
        {
            if (!_active)
            {
                return;
            }

            _canceled = true;
            _resultReady = true;
        }

        TraceInput("cancel");
    }

    public static void MoveSelection(int deltaX, int deltaY)
    {
        lock (Gate)
        {
            if (!_active)
            {
                return;
            }

            if (deltaY != 0)
            {
                _selectedRow = (_selectedRow + deltaY + KeyRows.Length) % KeyRows.Length;
                _selectedColumn = Math.Min(_selectedColumn, KeyRows[_selectedRow].Length - 1);
            }

            if (deltaX != 0)
            {
                var width = KeyRows[_selectedRow].Length;
                _selectedColumn = (_selectedColumn + deltaX + width) % width;
            }
        }

        TraceInput("navigate");
    }

    public static void ActivateSelected()
    {
        string key;
        lock (Gate)
        {
            if (!_active)
            {
                return;
            }

            key = KeyRows[_selectedRow][_selectedColumn];
        }

        switch (key)
        {
            case "SPACE":
                InsertSpace();
                break;
            case "BACK":
                Backspace();
                break;
            case "DONE":
                Confirm();
                break;
            default:
                InsertCharacter(char.ToLowerInvariant(key[0]));
                break;
        }
    }

    public static void HandleGamepadButtons(HostGamepadButtons buttons)
    {
        HostGamepadButtons pressed;
        lock (Gate)
        {
            if (!_active)
            {
                _lastButtons = buttons;
                return;
            }

            pressed = buttons & ~_lastButtons;
            _lastButtons = buttons;
        }

        if ((pressed & HostGamepadButtons.Up) != 0) MoveSelection(0, -1);
        if ((pressed & HostGamepadButtons.Down) != 0) MoveSelection(0, 1);
        if ((pressed & HostGamepadButtons.Left) != 0) MoveSelection(-1, 0);
        if ((pressed & HostGamepadButtons.Right) != 0) MoveSelection(1, 0);
        if ((pressed & HostGamepadButtons.Cross) != 0) ActivateSelected();
        if ((pressed & HostGamepadButtons.Circle) != 0) Cancel();
        if ((pressed & HostGamepadButtons.Square) != 0) Backspace();
        if ((pressed & HostGamepadButtons.Options) != 0) Confirm();
    }

    /// <summary>Rasterizes the IME panel as tightly packed BGRA pixels.</summary>
    public static void Fill(Span<byte> bgra)
    {
        string text;
        int selectedRow;
        int selectedColumn;
        lock (Gate)
        {
            text = _text;
            selectedRow = _selectedRow;
            selectedColumn = _selectedColumn;
        }

        FillRect(bgra, 0, 0, PanelWidth, PanelHeight, 0x12, 0x16, 0x1E);
        FillRect(bgra, 0, 0, PanelWidth, 54, 0x20, 0x25, 0x30);
        DrawString(bgra, 28, 20, "ENTER YOUR PLAYER'S NAME", 0xEE, 0xEE, 0xF2);

        FillRect(bgra, 28, 70, PanelWidth - 56, 58, 0x2A, 0x30, 0x3D);
        DrawString(bgra, 44, 90, text + "_", 0xFF, 0xFF, 0xFF);

        const int keyWidth = 68;
        const int keyHeight = 52;
        const int keyGap = 8;
        const int startX = 30;
        const int startY = 150;

        for (var row = 0; row < 4; row++)
        {
            var keys = KeyRows[row];
            for (var column = 0; column < keys.Length; column++)
            {
                var x = startX + column * (keyWidth + keyGap);
                var y = startY + row * (keyHeight + keyGap);
                var selected = row == selectedRow && column == selectedColumn;
                FillRect(
                    bgra,
                    x,
                    y,
                    keyWidth,
                    keyHeight,
                    selected ? (byte)0x4A : (byte)0x2A,
                    selected ? (byte)0x86 : (byte)0x31,
                    selected ? (byte)0x8C : (byte)0x3D);
                DrawCenteredString(
                    bgra,
                    x,
                    y,
                    keyWidth,
                    keyHeight,
                    keys[column],
                    0xF4,
                    0xF4,
                    0xF4);
            }
        }

        var specialY = 396;
        DrawSpecialKey(bgra, 30, specialY, 360, 58, "SPACE", selectedRow == 4 && selectedColumn == 0);
        DrawSpecialKey(bgra, 402, specialY, 210, 58, "BACK", selectedRow == 4 && selectedColumn == 1);
        DrawSpecialKey(bgra, 624, specialY, 246, 58, "DONE", selectedRow == 4 && selectedColumn == 2);

        DrawString(
            bgra,
            30,
            472,
            "DPAD/ARROWS MOVE  X/ENTER SELECT  O/ESC CANCEL  SQUARE/BACKSPACE DELETE",
            0xA8,
            0xB0,
            0xC0);
    }

    private static void DrawSpecialKey(
        Span<byte> bgra,
        int x,
        int y,
        int width,
        int height,
        string text,
        bool selected)
    {
        FillRect(
            bgra,
            x,
            y,
            width,
            height,
            selected ? (byte)0x4A : (byte)0x2A,
            selected ? (byte)0x86 : (byte)0x31,
            selected ? (byte)0x8C : (byte)0x3D);
        DrawCenteredString(bgra, x, y, width, height, text, 0xF4, 0xF4, 0xF4);
    }

    private static void DrawCenteredString(
        Span<byte> bgra,
        int x,
        int y,
        int width,
        int height,
        string text,
        byte r,
        byte g,
        byte b)
    {
        var textWidth = text.Length * CellWidth;
        DrawString(
            bgra,
            x + Math.Max(0, (width - textWidth) / 2),
            y + Math.Max(0, (height - GlyphRows * GlyphScale) / 2),
            text,
            r,
            g,
            b);
    }

    private static void FillRect(
        Span<byte> bgra,
        int x,
        int y,
        int width,
        int height,
        byte r,
        byte g,
        byte b)
    {
        var endX = Math.Min(PanelWidth, x + width);
        var endY = Math.Min(PanelHeight, y + height);
        for (var py = Math.Max(0, y); py < endY; py++)
        {
            for (var px = Math.Max(0, x); px < endX; px++)
            {
                SetPixel(bgra, px, py, r, g, b);
            }
        }
    }

    private static void DrawString(
        Span<byte> bgra,
        int x,
        int y,
        string text,
        byte r,
        byte g,
        byte b)
    {
        var penX = x;
        foreach (var raw in text)
        {
            var c = char.ToUpperInvariant(raw);
            if (c < ' ' || c > 'Z')
            {
                c = '?';
            }

            var glyph = Font.Slice((c - ' ') * GlyphColumns, GlyphColumns);
            for (var column = 0; column < GlyphColumns; column++)
            {
                var bits = glyph[column];
                for (var row = 0; row < GlyphRows; row++)
                {
                    if ((bits & (1 << row)) == 0)
                    {
                        continue;
                    }

                    for (var sy = 0; sy < GlyphScale; sy++)
                    {
                        for (var sx = 0; sx < GlyphScale; sx++)
                        {
                            SetPixel(
                                bgra,
                                penX + column * GlyphScale + sx,
                                y + row * GlyphScale + sy,
                                r,
                                g,
                                b);
                        }
                    }
                }
            }

            penX += CellWidth;
            if (penX >= PanelWidth - CellWidth)
            {
                break;
            }
        }
    }

    private static void SetPixel(Span<byte> bgra, int x, int y, byte r, byte g, byte b)
    {
        if ((uint)x >= PanelWidth || (uint)y >= PanelHeight)
        {
            return;
        }

        var offset = (y * PanelWidth + x) * 4;
        bgra[offset] = b;
        bgra[offset + 1] = g;
        bgra[offset + 2] = r;
        bgra[offset + 3] = 0xFF;
    }

    private static void TraceInput(string action)
    {
        var count = Interlocked.Increment(ref _inputCount);
        if (count <= 32 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.88][IME_IN_WINDOW] input count={count} action={action}");
        }
    }

    private static ReadOnlySpan<byte> Font =>
    [
        0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x5F,0x00,0x00,
        0x00,0x07,0x00,0x07,0x00, 0x14,0x7F,0x14,0x7F,0x14,
        0x24,0x2A,0x7F,0x2A,0x12, 0x23,0x13,0x08,0x64,0x62,
        0x36,0x49,0x55,0x22,0x50, 0x00,0x05,0x03,0x00,0x00,
        0x00,0x1C,0x22,0x41,0x00, 0x00,0x41,0x22,0x1C,0x00,
        0x08,0x2A,0x1C,0x2A,0x08, 0x08,0x08,0x3E,0x08,0x08,
        0x00,0x50,0x30,0x00,0x00, 0x08,0x08,0x08,0x08,0x08,
        0x00,0x60,0x60,0x00,0x00, 0x20,0x10,0x08,0x04,0x02,
        0x3E,0x51,0x49,0x45,0x3E, 0x00,0x42,0x7F,0x40,0x00,
        0x42,0x61,0x51,0x49,0x46, 0x21,0x41,0x45,0x4B,0x31,
        0x18,0x14,0x12,0x7F,0x10, 0x27,0x45,0x45,0x45,0x39,
        0x3C,0x4A,0x49,0x49,0x30, 0x01,0x71,0x09,0x05,0x03,
        0x36,0x49,0x49,0x49,0x36, 0x06,0x49,0x49,0x29,0x1E,
        0x00,0x36,0x36,0x00,0x00, 0x00,0x56,0x36,0x00,0x00,
        0x00,0x08,0x14,0x22,0x41, 0x14,0x14,0x14,0x14,0x14,
        0x41,0x22,0x14,0x08,0x00, 0x02,0x01,0x51,0x09,0x06,
        0x32,0x49,0x79,0x41,0x3E, 0x7E,0x11,0x11,0x11,0x7E,
        0x7F,0x49,0x49,0x49,0x36, 0x3E,0x41,0x41,0x41,0x22,
        0x7F,0x41,0x41,0x22,0x1C, 0x7F,0x49,0x49,0x49,0x41,
        0x7F,0x09,0x09,0x09,0x01, 0x3E,0x41,0x49,0x49,0x7A,
        0x7F,0x08,0x08,0x08,0x7F, 0x00,0x41,0x7F,0x41,0x00,
        0x20,0x40,0x41,0x3F,0x01, 0x7F,0x08,0x14,0x22,0x41,
        0x7F,0x40,0x40,0x40,0x40, 0x7F,0x02,0x0C,0x02,0x7F,
        0x7F,0x04,0x08,0x10,0x7F, 0x3E,0x41,0x41,0x41,0x3E,
        0x7F,0x09,0x09,0x09,0x06, 0x3E,0x41,0x51,0x21,0x5E,
        0x7F,0x09,0x19,0x29,0x46, 0x46,0x49,0x49,0x49,0x31,
        0x01,0x01,0x7F,0x01,0x01, 0x3F,0x40,0x40,0x40,0x3F,
        0x1F,0x20,0x40,0x20,0x1F, 0x3F,0x40,0x38,0x40,0x3F,
        0x63,0x14,0x08,0x14,0x63, 0x07,0x08,0x70,0x08,0x07,
        0x61,0x51,0x49,0x45,0x43,
    ];

    internal readonly record struct ImeOverlayResult(long Generation, string Text, bool Canceled);
}
