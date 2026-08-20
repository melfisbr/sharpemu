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
/// V74.0.85 replaces the old immediate "Sharp" autofill stub. sceImeDialogInit
/// now enters RUNNING, opens a real host text-entry panel on Windows, and only
/// reports FINISHED after the user presses OK/Cancel. The guest-owned UTF-16
/// input buffer is written from a live guest CpuContext while GetStatus/GetResult
/// polls, avoiding guest-memory writes from the host UI thread.
/// </summary>
public static class ImeDialogExports
{
    private const string V74085Marker = "SHARPEMU_V74_0_85_IME_DIALOG_HOST_TEXT_INPUT";

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
                $"[V74.0.85][IME_DIALOG] init_failed param=0x{parameterAddress:X16} " +
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
            $"[V74.0.85][IME_DIALOG] init count={count} generation={generation} " +
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
                $"[V74.0.85][IME_DIALOG] get_status count={count} status={StatusName(status)}");
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
                $"[V74.0.85][IME_DIALOG] get_result_failed result=0x{resultAddress:X16}");
            return SetReturn(ctx, ImeDialogErrorInvalidAddress);
        }

        var count = System.Threading.Interlocked.Increment(ref _resultCount);
        Console.Error.WriteLine(
            $"[V74.0.85][IME_DIALOG] get_result count={count} result=0x{resultAddress:X16} " +
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

        Console.Error.WriteLine("[V74.0.85][IME_DIALOG] abort status=FINISHED end_status=ABORTED");
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

        Console.Error.WriteLine("[V74.0.85][IME_DIALOG] term status=NONE");
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
                    $"[V74.0.85][IME_DIALOG] host_panel_open generation={generation} " +
                    $"max={maxTextLength} backend=windows-powershell-winforms");

                var result = RunWindowsHostPanel(generation, initialText, maxTextLength);
                CompleteHostPanel(generation, result.Text, result.EndStatus, result.Source);
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(
                    $"[V74.0.85][IME_DIALOG] host_panel_error generation={generation} " +
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
        var script = @"
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SharpEmu - Text Input'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.Width = 540
$form.Height = 185
$label = New-Object System.Windows.Forms.Label
$label.Left = 18
$label.Top = 18
$label.Width = 490
$label.Height = 24
$label.Text = 'Enter text, then press OK:'
$text = New-Object System.Windows.Forms.TextBox
$text.Left = 18
$text.Top = 48
$text.Width = 490
$text.Height = 26
$text.MaxLength = [Math]::Max(1, [int]$env:SHARPEMU_IME_MAX)
if (-not [string]::IsNullOrEmpty($env:SHARPEMU_IME_INITIAL_B64)) {
    $text.Text = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:SHARPEMU_IME_INITIAL_B64))
}
$ok = New-Object System.Windows.Forms.Button
$ok.Text = 'OK'
$ok.Left = 352
$ok.Top = 92
$ok.Width = 74
$ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Left = 434
$cancel.Top = 92
$cancel.Width = 74
$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.AcceptButton = $ok
$form.CancelButton = $cancel
$form.Controls.Add($label)
$form.Controls.Add($text)
$form.Controls.Add($ok)
$form.Controls.Add($cancel)
$form.Add_Shown({ $form.Activate(); $text.Focus(); $text.SelectAll() })
$result = $form.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $bytes = [Text.Encoding]::Unicode.GetBytes($text.Text)
    [Console]::Out.WriteLine('OK:' + [Convert]::ToBase64String($bytes))
} else {
    [Console]::Out.WriteLine('CANCEL:')
}
$form.Dispose()
";

        var encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
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
            Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -EncodedCommand " + encodedScript,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        psi.Environment["SHARPEMU_IME_MAX"] = maxTextLength.ToString(System.Globalization.CultureInfo.InvariantCulture);
        psi.Environment["SHARPEMU_IME_INITIAL_B64"] =
            Convert.ToBase64String(Encoding.Unicode.GetBytes(initialText));

        using var process = new Process { StartInfo = psi };
        if (!process.Start())
        {
            throw new InvalidOperationException("powershell host panel could not be started");
        }

        lock (_gate)
        {
            if (generation != _generation)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                return new HostPanelResult(null, EndStatusAborted, "stale-generation");
            }
            _hostPanelProcess = process;
        }

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
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
                $"PowerShell text panel exited with {process.ExitCode}: {stderr.Trim()}");
        }

        foreach (var rawLine in stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var line = rawLine.Trim();
            if (line.StartsWith("OK:", StringComparison.Ordinal))
            {
                var payload = line.Substring(3);
                var text = payload.Length == 0
                    ? string.Empty
                    : Encoding.Unicode.GetString(Convert.FromBase64String(payload));
                return new HostPanelResult(
                    Truncate(text, maxTextLength),
                    EndStatusOk,
                    "host-ok");
            }
            if (line.StartsWith("CANCEL:", StringComparison.Ordinal))
            {
                return new HostPanelResult(null, EndStatusCanceled, "host-cancel");
            }
        }

        throw new InvalidOperationException("PowerShell text panel returned no recognized result");
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
            $"[V74.0.85][IME_DIALOG] host_panel_complete generation={generation} " +
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
                    $"[V74.0.85][IME_DIALOG] text_commit_retry buffer=0x{bufferAddress:X16} " +
                    $"max={maxTextLength} chars={safeText.Length}");
                return;
            }

            Console.Error.WriteLine(
                $"[V74.0.85][IME_DIALOG] text_commit buffer=0x{bufferAddress:X16} " +
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
