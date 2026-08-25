// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;
using System.Buffers.Binary;
using System.Text;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Ime;

/// <summary>
/// libSceImeDialog compatibility backed by SharpEmu's in-window SDL/Vulkan
/// system-UI overlay. The guest lifecycle remains Init -> Running -> Result ->
/// Finished -> Term and the UTF-16 buffer is still committed from a live
/// guest CpuContext.
/// </summary>
public static class ImeDialogExports
{
    private const string V74088Marker = "SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI";

    private const int StatusNone = 0;
    private const int StatusRunning = 1;
    private const int StatusFinished = 2;
    private const int EndStatusOk = 0;
    private const int EndStatusCanceled = 1;
    private const int EndStatusAborted = 2;

    private const ulong ParamMaxTextLengthOffset = 0x24;
    private const ulong ParamInputTextBufferOffset = 0x28;
    private const int ImeDialogErrorInvalidAddress = unchecked((int)0x80BC0001);

    private static readonly object Gate = new();
    private static int _status = StatusNone;
    private static int _endStatus = EndStatusOk;
    private static long _generation;
    private static ulong _inputBufferAddress;
    private static uint _maxTextLength = 16;
    private static bool _completionReady;
    private static string? _pendingText;
    private static long _initCount;
    private static long _statusCount;
    private static long _resultCount;

    [SysAbiExport(
        Nid = "NUeBrN7hzf0",
        ExportName = "sceImeDialogInit",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogInit(CpuContext ctx)
    {
        var parameterAddress = ctx[CpuRegister.Rdi];
        if (parameterAddress == 0)
        {
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        if (!TryReadDialogParameter(ctx, parameterAddress, out var bufferAddress, out var maxTextLength))
        {
            Console.Error.WriteLine(
                $"[V74.0.88][IME_DIALOG] init_failed param=0x{parameterAddress:X16} reason=input-buffer-unreadable");
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        var initialText = TryReadUtf16Text(ctx, bufferAddress, maxTextLength) ?? string.Empty;
        long generation;
        lock (Gate)
        {
            generation = ++_generation;
            ImeInWindowOverlay.Close(generation - 1);
            _inputBufferAddress = bufferAddress;
            _maxTextLength = maxTextLength;
            _pendingText = null;
            _completionReady = false;
            _endStatus = EndStatusOk;
            _status = StatusRunning;
        }

        var count = Interlocked.Increment(ref _initCount);
        Console.Error.WriteLine(
            $"[V74.0.88][IME_DIALOG] init count={count} generation={generation} " +
            $"param=0x{parameterAddress:X16} buffer=0x{bufferAddress:X16} max={maxTextLength} " +
            $"initial_chars={initialText.Length} status=RUNNING backend=in-window");

        var forcedText = Environment.GetEnvironmentVariable("SHARPEMU_IME_TEXT");
        if (!string.IsNullOrEmpty(forcedText))
        {
            CompleteOverlay(
                generation,
                Truncate(forcedText, maxTextLength),
                EndStatusOk,
                "environment");
        }
        else
        {
            ImeInWindowOverlay.Open(generation, initialText, maxTextLength);
        }

        return SetReturn(ctx, 0);
    }

    [SysAbiExport(
        Nid = "IADmD4tScBY",
        ExportName = "sceImeDialogGetStatus",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogGetStatus(CpuContext ctx)
    {
        PumpCompletedOverlay(ctx);

        int status;
        lock (Gate)
        {
            status = _status;
        }

        var count = Interlocked.Increment(ref _statusCount);
        if (count <= 8 || (count & (count - 1)) == 0 || status == StatusFinished)
        {
            Console.Error.WriteLine(
                $"[V74.0.88][IME_DIALOG] get_status count={count} status={StatusName(status)}");
        }

        ctx[CpuRegister.Rax] = unchecked((ulong)(long)status);
        return status;
    }

    [SysAbiExport(
        Nid = "x01jxu+vxlc",
        ExportName = "sceImeDialogGetResult",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogGetResult(CpuContext ctx)
    {
        PumpCompletedOverlay(ctx);

        var resultAddress = ctx[CpuRegister.Rdi];
        if (resultAddress == 0)
        {
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        int endStatus;
        lock (Gate)
        {
            endStatus = _endStatus;
        }

        Span<byte> result = stackalloc byte[8];
        result.Clear();
        BinaryPrimitives.WriteInt32LittleEndian(result, endStatus);
        if (!ctx.Memory.TryWrite(resultAddress, result))
        {
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        var count = Interlocked.Increment(ref _resultCount);
        Console.Error.WriteLine(
            $"[V74.0.88][IME_DIALOG] get_result count={count} result=0x{resultAddress:X16} " +
            $"end_status={EndStatusName(endStatus)}");
        return SetReturn(ctx, 0);
    }

    [SysAbiExport(
        Nid = "oBmw4xrmfKs",
        ExportName = "sceImeDialogAbort",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogAbort(CpuContext ctx)
    {
        long generation;
        lock (Gate)
        {
            generation = _generation;
            ++_generation;
            _pendingText = null;
            _completionReady = false;
            _endStatus = EndStatusAborted;
            _status = StatusFinished;
        }

        ImeInWindowOverlay.Close(generation);
        Console.Error.WriteLine("[V74.0.88][IME_DIALOG] abort status=FINISHED end_status=ABORTED");
        return SetReturn(ctx, 0);
    }

    [SysAbiExport(
        Nid = "gyTyVn+bXMw",
        ExportName = "sceImeDialogTerm",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogTerm(CpuContext ctx)
    {
        long generation;
        lock (Gate)
        {
            generation = _generation;
            ++_generation;
            _pendingText = null;
            _completionReady = false;
            _inputBufferAddress = 0;
            _maxTextLength = 16;
            _endStatus = EndStatusOk;
            _status = StatusNone;
        }

        ImeInWindowOverlay.Close(generation);
        Console.Error.WriteLine("[V74.0.88][IME_DIALOG] term status=NONE");
        return SetReturn(ctx, 0);
    }

    private static void CompleteOverlay(long generation, string? text, int endStatus, string source)
    {
        lock (Gate)
        {
            if (generation != _generation || _status != StatusRunning)
            {
                return;
            }

            _pendingText = text;
            _endStatus = endStatus;
            _completionReady = true;
        }

        Console.Error.WriteLine(
            $"[V74.0.88][IME_DIALOG] overlay_complete generation={generation} source={source} " +
            $"end_status={EndStatusName(endStatus)} chars={text?.Length ?? 0}");
    }

    private static void PumpCompletedOverlay(CpuContext ctx)
    {
        if (ImeInWindowOverlay.TryTakeResult(out var overlayResult))
        {
            CompleteOverlay(
                overlayResult.Generation,
                overlayResult.Text,
                overlayResult.Canceled ? EndStatusCanceled : EndStatusOk,
                overlayResult.Canceled ? "in-window-cancel" : "in-window-done");
        }

        ulong bufferAddress;
        uint maxTextLength;
        string? text;
        int endStatus;
        lock (Gate)
        {
            if (_status != StatusRunning || !_completionReady)
            {
                return;
            }

            bufferAddress = _inputBufferAddress;
            maxTextLength = _maxTextLength;
            text = _pendingText;
            endStatus = _endStatus;
        }

        if (endStatus == EndStatusOk)
        {
            var safeText = Truncate(text ?? string.Empty, maxTextLength);
            if (!TryWriteUtf16Text(ctx, bufferAddress, maxTextLength, safeText))
            {
                Console.Error.WriteLine(
                    $"[V74.0.88][IME_DIALOG] text_commit_retry buffer=0x{bufferAddress:X16} " +
                    $"max={maxTextLength} chars={safeText.Length}");
                return;
            }

            Console.Error.WriteLine(
                $"[V74.0.88][IME_DIALOG] text_commit buffer=0x{bufferAddress:X16} max={maxTextLength} " +
                $"chars={safeText.Length} encoding=UTF16LE");
        }

        lock (Gate)
        {
            if (_status == StatusRunning && _completionReady)
            {
                _completionReady = false;
                _status = StatusFinished;
            }
        }
    }

    private static bool TryReadDialogParameter(
        CpuContext ctx,
        ulong parameterAddress,
        out ulong bufferAddress,
        out uint maxTextLength)
    {
        bufferAddress = 0;
        maxTextLength = 16;

        Span<byte> pointerField = stackalloc byte[8];
        if (!ctx.Memory.TryRead(parameterAddress + ParamInputTextBufferOffset, pointerField))
        {
            return false;
        }

        bufferAddress = BinaryPrimitives.ReadUInt64LittleEndian(pointerField);
        if (bufferAddress == 0)
        {
            return false;
        }

        Span<byte> maxField = stackalloc byte[4];
        if (ctx.Memory.TryRead(parameterAddress + ParamMaxTextLengthOffset, maxField))
        {
            var candidate = BinaryPrimitives.ReadUInt32LittleEndian(maxField);
            if (candidate is >= 1 and <= 512)
            {
                maxTextLength = candidate;
            }
        }

        return true;
    }

    private static string? TryReadUtf16Text(CpuContext ctx, ulong bufferAddress, uint maxTextLength)
    {
        var chars = new StringBuilder((int)Math.Min(maxTextLength, 128));
        Span<byte> codeUnit = stackalloc byte[2];
        for (uint index = 0; index < maxTextLength; index++)
        {
            if (!ctx.Memory.TryRead(bufferAddress + index * 2UL, codeUnit))
            {
                return chars.Length == 0 ? null : chars.ToString();
            }

            var value = BinaryPrimitives.ReadUInt16LittleEndian(codeUnit);
            if (value == 0)
            {
                break;
            }

            chars.Append((char)value);
        }

        return chars.ToString();
    }

    private static bool TryWriteUtf16Text(
        CpuContext ctx,
        ulong bufferAddress,
        uint maxTextLength,
        string text)
    {
        if (bufferAddress == 0)
        {
            return false;
        }

        text = Truncate(text, maxTextLength);
        var encoded = Encoding.Unicode.GetBytes(text);
        var payload = new byte[encoded.Length + 2];
        encoded.CopyTo(payload, 0);
        return ctx.Memory.TryWrite(bufferAddress, payload);
    }

    private static string Truncate(string text, uint maxTextLength)
    {
        var max = checked((int)Math.Min(maxTextLength, 512));
        return text.Length <= max ? text : text[..max];
    }

    private static string StatusName(int status) => status switch
    {
        StatusNone => "NONE",
        StatusRunning => "RUNNING",
        StatusFinished => "FINISHED",
        _ => status.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };

    private static string EndStatusName(int status) => status switch
    {
        EndStatusOk => "OK",
        EndStatusCanceled => "CANCELED",
        EndStatusAborted => "ABORTED",
        _ => status.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };

    private static int SetReturn(CpuContext ctx, int result)
    {
        ctx[CpuRegister.Rax] = unchecked((ulong)(long)result);
        return result;
    }
}
