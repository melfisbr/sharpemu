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

        var script = @"
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$resultPath = $env:SHARPEMU_IME_RESULT_PATH
function Write-SharpEmuImeResult([string]$value) {
    [IO.File]::WriteAllText($resultPath, $value, (New-Object Text.UTF8Encoding($false)))
}
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SharpEmu - Text Input'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ShowIcon = $false
$form.ShowInTaskbar = $true
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(18,22,30)
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke
$form.ClientSize = New-Object System.Drawing.Size(980, 540)

$title = New-Object System.Windows.Forms.Label
$title.Left = 28
$title.Top = 18
$title.Width = 900
$title.Height = 28
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Text = 'Enter your player''s name'

$text = New-Object System.Windows.Forms.TextBox
$text.Left = 28
$text.Top = 58
$text.Width = 900
$text.Height = 34
$text.Font = New-Object System.Drawing.Font('Segoe UI', 16)
$text.MaxLength = [Math]::Max(1, [int]$env:SHARPEMU_IME_MAX)
if (-not [string]::IsNullOrEmpty($env:SHARPEMU_IME_INITIAL_B64)) {
    $text.Text = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:SHARPEMU_IME_INITIAL_B64))
}

$info = New-Object System.Windows.Forms.Label
$info.Left = 28
$info.Top = 100
$info.Width = 520
$info.Height = 22
$info.Text = 'Keyboard / mouse friendly overlay styled closer to the PS5 on-screen keyboard.'

$panel = New-Object System.Windows.Forms.Panel
$panel.Left = 28
$panel.Top = 136
$panel.Width = 900
$panel.Height = 280
$panel.BackColor = [System.Drawing.Color]::FromArgb(28,32,43)

$keys = @(
    '1','2','3','4','5','6','7','8','9','0','@',
    'q','w','e','r','t','y','u','i','o','p','#',
    'a','s','d','f','g','h','j','k','l',"'",'/',
    'z','x','c','v','b','n','m',',','.','?','!'
)
$startX = 18
$startY = 18
$keyW = 68
$keyH = 50
$gap = 10
for ($i = 0; $i -lt $keys.Count; $i++) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Width = $keyW
    $btn.Height = $keyH
    $row = [Math]::Floor($i / 11)
    $col = $i % 11
    $btn.Left = $startX + ($col * ($keyW + $gap))
    $btn.Top = $startY + ($row * ($keyH + $gap))
    $btn.Text = $keys[$i]
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 13)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(44,49,63)
    $btn.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $btn.FlatStyle = 'Flat'
    $btn.Add_Click({ $text.SelectedText = $this.Text; $text.Focus() })
    $panel.Controls.Add($btn)
}

$space = New-Object System.Windows.Forms.Button
$space.Left = 18
$space.Top = 240
$space.Width = 250
$space.Height = 28
$space.Text = 'Space'
$space.BackColor = [System.Drawing.Color]::FromArgb(44,49,63)
$space.ForeColor = [System.Drawing.Color]::WhiteSmoke
$space.FlatStyle = 'Flat'
$space.Add_Click({ $text.SelectedText = ' '; $text.Focus() })
$panel.Controls.Add($space)

$back = New-Object System.Windows.Forms.Button
$back.Left = 282
$back.Top = 240
$back.Width = 170
$back.Height = 28
$back.Text = 'Backspace'
$back.BackColor = [System.Drawing.Color]::FromArgb(44,49,63)
$back.ForeColor = [System.Drawing.Color]::WhiteSmoke
$back.FlatStyle = 'Flat'
$back.Add_Click({ if ($text.SelectionLength -gt 0) { $start = $text.SelectionStart; $text.Text = $text.Text.Remove($start, $text.SelectionLength); $text.SelectionStart = $start } elseif ($text.SelectionStart -gt 0) { $start = $text.SelectionStart; $text.Text = $text.Text.Remove($start - 1, 1); $text.SelectionStart = $start - 1 }; $text.Focus() })
$panel.Controls.Add($back)

$clear = New-Object System.Windows.Forms.Button
$clear.Left = 466
$clear.Top = 240
$clear.Width = 120
$clear.Height = 28
$clear.Text = 'Clear'
$clear.BackColor = [System.Drawing.Color]::FromArgb(44,49,63)
$clear.ForeColor = [System.Drawing.Color]::WhiteSmoke
$clear.FlatStyle = 'Flat'
$clear.Add_Click({ $text.Clear(); $text.Focus() })
$panel.Controls.Add($clear)

$abc = New-Object System.Windows.Forms.Label
$abc.Left = 606
$abc.Top = 244
$abc.Width = 260
$abc.Height = 22
$abc.Text = 'ABC    @#:    L1/R1  simulated layout groups'
$panel.Controls.Add($abc)

$done = New-Object System.Windows.Forms.Button
$done.Text = 'Done'
$done.Left = 746
$done.Top = 440
$done.Width = 182
$done.Height = 48
$done.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$done.BackColor = [System.Drawing.Color]::FromArgb(68,82,110)
$done.ForeColor = [System.Drawing.Color]::WhiteSmoke
$done.DialogResult = [System.Windows.Forms.DialogResult]::OK

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Left = 546
$cancel.Top = 440
$cancel.Width = 182
$cancel.Height = 48
$cancel.Font = New-Object System.Drawing.Font('Segoe UI', 12)
$cancel.BackColor = [System.Drawing.Color]::FromArgb(44,49,63)
$cancel.ForeColor = [System.Drawing.Color]::WhiteSmoke
$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

$hints = New-Object System.Windows.Forms.Label
$hints.Left = 28
$hints.Top = 448
$hints.Width = 470
$hints.Height = 38
$hints.Text = 'Enter confirms • ESC cancels • mouse can click keys • typed keyboard input also works'

$form.AcceptButton = $done
$form.CancelButton = $cancel
$form.Controls.Add($title)
$form.Controls.Add($text)
$form.Controls.Add($info)
$form.Controls.Add($panel)
$form.Controls.Add($hints)
$form.Controls.Add($done)
$form.Controls.Add($cancel)
$form.Add_Shown({
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.TopMost = $true
    $form.BringToFront()
    $form.Activate()
    $text.Focus()
    $text.Select($text.Text.Length,0)
})
$result = $form.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $bytes = [Text.Encoding]::Unicode.GetBytes($text.Text)
    Write-SharpEmuImeResult ('OK:' + [Convert]::ToBase64String($bytes))
} else {
    Write-SharpEmuImeResult 'CANCEL:'
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
