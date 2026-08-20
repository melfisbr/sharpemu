// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Buffers.Binary;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Ime;

/// <summary>
/// libSceImeDialog compatibility with an asynchronous host text-entry panel.
///
/// V74.0.86.1 keeps the asynchronous IME lifecycle and replaces the hidden child-panel transport. It also replaces the old immediate "Sharp" autofill stub. sceImeDialogInit
/// now enters RUNNING, opens a real host text-entry panel on Windows, and only
/// reports FINISHED after the user presses OK/Cancel. The guest-owned UTF-16
/// input buffer is written from a live guest CpuContext while GetStatus/GetResult
/// polls, avoiding guest-memory writes from the host UI thread.
/// </summary>
public static class ImeDialogExports
{
    private const string V74086Marker = "SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY";

    private const int StatusNone = 0;
    private const int StatusRunning = 1;
    private const int StatusFinished = 2;

    private const int EndStatusOk = 0;
    private const int EndStatusCanceled = 1;
    private const int EndStatusAborted = 2;

    // Existing SharpEmu ABI layout for SceImeDialogParam used by Gen4/Gen5.
    private const ulong ParamMaxTextLengthOffset = 0x24;
    private const ulong ParamInputTextBufferOffset = 0x28;

    private const int ImeDialogErrorInvalidAddress = unchecked((int)0x80BC0001);

    private static readonly object _gate = new();
    private static int _status = StatusNone;
    private static int _endStatus = EndStatusOk;
    private static long _generation;
    private static ulong _inputBufferAddress;
    private static uint _maxTextLength = 16;
    private static bool _completionReady;
    private static string? _pendingText;
    private static Process? _hostPanelProcess;
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

        if (!TryReadDialogParameter(
                ctx,
                parameterAddress,
                out var bufferAddress,
                out var maxTextLength))
        {
            Console.Error.WriteLine(
                $"[V74.0.86.1][IME_DIALOG] init_failed param=0x{parameterAddress:X16} " +
                "reason=input-buffer-unreadable");
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        var initialText = TryReadUtf16Text(ctx, bufferAddress, maxTextLength) ?? string.Empty;
        long generation;
        lock (_gate)
        {
            TryStopHostPanelLocked();
            generation = ++_generation;
            _inputBufferAddress = bufferAddress;
            _maxTextLength = maxTextLength;
            _pendingText = null;
            _completionReady = false;
            _endStatus = EndStatusOk;
            _status = StatusRunning;
        }

        var count = System.Threading.Interlocked.Increment(ref _initCount);
        Console.Error.WriteLine(
            $"[V74.0.86.1][IME_DIALOG] init count={count} generation={generation} " +
            $"param=0x{parameterAddress:X16} buffer=0x{bufferAddress:X16} " +
            $"max={maxTextLength} initial_chars={initialText.Length} status=RUNNING");

        StartHostPanel(generation, initialText, maxTextLength);
        return SetReturn(ctx, 0);
    }

    [SysAbiExport(
        Nid = "IADmD4tScBY",
        ExportName = "sceImeDialogGetStatus",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogGetStatus(CpuContext ctx)
    {
        PumpCompletedHostPanel(ctx);

        int status;
        lock (_gate)
        {
            status = _status;
        }

        var count = System.Threading.Interlocked.Increment(ref _statusCount);
        if (count <= 8 || (count & (count - 1)) == 0 || status == StatusFinished)
        {
            Console.Error.WriteLine(
                $"[V74.0.86.1][IME_DIALOG] get_status count={count} status={StatusName(status)}");
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
        PumpCompletedHostPanel(ctx);

        var resultAddress = ctx[CpuRegister.Rdi];
        if (resultAddress == 0)
        {
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        int endStatus;
        lock (_gate)
        {
            endStatus = _endStatus;
        }

        Span<byte> result = stackalloc byte[8];
        result.Clear();
        BinaryPrimitives.WriteInt32LittleEndian(result, endStatus);
        if (!ctx.Memory.TryWrite(resultAddress, result))
        {
            Console.Error.WriteLine(
                $"[V74.0.86.1][IME_DIALOG] get_result_failed result=0x{resultAddress:X16}");
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        var count = System.Threading.Interlocked.Increment(ref _resultCount);
        Console.Error.WriteLine(
            $"[V74.0.86.1][IME_DIALOG] get_result count={count} result=0x{resultAddress:X16} " +
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
        lock (_gate)
        {
            ++_generation;
            TryStopHostPanelLocked();
            _pendingText = null;
            _completionReady = false;
            _endStatus = EndStatusAborted;
            _status = StatusFinished;
        }

        Console.Error.WriteLine("[V74.0.86.1][IME_DIALOG] abort status=FINISHED end_status=ABORTED");
        return SetReturn(ctx, 0);
    }

    [SysAbiExport(
        Nid = "gyTyVn+bXMw",
        ExportName = "sceImeDialogTerm",
        Target = Generation.Gen4 | Generation.Gen5,
        LibraryName = "libSceImeDialog")]
    public static int ImeDialogTerm(CpuContext ctx)
    {
        lock (_gate)
        {
            ++_generation;
            TryStopHostPanelLocked();
            _pendingText = null;
            _completionReady = false;
            _inputBufferAddress = 0;
            _maxTextLength = 16;
            _endStatus = EndStatusOk;
            _status = StatusNone;
        }

        Console.Error.WriteLine("[V74.0.86.1][IME_DIALOG] term status=NONE");
        return SetReturn(ctx, 0);
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

        Span<byte> lengthField = stackalloc byte[4];
        if (ctx.Memory.TryRead(parameterAddress + ParamMaxTextLengthOffset, lengthField))
        {
            var declared = BinaryPrimitives.ReadUInt32LittleEndian(lengthField);
            if (declared is > 0 and <= 512)
            {
                maxTextLength = declared;
            }
        }

        return true;
    }

    private static string? TryReadUtf16Text(
        CpuContext ctx,
        ulong bufferAddress,
        uint maxTextLength)
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

    private static void StartHostPanel(long generation, string initialText, uint maxTextLength)
    {
        var forcedText = Environment.GetEnvironmentVariable("SHARPEMU_IME_TEXT");
        if (!string.IsNullOrEmpty(forcedText))
        {
            CompleteHostPanel(
                generation,
                Truncate(forcedText, maxTextLength),
                EndStatusOk,
                "environment");
            return;
        }

        var enabled = Environment.GetEnvironmentVariable("SHARPEMU_IME_HOST_PANEL");
        if (string.Equals(enabled, "0", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(enabled, "false", StringComparison.OrdinalIgnoreCase))
        {
            CompleteHostPanel(generation, initialText, EndStatusCanceled, "panel-disabled");
            return;
        }

        _ = Task.Run(() =>
        {
            try
            {
                if (!OperatingSystem.IsWindows())
                {
                    CompleteHostPanel(generation, initialText, EndStatusCanceled, "non-windows");
                    return;
                }

                Console.Error.WriteLine(
                    $"[V74.0.86.1][IME_DIALOG] host_panel_open generation={generation} " +
                    $"max={maxTextLength} backend=windows-powershell-winforms");

                var result = RunWindowsHostPanel(generation, initialText, maxTextLength);
                CompleteHostPanel(generation, result.Text, result.EndStatus, result.Source);
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(
                    $"[V74.0.86.1][IME_DIALOG] host_panel_error generation={generation} " +
                    $"type={exception.GetType().Name} message='{exception.Message}'");
                CompleteHostPanel(generation, initialText, EndStatusCanceled, "host-error");
            }
        });
    }

    private static HostPanelResult RunWindowsHostPanel(
        long generation,
        string initialText,
        uint maxTextLength)
    {
        // SHARPEMU_V74_0_86_1_IME_OSK_RESULT_FILE
        // V85.1 launched a hidden/non-interactive PowerShell process and tried to
        // read the answer from redirected stdout. The guest correctly entered
        // RUNNING, but on the tested Windows 10 machine the WinForms dialog never
        // became visible and the guest remained in RUNNING indefinitely.
        //
        // V86 deliberately gives the child a normal visible window and exchanges
        // the result through a private temp file. This avoids stdout pipe/window
        // interaction while keeping all guest-memory writes on the guest thread.
        var resultPath = Path.Combine(
            Path.GetTempPath(),
            $"SharpEmuIme_{Environment.ProcessId}_{generation}_{Guid.NewGuid():N}.result");
        // SHARPEMU_V74_0_86_1_6_IME_OSK_BASE64_PAYLOAD
        // Keep the WinForms/PS-style OSK script out of a C# verbatim string.
        // PowerShell -EncodedCommand consumes UTF-16LE Base64, so this also
        // removes every C#/PowerShell quote-escaping ambiguity.
        const string encodedScript = "JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAUwB0AG8AcAAnAAoAQQBkAGQALQBUAHkAcABlACAALQBBAHMAcwBlAG0AYgBsAHkATgBhAG0AZQAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAKAEEAZABkAC0AVAB5AHAAZQAgAC0AQQBzAHMAZQBtAGIAbAB5AE4AYQBtAGUAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcACgBbAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEEAcABwAGwAaQBjAGEAdABpAG8AbgBdADoAOgBFAG4AYQBiAGwAZQBWAGkAcwB1AGEAbABTAHQAeQBsAGUAcwAoACkACgAkAHIAZQBzAHUAbAB0AFAAYQB0AGgAIAA9ACAAJABlAG4AdgA6AFMASABBAFIAUABFAE0AVQBfAEkATQBFAF8AUgBFAFMAVQBMAFQAXwBQAEEAVABIAAoAZgB1AG4AYwB0AGkAbwBuACAAVwByAGkAdABlAC0AUwBoAGEAcgBwAEUAbQB1AEkAbQBlAFIAZQBzAHUAbAB0ACgAWwBzAHQAcgBpAG4AZwBdACQAdgBhAGwAdQBlACkAIAB7AAoAIAAgACAAIABbAEkATwAuAEYAaQBsAGUAXQA6ADoAVwByAGkAdABlAEEAbABsAFQAZQB4AHQAKAAkAHIAZQBzAHUAbAB0AFAAYQB0AGgALAAgACQAdgBhAGwAdQBlACwAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABUAGUAeAB0AC4AVQBUAEYAOABFAG4AYwBvAGQAaQBuAGcAKAAkAGYAYQBsAHMAZQApACkAKQAKAH0ACgAkAGYAbwByAG0AIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEYAbwByAG0ACgAkAGYAbwByAG0ALgBUAGUAeAB0ACAAPQAgACcAUwBoAGEAcgBwAEUAbQB1ACAALQAgAFQAZQB4AHQAIABJAG4AcAB1AHQAJwAKACQAZgBvAHIAbQAuAFMAdABhAHIAdABQAG8AcwBpAHQAaQBvAG4AIAA9ACAAJwBDAGUAbgB0AGUAcgBTAGMAcgBlAGUAbgAnAAoAJABmAG8AcgBtAC4ARgBvAHIAbQBCAG8AcgBkAGUAcgBTAHQAeQBsAGUAIAA9ACAAJwBGAGkAeABlAGQARABpAGEAbABvAGcAJwAKACQAZgBvAHIAbQAuAE0AYQB4AGkAbQBpAHoAZQBCAG8AeAAgAD0AIAAkAGYAYQBsAHMAZQAKACQAZgBvAHIAbQAuAE0AaQBuAGkAbQBpAHoAZQBCAG8AeAAgAD0AIAAkAGYAYQBsAHMAZQAKACQAZgBvAHIAbQAuAFMAaABvAHcASQBjAG8AbgAgAD0AIAAkAGYAYQBsAHMAZQAKACQAZgBvAHIAbQAuAFMAaABvAHcASQBuAFQAYQBzAGsAYgBhAHIAIAA9ACAAJAB0AHIAdQBlAAoAJABmAG8AcgBtAC4AVABvAHAATQBvAHMAdAAgAD0AIAAkAHQAcgB1AGUACgAkAGYAbwByAG0ALgBCAGEAYwBrAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBGAHIAbwBtAEEAcgBnAGIAKAAxADgALAAyADIALAAzADAAKQAKACQAZgBvAHIAbQAuAEYAbwByAGUAQwBvAGwAbwByACAAPQAgAFsAUwB5AHMAdABlAG0ALgBEAHIAYQB3AGkAbgBnAC4AQwBvAGwAbwByAF0AOgA6AFcAaABpAHQAZQBTAG0AbwBrAGUACgAkAGYAbwByAG0ALgBDAGwAaQBlAG4AdABTAGkAegBlACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBTAGkAegBlACgAOQA4ADAALAAgADUANAAwACkACgAKACQAdABpAHQAbABlACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFcAaQBuAGQAbwB3AHMALgBGAG8AcgBtAHMALgBMAGEAYgBlAGwACgAkAHQAaQB0AGwAZQAuAEwAZQBmAHQAIAA9ACAAMgA4AAoAJAB0AGkAdABsAGUALgBUAG8AcAAgAD0AIAAxADgACgAkAHQAaQB0AGwAZQAuAFcAaQBkAHQAaAAgAD0AIAA5ADAAMAAKACQAdABpAHQAbABlAC4ASABlAGkAZwBoAHQAIAA9ACAAMgA4AAoAJAB0AGkAdABsAGUALgBGAG8AbgB0ACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBGAG8AbgB0ACgAJwBTAGUAZwBvAGUAIABVAEkAJwAsACAAMQA0ACwAIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEYAbwBuAHQAUwB0AHkAbABlAF0AOgA6AEIAbwBsAGQAKQAKACQAdABpAHQAbABlAC4AVABlAHgAdAAgAD0AIAAnAEUAbgB0AGUAcgAgAHkAbwB1AHIAIABwAGwAYQB5AGUAcgAnACcAcwAgAG4AYQBtAGUAJwAKAAoAJAB0AGUAeAB0ACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFcAaQBuAGQAbwB3AHMALgBGAG8AcgBtAHMALgBUAGUAeAB0AEIAbwB4AAoAJAB0AGUAeAB0AC4ATABlAGYAdAAgAD0AIAAyADgACgAkAHQAZQB4AHQALgBUAG8AcAAgAD0AIAA1ADgACgAkAHQAZQB4AHQALgBXAGkAZAB0AGgAIAA9ACAAOQAwADAACgAkAHQAZQB4AHQALgBIAGUAaQBnAGgAdAAgAD0AIAAzADQACgAkAHQAZQB4AHQALgBGAG8AbgB0ACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBGAG8AbgB0ACgAJwBTAGUAZwBvAGUAIABVAEkAJwAsACAAMQA2ACkACgAkAHQAZQB4AHQALgBNAGEAeABMAGUAbgBnAHQAaAAgAD0AIABbAE0AYQB0AGgAXQA6ADoATQBhAHgAKAAxACwAIABbAGkAbgB0AF0AJABlAG4AdgA6AFMASABBAFIAUABFAE0AVQBfAEkATQBFAF8ATQBBAFgAKQAKAGkAZgAgACgALQBuAG8AdAAgAFsAcwB0AHIAaQBuAGcAXQA6ADoASQBzAE4AdQBsAGwATwByAEUAbQBwAHQAeQAoACQAZQBuAHYAOgBTAEgAQQBSAFAARQBNAFUAXwBJAE0ARQBfAEkATgBJAFQASQBBAEwAXwBCADYANAApACkAIAB7AAoAIAAgACAAIAAkAHQAZQB4AHQALgBUAGUAeAB0ACAAPQAgAFsAVABlAHgAdAAuAEUAbgBjAG8AZABpAG4AZwBdADoAOgBVAG4AaQBjAG8AZABlAC4ARwBlAHQAUwB0AHIAaQBuAGcAKABbAEMAbwBuAHYAZQByAHQAXQA6ADoARgByAG8AbQBCAGEAcwBlADYANABTAHQAcgBpAG4AZwAoACQAZQBuAHYAOgBTAEgAQQBSAFAARQBNAFUAXwBJAE0ARQBfAEkATgBJAFQASQBBAEwAXwBCADYANAApACkACgB9AAoACgAkAGkAbgBmAG8AIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEwAYQBiAGUAbAAKACQAaQBuAGYAbwAuAEwAZQBmAHQAIAA9ACAAMgA4AAoAJABpAG4AZgBvAC4AVABvAHAAIAA9ACAAMQAwADAACgAkAGkAbgBmAG8ALgBXAGkAZAB0AGgAIAA9ACAANQAyADAACgAkAGkAbgBmAG8ALgBIAGUAaQBnAGgAdAAgAD0AIAAyADIACgAkAGkAbgBmAG8ALgBUAGUAeAB0ACAAPQAgACcASwBlAHkAYgBvAGEAcgBkACAALwAgAG0AbwB1AHMAZQAgAGYAcgBpAGUAbgBkAGwAeQAgAG8AdgBlAHIAbABhAHkAIABzAHQAeQBsAGUAZAAgAGMAbABvAHMAZQByACAAdABvACAAdABoAGUAIABQAFMANQAgAG8AbgAtAHMAYwByAGUAZQBuACAAawBlAHkAYgBvAGEAcgBkAC4AJwAKAAoAJABwAGEAbgBlAGwAIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAFAAYQBuAGUAbAAKACQAcABhAG4AZQBsAC4ATABlAGYAdAAgAD0AIAAyADgACgAkAHAAYQBuAGUAbAAuAFQAbwBwACAAPQAgADEAMwA2AAoAJABwAGEAbgBlAGwALgBXAGkAZAB0AGgAIAA9ACAAOQAwADAACgAkAHAAYQBuAGUAbAAuAEgAZQBpAGcAaAB0ACAAPQAgADIAOAAwAAoAJABwAGEAbgBlAGwALgBCAGEAYwBrAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBGAHIAbwBtAEEAcgBnAGIAKAAyADgALAAzADIALAA0ADMAKQAKAAoAJABrAGUAeQBzACAAPQAgAEAAKAAKACAAIAAgACAAJwAxACcALAAnADIAJwAsACcAMwAnACwAJwA0ACcALAAnADUAJwAsACcANgAnACwAJwA3ACcALAAnADgAJwAsACcAOQAnACwAJwAwACcALAAnAEAAJwAsAAoAIAAgACAAIAAnAHEAJwAsACcAdwAnACwAJwBlACcALAAnAHIAJwAsACcAdAAnACwAJwB5ACcALAAnAHUAJwAsACcAaQAnACwAJwBvACcALAAnAHAAJwAsACcAIwAnACwACgAgACAAIAAgACcAYQAnACwAJwBzACcALAAnAGQAJwAsACcAZgAnACwAJwBnACcALAAnAGgAJwAsACcAagAnACwAJwBrACcALAAnAGwAJwAsACIAJwAiACwAJwAvACcALAAKACAAIAAgACAAJwB6ACcALAAnAHgAJwAsACcAYwAnACwAJwB2ACcALAAnAGIAJwAsACcAbgAnACwAJwBtACcALAAnACwAJwAsACcALgAnACwAJwA/ACcALAAnACEAJwAKACkACgAkAHMAdABhAHIAdABYACAAPQAgADEAOAAKACQAcwB0AGEAcgB0AFkAIAA9ACAAMQA4AAoAJABrAGUAeQBXACAAPQAgADYAOAAKACQAawBlAHkASAAgAD0AIAA1ADAACgAkAGcAYQBwACAAPQAgADEAMAAKAGYAbwByACAAKAAkAGkAIAA9ACAAMAA7ACAAJABpACAALQBsAHQAIAAkAGsAZQB5AHMALgBDAG8AdQBuAHQAOwAgACQAaQArACsAKQAgAHsACgAgACAAIAAgACQAYgB0AG4AIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEIAdQB0AHQAbwBuAAoAIAAgACAAIAAkAGIAdABuAC4AVwBpAGQAdABoACAAPQAgACQAawBlAHkAVwAKACAAIAAgACAAJABiAHQAbgAuAEgAZQBpAGcAaAB0ACAAPQAgACQAawBlAHkASAAKACAAIAAgACAAJAByAG8AdwAgAD0AIABbAE0AYQB0AGgAXQA6ADoARgBsAG8AbwByACgAJABpACAALwAgADEAMQApAAoAIAAgACAAIAAkAGMAbwBsACAAPQAgACQAaQAgACUAIAAxADEACgAgACAAIAAgACQAYgB0AG4ALgBMAGUAZgB0ACAAPQAgACQAcwB0AGEAcgB0AFgAIAArACAAKAAkAGMAbwBsACAAKgAgACgAJABrAGUAeQBXACAAKwAgACQAZwBhAHAAKQApAAoAIAAgACAAIAAkAGIAdABuAC4AVABvAHAAIAA9ACAAJABzAHQAYQByAHQAWQAgACsAIAAoACQAcgBvAHcAIAAqACAAKAAkAGsAZQB5AEgAIAArACAAJABnAGEAcAApACkACgAgACAAIAAgACQAYgB0AG4ALgBUAGUAeAB0ACAAPQAgACQAawBlAHkAcwBbACQAaQBdAAoAIAAgACAAIAAkAGIAdABuAC4ARgBvAG4AdAAgAD0AIABOAGUAdwAtAE8AYgBqAGUAYwB0ACAAUwB5AHMAdABlAG0ALgBEAHIAYQB3AGkAbgBnAC4ARgBvAG4AdAAoACcAUwBlAGcAbwBlACAAVQBJACcALAAgADEAMwApAAoAIAAgACAAIAAkAGIAdABuAC4AQgBhAGMAawBDAG8AbABvAHIAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBDAG8AbABvAHIAXQA6ADoARgByAG8AbQBBAHIAZwBiACgANAA0ACwANAA5ACwANgAzACkACgAgACAAIAAgACQAYgB0AG4ALgBGAG8AcgBlAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBXAGgAaQB0AGUAUwBtAG8AawBlAAoAIAAgACAAIAAkAGIAdABuAC4ARgBsAGEAdABTAHQAeQBsAGUAIAA9ACAAJwBGAGwAYQB0ACcACgAgACAAIAAgACQAYgB0AG4ALgBBAGQAZABfAEMAbABpAGMAawAoAHsAIAAkAHQAZQB4AHQALgBTAGUAbABlAGMAdABlAGQAVABlAHgAdAAgAD0AIAAkAHQAaABpAHMALgBUAGUAeAB0ADsAIAAkAHQAZQB4AHQALgBGAG8AYwB1AHMAKAApACAAfQApAAoAIAAgACAAIAAkAHAAYQBuAGUAbAAuAEMAbwBuAHQAcgBvAGwAcwAuAEEAZABkACgAJABiAHQAbgApAAoAfQAKAAoAJABzAHAAYQBjAGUAIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEIAdQB0AHQAbwBuAAoAJABzAHAAYQBjAGUALgBMAGUAZgB0ACAAPQAgADEAOAAKACQAcwBwAGEAYwBlAC4AVABvAHAAIAA9ACAAMgA0ADAACgAkAHMAcABhAGMAZQAuAFcAaQBkAHQAaAAgAD0AIAAyADUAMAAKACQAcwBwAGEAYwBlAC4ASABlAGkAZwBoAHQAIAA9ACAAMgA4AAoAJABzAHAAYQBjAGUALgBUAGUAeAB0ACAAPQAgACcAUwBwAGEAYwBlACcACgAkAHMAcABhAGMAZQAuAEIAYQBjAGsAQwBvAGwAbwByACAAPQAgAFsAUwB5AHMAdABlAG0ALgBEAHIAYQB3AGkAbgBnAC4AQwBvAGwAbwByAF0AOgA6AEYAcgBvAG0AQQByAGcAYgAoADQANAAsADQAOQAsADYAMwApAAoAJABzAHAAYQBjAGUALgBGAG8AcgBlAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBXAGgAaQB0AGUAUwBtAG8AawBlAAoAJABzAHAAYQBjAGUALgBGAGwAYQB0AFMAdAB5AGwAZQAgAD0AIAAnAEYAbABhAHQAJwAKACQAcwBwAGEAYwBlAC4AQQBkAGQAXwBDAGwAaQBjAGsAKAB7ACAAJAB0AGUAeAB0AC4AUwBlAGwAZQBjAHQAZQBkAFQAZQB4AHQAIAA9ACAAJwAgACcAOwAgACQAdABlAHgAdAAuAEYAbwBjAHUAcwAoACkAIAB9ACkACgAkAHAAYQBuAGUAbAAuAEMAbwBuAHQAcgBvAGwAcwAuAEEAZABkACgAJABzAHAAYQBjAGUAKQAKAAoAJABiAGEAYwBrACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFcAaQBuAGQAbwB3AHMALgBGAG8AcgBtAHMALgBCAHUAdAB0AG8AbgAKACQAYgBhAGMAawAuAEwAZQBmAHQAIAA9ACAAMgA4ADIACgAkAGIAYQBjAGsALgBUAG8AcAAgAD0AIAAyADQAMAAKACQAYgBhAGMAawAuAFcAaQBkAHQAaAAgAD0AIAAxADcAMAAKACQAYgBhAGMAawAuAEgAZQBpAGcAaAB0ACAAPQAgADIAOAAKACQAYgBhAGMAawAuAFQAZQB4AHQAIAA9ACAAJwBCAGEAYwBrAHMAcABhAGMAZQAnAAoAJABiAGEAYwBrAC4AQgBhAGMAawBDAG8AbABvAHIAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBDAG8AbABvAHIAXQA6ADoARgByAG8AbQBBAHIAZwBiACgANAA0ACwANAA5ACwANgAzACkACgAkAGIAYQBjAGsALgBGAG8AcgBlAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBXAGgAaQB0AGUAUwBtAG8AawBlAAoAJABiAGEAYwBrAC4ARgBsAGEAdABTAHQAeQBsAGUAIAA9ACAAJwBGAGwAYQB0ACcACgAkAGIAYQBjAGsALgBBAGQAZABfAEMAbABpAGMAawAoAHsAIABpAGYAIAAoACQAdABlAHgAdAAuAFMAZQBsAGUAYwB0AGkAbwBuAEwAZQBuAGcAdABoACAALQBnAHQAIAAwACkAIAB7ACAAJABzAHQAYQByAHQAIAA9ACAAJAB0AGUAeAB0AC4AUwBlAGwAZQBjAHQAaQBvAG4AUwB0AGEAcgB0ADsAIAAkAHQAZQB4AHQALgBUAGUAeAB0ACAAPQAgACQAdABlAHgAdAAuAFQAZQB4AHQALgBSAGUAbQBvAHYAZQAoACQAcwB0AGEAcgB0ACwAIAAkAHQAZQB4AHQALgBTAGUAbABlAGMAdABpAG8AbgBMAGUAbgBnAHQAaAApADsAIAAkAHQAZQB4AHQALgBTAGUAbABlAGMAdABpAG8AbgBTAHQAYQByAHQAIAA9ACAAJABzAHQAYQByAHQAIAB9ACAAZQBsAHMAZQBpAGYAIAAoACQAdABlAHgAdAAuAFMAZQBsAGUAYwB0AGkAbwBuAFMAdABhAHIAdAAgAC0AZwB0ACAAMAApACAAewAgACQAcwB0AGEAcgB0ACAAPQAgACQAdABlAHgAdAAuAFMAZQBsAGUAYwB0AGkAbwBuAFMAdABhAHIAdAA7ACAAJAB0AGUAeAB0AC4AVABlAHgAdAAgAD0AIAAkAHQAZQB4AHQALgBUAGUAeAB0AC4AUgBlAG0AbwB2AGUAKAAkAHMAdABhAHIAdAAgAC0AIAAxACwAIAAxACkAOwAgACQAdABlAHgAdAAuAFMAZQBsAGUAYwB0AGkAbwBuAFMAdABhAHIAdAAgAD0AIAAkAHMAdABhAHIAdAAgAC0AIAAxACAAfQA7ACAAJAB0AGUAeAB0AC4ARgBvAGMAdQBzACgAKQAgAH0AKQAKACQAcABhAG4AZQBsAC4AQwBvAG4AdAByAG8AbABzAC4AQQBkAGQAKAAkAGIAYQBjAGsAKQAKAAoAJABjAGwAZQBhAHIAIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEIAdQB0AHQAbwBuAAoAJABjAGwAZQBhAHIALgBMAGUAZgB0ACAAPQAgADQANgA2AAoAJABjAGwAZQBhAHIALgBUAG8AcAAgAD0AIAAyADQAMAAKACQAYwBsAGUAYQByAC4AVwBpAGQAdABoACAAPQAgADEAMgAwAAoAJABjAGwAZQBhAHIALgBIAGUAaQBnAGgAdAAgAD0AIAAyADgACgAkAGMAbABlAGEAcgAuAFQAZQB4AHQAIAA9ACAAJwBDAGwAZQBhAHIAJwAKACQAYwBsAGUAYQByAC4AQgBhAGMAawBDAG8AbABvAHIAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBDAG8AbABvAHIAXQA6ADoARgByAG8AbQBBAHIAZwBiACgANAA0ACwANAA5ACwANgAzACkACgAkAGMAbABlAGEAcgAuAEYAbwByAGUAQwBvAGwAbwByACAAPQAgAFsAUwB5AHMAdABlAG0ALgBEAHIAYQB3AGkAbgBnAC4AQwBvAGwAbwByAF0AOgA6AFcAaABpAHQAZQBTAG0AbwBrAGUACgAkAGMAbABlAGEAcgAuAEYAbABhAHQAUwB0AHkAbABlACAAPQAgACcARgBsAGEAdAAnAAoAJABjAGwAZQBhAHIALgBBAGQAZABfAEMAbABpAGMAawAoAHsAIAAkAHQAZQB4AHQALgBDAGwAZQBhAHIAKAApADsAIAAkAHQAZQB4AHQALgBGAG8AYwB1AHMAKAApACAAfQApAAoAJABwAGEAbgBlAGwALgBDAG8AbgB0AHIAbwBsAHMALgBBAGQAZAAoACQAYwBsAGUAYQByACkACgAKACQAYQBiAGMAIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEwAYQBiAGUAbAAKACQAYQBiAGMALgBMAGUAZgB0ACAAPQAgADYAMAA2AAoAJABhAGIAYwAuAFQAbwBwACAAPQAgADIANAA0AAoAJABhAGIAYwAuAFcAaQBkAHQAaAAgAD0AIAAyADYAMAAKACQAYQBiAGMALgBIAGUAaQBnAGgAdAAgAD0AIAAyADIACgAkAGEAYgBjAC4AVABlAHgAdAAgAD0AIAAnAEEAQgBDACAAIAAgACAAQAAjADoAIAAgACAAIABMADEALwBSADEAIAAgAHMAaQBtAHUAbABhAHQAZQBkACAAbABhAHkAbwB1AHQAIABnAHIAbwB1AHAAcwAnAAoAJABwAGEAbgBlAGwALgBDAG8AbgB0AHIAbwBsAHMALgBBAGQAZAAoACQAYQBiAGMAKQAKAAoAJABkAG8AbgBlACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFcAaQBuAGQAbwB3AHMALgBGAG8AcgBtAHMALgBCAHUAdAB0AG8AbgAKACQAZABvAG4AZQAuAFQAZQB4AHQAIAA9ACAAJwBEAG8AbgBlACcACgAkAGQAbwBuAGUALgBMAGUAZgB0ACAAPQAgADcANAA2AAoAJABkAG8AbgBlAC4AVABvAHAAIAA9ACAANAA0ADAACgAkAGQAbwBuAGUALgBXAGkAZAB0AGgAIAA9ACAAMQA4ADIACgAkAGQAbwBuAGUALgBIAGUAaQBnAGgAdAAgAD0AIAA0ADgACgAkAGQAbwBuAGUALgBGAG8AbgB0ACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBGAG8AbgB0ACgAJwBTAGUAZwBvAGUAIABVAEkAJwAsACAAMQA0ACwAIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEYAbwBuAHQAUwB0AHkAbABlAF0AOgA6AEIAbwBsAGQAKQAKACQAZABvAG4AZQAuAEIAYQBjAGsAQwBvAGwAbwByACAAPQAgAFsAUwB5AHMAdABlAG0ALgBEAHIAYQB3AGkAbgBnAC4AQwBvAGwAbwByAF0AOgA6AEYAcgBvAG0AQQByAGcAYgAoADYAOAAsADgAMgAsADEAMQAwACkACgAkAGQAbwBuAGUALgBGAG8AcgBlAEMAbwBsAG8AcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ARAByAGEAdwBpAG4AZwAuAEMAbwBsAG8AcgBdADoAOgBXAGgAaQB0AGUAUwBtAG8AawBlAAoAJABkAG8AbgBlAC4ARABpAGEAbABvAGcAUgBlAHMAdQBsAHQAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAFcAaQBuAGQAbwB3AHMALgBGAG8AcgBtAHMALgBEAGkAYQBsAG8AZwBSAGUAcwB1AGwAdABdADoAOgBPAEsACgAKACQAYwBhAG4AYwBlAGwAIAA9ACAATgBlAHcALQBPAGIAagBlAGMAdAAgAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEIAdQB0AHQAbwBuAAoAJABjAGEAbgBjAGUAbAAuAFQAZQB4AHQAIAA9ACAAJwBDAGEAbgBjAGUAbAAnAAoAJABjAGEAbgBjAGUAbAAuAEwAZQBmAHQAIAA9ACAANQA0ADYACgAkAGMAYQBuAGMAZQBsAC4AVABvAHAAIAA9ACAANAA0ADAACgAkAGMAYQBuAGMAZQBsAC4AVwBpAGQAdABoACAAPQAgADEAOAAyAAoAJABjAGEAbgBjAGUAbAAuAEgAZQBpAGcAaAB0ACAAPQAgADQAOAAKACQAYwBhAG4AYwBlAGwALgBGAG8AbgB0ACAAPQAgAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBGAG8AbgB0ACgAJwBTAGUAZwBvAGUAIABVAEkAJwAsACAAMQAyACkACgAkAGMAYQBuAGMAZQBsAC4AQgBhAGMAawBDAG8AbABvAHIAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBDAG8AbABvAHIAXQA6ADoARgByAG8AbQBBAHIAZwBiACgANAA0ACwANAA5ACwANgAzACkACgAkAGMAYQBuAGMAZQBsAC4ARgBvAHIAZQBDAG8AbABvAHIAIAA9ACAAWwBTAHkAcwB0AGUAbQAuAEQAcgBhAHcAaQBuAGcALgBDAG8AbABvAHIAXQA6ADoAVwBoAGkAdABlAFMAbQBvAGsAZQAKACQAYwBhAG4AYwBlAGwALgBEAGkAYQBsAG8AZwBSAGUAcwB1AGwAdAAgAD0AIABbAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEQAaQBhAGwAbwBnAFIAZQBzAHUAbAB0AF0AOgA6AEMAYQBuAGMAZQBsAAoACgAkAGgAaQBuAHQAcwAgAD0AIABOAGUAdwAtAE8AYgBqAGUAYwB0ACAAUwB5AHMAdABlAG0ALgBXAGkAbgBkAG8AdwBzAC4ARgBvAHIAbQBzAC4ATABhAGIAZQBsAAoAJABoAGkAbgB0AHMALgBMAGUAZgB0ACAAPQAgADIAOAAKACQAaABpAG4AdABzAC4AVABvAHAAIAA9ACAANAA0ADgACgAkAGgAaQBuAHQAcwAuAFcAaQBkAHQAaAAgAD0AIAA0ADcAMAAKACQAaABpAG4AdABzAC4ASABlAGkAZwBoAHQAIAA9ACAAMwA4AAoAJABoAGkAbgB0AHMALgBUAGUAeAB0ACAAPQAgACcARQBuAHQAZQByACAAYwBvAG4AZgBpAHIAbQBzACAAIiAgAEUAUwBDACAAYwBhAG4AYwBlAGwAcwAgACIgIABtAG8AdQBzAGUAIABjAGEAbgAgAGMAbABpAGMAawAgAGsAZQB5AHMAIAAiICAAdAB5AHAAZQBkACAAawBlAHkAYgBvAGEAcgBkACAAaQBuAHAAdQB0ACAAYQBsAHMAbwAgAHcAbwByAGsAcwAnAAoACgAkAGYAbwByAG0ALgBBAGMAYwBlAHAAdABCAHUAdAB0AG8AbgAgAD0AIAAkAGQAbwBuAGUACgAkAGYAbwByAG0ALgBDAGEAbgBjAGUAbABCAHUAdAB0AG8AbgAgAD0AIAAkAGMAYQBuAGMAZQBsAAoAJABmAG8AcgBtAC4AQwBvAG4AdAByAG8AbABzAC4AQQBkAGQAKAAkAHQAaQB0AGwAZQApAAoAJABmAG8AcgBtAC4AQwBvAG4AdAByAG8AbABzAC4AQQBkAGQAKAAkAHQAZQB4AHQAKQAKACQAZgBvAHIAbQAuAEMAbwBuAHQAcgBvAGwAcwAuAEEAZABkACgAJABpAG4AZgBvACkACgAkAGYAbwByAG0ALgBDAG8AbgB0AHIAbwBsAHMALgBBAGQAZAAoACQAcABhAG4AZQBsACkACgAkAGYAbwByAG0ALgBDAG8AbgB0AHIAbwBsAHMALgBBAGQAZAAoACQAaABpAG4AdABzACkACgAkAGYAbwByAG0ALgBDAG8AbgB0AHIAbwBsAHMALgBBAGQAZAAoACQAZABvAG4AZQApAAoAJABmAG8AcgBtAC4AQwBvAG4AdAByAG8AbABzAC4AQQBkAGQAKAAkAGMAYQBuAGMAZQBsACkACgAkAGYAbwByAG0ALgBBAGQAZABfAFMAaABvAHcAbgAoAHsACgAgACAAIAAgACQAZgBvAHIAbQAuAFcAaQBuAGQAbwB3AFMAdABhAHQAZQAgAD0AIABbAFMAeQBzAHQAZQBtAC4AVwBpAG4AZABvAHcAcwAuAEYAbwByAG0AcwAuAEYAbwByAG0AVwBpAG4AZABvAHcAUwB0AGEAdABlAF0AOgA6AE4AbwByAG0AYQBsAAoAIAAgACAAIAAkAGYAbwByAG0ALgBUAG8AcABNAG8AcwB0ACAAPQAgACQAdAByAHUAZQAKACAAIAAgACAAJABmAG8AcgBtAC4AQgByAGkAbgBnAFQAbwBGAHIAbwBuAHQAKAApAAoAIAAgACAAIAAkAGYAbwByAG0ALgBBAGMAdABpAHYAYQB0AGUAKAApAAoAIAAgACAAIAAkAHQAZQB4AHQALgBGAG8AYwB1AHMAKAApAAoAIAAgACAAIAAkAHQAZQB4AHQALgBTAGUAbABlAGMAdAAoACQAdABlAHgAdAAuAFQAZQB4AHQALgBMAGUAbgBnAHQAaAAsADAAKQAKAH0AKQAKACQAcgBlAHMAdQBsAHQAIAA9ACAAJABmAG8AcgBtAC4AUwBoAG8AdwBEAGkAYQBsAG8AZwAoACkACgBpAGYAIAAoACQAcgBlAHMAdQBsAHQAIAAtAGUAcQAgAFsAUwB5AHMAdABlAG0ALgBXAGkAbgBkAG8AdwBzAC4ARgBvAHIAbQBzAC4ARABpAGEAbABvAGcAUgBlAHMAdQBsAHQAXQA6ADoATwBLACkAIAB7AAoAIAAgACAAIAAkAGIAeQB0AGUAcwAgAD0AIABbAFQAZQB4AHQALgBFAG4AYwBvAGQAaQBuAGcAXQA6ADoAVQBuAGkAYwBvAGQAZQAuAEcAZQB0AEIAeQB0AGUAcwAoACQAdABlAHgAdAAuAFQAZQB4AHQAKQAKACAAIAAgACAAVwByAGkAdABlAC0AUwBoAGEAcgBwAEUAbQB1AEkAbQBlAFIAZQBzAHUAbAB0ACAAKAAnAE8ASwA6ACcAIAArACAAWwBDAG8AbgB2AGUAcgB0AF0AOgA6AFQAbwBCAGEAcwBlADYANABTAHQAcgBpAG4AZwAoACQAYgB5AHQAZQBzACkAKQAKAH0AIABlAGwAcwBlACAAewAKACAAIAAgACAAVwByAGkAdABlAC0AUwBoAGEAcgBwAEUAbQB1AEkAbQBlAFIAZQBzAHUAbAB0ACAAJwBDAEEATgBDAEUATAA6ACcACgB9AAoAJABmAG8AcgBtAC4ARABpAHMAcABvAHMAZQAoACkACgA=";
        var windowsDirectory = Environment.GetEnvironmentVariable("WINDIR") ?? "C:\\Windows";
        var executable = Path.Combine(
            windowsDirectory,
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        if (!File.Exists(executable))
        {
            executable = "powershell.exe";
        }

        var psi = new ProcessStartInfo
        {
            FileName = executable,
            Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand " + encodedScript,
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            CreateNoWindow = false,
            WindowStyle = ProcessWindowStyle.Normal,
        };
        psi.Environment["SHARPEMU_IME_MAX"] = maxTextLength.ToString(System.Globalization.CultureInfo.InvariantCulture);
        psi.Environment["SHARPEMU_IME_INITIAL_B64"] =
            Convert.ToBase64String(Encoding.Unicode.GetBytes(initialText));
        psi.Environment["SHARPEMU_IME_RESULT_PATH"] = resultPath;

        try
        {
            using var process = new Process { StartInfo = psi };
            if (!process.Start())
            {
                throw new InvalidOperationException("powershell host panel could not be started");
            }

            Console.Error.WriteLine(
                $"[V74.0.86.1][IME_DIALOG] host_panel_spawn generation={generation} " +
                $"pid={process.Id} visible=True create_no_window=False window_style=Normal");

            lock (_gate)
            {
                if (generation != _generation)
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    return new HostPanelResult(null, EndStatusAborted, "stale-generation");
                }
                _hostPanelProcess = process;
            }

            process.WaitForExit();

            lock (_gate)
            {
                if (ReferenceEquals(_hostPanelProcess, process))
                {
                    _hostPanelProcess = null;
                }
            }

            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    $"PowerShell text panel exited with {process.ExitCode}");
            }

            if (!File.Exists(resultPath))
            {
                throw new InvalidOperationException(
                    "PowerShell text panel returned no result file");
            }

            var raw = File.ReadAllText(resultPath, Encoding.UTF8).Trim();
            if (raw.StartsWith("OK:", StringComparison.Ordinal))
            {
                var payload = raw.Substring(3);
                var text = payload.Length == 0
                    ? string.Empty
                    : Encoding.Unicode.GetString(Convert.FromBase64String(payload));
                return new HostPanelResult(
                    Truncate(text, maxTextLength),
                    EndStatusOk,
                    "host-visible-ok");
            }

            if (raw.StartsWith("CANCEL:", StringComparison.Ordinal))
            {
                return new HostPanelResult(null, EndStatusCanceled, "host-visible-cancel");
            }

            throw new InvalidOperationException(
                "PowerShell text panel returned an unrecognized result file");
        }
        finally
        {
            lock (_gate)
            {
                if (_hostPanelProcess is { HasExited: true })
                {
                    _hostPanelProcess = null;
                }
            }

            try
            {
                if (File.Exists(resultPath))
                {
                    File.Delete(resultPath);
                }
            }
            catch
            {
                // Temp result cleanup is best effort only.
            }
        }
    }

    private static void CompleteHostPanel(
        long generation,
        string? text,
        int endStatus,
        string source)
    {
        lock (_gate)
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
            $"[V74.0.86.1][IME_DIALOG] host_panel_complete generation={generation} " +
            $"source={source} end_status={EndStatusName(endStatus)} chars={text?.Length ?? 0}");
    }

    private static void PumpCompletedHostPanel(CpuContext ctx)
    {
        ulong bufferAddress;
        uint maxTextLength;
        string? text;
        int endStatus;
        lock (_gate)
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
                    $"[V74.0.86.1][IME_DIALOG] text_commit_retry buffer=0x{bufferAddress:X16} " +
                    $"max={maxTextLength} chars={safeText.Length}");
                return;
            }

            Console.Error.WriteLine(
                $"[V74.0.86.1][IME_DIALOG] text_commit buffer=0x{bufferAddress:X16} " +
                $"max={maxTextLength} chars={safeText.Length} encoding=UTF16LE");
        }

        lock (_gate)
        {
            if (_status == StatusRunning && _completionReady)
            {
                _completionReady = false;
                _status = StatusFinished;
            }
        }
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

    private static void TryStopHostPanelLocked()
    {
        var process = _hostPanelProcess;
        _hostPanelProcess = null;
        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // The child may have already exited between the checks.
        }
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

    private readonly record struct HostPanelResult(string? Text, int EndStatus, string Source);
}
