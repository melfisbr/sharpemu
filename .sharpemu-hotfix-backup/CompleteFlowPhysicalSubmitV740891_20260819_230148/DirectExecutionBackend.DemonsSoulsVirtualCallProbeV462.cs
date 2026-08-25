// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Text;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    private const ulong DemonMainVirtualCallFaultRipV462 = 0x0000000801388AB4UL;
    private const ulong DemonHighGraphicsFaultRipV462 = 0x0000000801104ED6UL;
    private const ulong DemonHighGraphicsEntryV462 = 0x0000000801104E90UL;

    private static int _demonVirtualCallProbeCountV462;
    private static int _demonHighGraphicsStartProbeCountV462;

    /// <summary>
    /// Evidence-only V46.2 probe. It never changes guest memory, registers, RIP,
    /// exception state, scheduling state, or recovery decisions.
    /// </summary>
    private unsafe void ProbeDemonVirtualCallFaultV462(
        EXCEPTION_RECORD* exceptionRecord,
        void* contextRecord,
        ulong rip)
    {
        if (exceptionRecord == null ||
            contextRecord == null ||
            exceptionRecord->ExceptionCode != 0xC0000005u ||
            (rip != DemonMainVirtualCallFaultRipV462 &&
             rip != DemonHighGraphicsFaultRipV462))
        {
            return;
        }

        var ordinal = Interlocked.Increment(ref _demonVirtualCallProbeCountV462);
        if (ordinal > 8)
        {
            return;
        }

        var rax = ReadCtxU64(contextRecord, CTX_RAX);
        var rbx = ReadCtxU64(contextRecord, CTX_RBX);
        var rcx = ReadCtxU64(contextRecord, CTX_RCX);
        var rdx = ReadCtxU64(contextRecord, CTX_RDX);
        var rsi = ReadCtxU64(contextRecord, CTX_RSI);
        var rdi = ReadCtxU64(contextRecord, CTX_RDI);
        var rbp = ReadCtxU64(contextRecord, CTX_RBP);
        var rsp = ReadCtxU64(contextRecord, CTX_RSP);
        var r8 = ReadCtxU64(contextRecord, CTX_R8);
        var r9 = ReadCtxU64(contextRecord, CTX_R9);
        var r10 = ReadCtxU64(contextRecord, CTX_R10);
        var r11 = ReadCtxU64(contextRecord, CTX_R11);
        var r12 = ReadCtxU64(contextRecord, CTX_R12);
        var r13 = ReadCtxU64(contextRecord, CTX_R13);
        var r14 = ReadCtxU64(contextRecord, CTX_R14);
        var r15 = ReadCtxU64(contextRecord, CTX_R15);

        ulong avType = 0;
        ulong avTarget = 0;
        if (exceptionRecord->NumberParameters >= 2)
        {
            avType = exceptionRecord->ExceptionInformation[0];
            avTarget = exceptionRecord->ExceptionInformation[1];
        }

        Console.Error.WriteLine("[DS-VPROBE][V46.2] ===================================================");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] fault#{ordinal} rip=0x{rip:X16} " +
            $"av_type={avType} av_target=0x{avTarget:X16}");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] rax=0x{rax:X16} rbx=0x{rbx:X16} " +
            $"rcx=0x{rcx:X16} rdx=0x{rdx:X16}");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] rsi=0x{rsi:X16} rdi=0x{rdi:X16} " +
            $"rbp=0x{rbp:X16} rsp=0x{rsp:X16}");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] r8=0x{r8:X16} r9=0x{r9:X16} " +
            $"r10=0x{r10:X16} r11=0x{r11:X16}");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] r12=0x{r12:X16} r13=0x{r13:X16} " +
            $"r14=0x{r14:X16} r15=0x{r15:X16}");
        Console.Error.WriteLine(
            $"[DS-VPROBE][V46.2] rax_class={ClassifyDemonAddressV462(rax)} " +
            $"rax_utf16='{DecodeDemonInlineUtf16QwordV462(rax)}' " +
            $"rdi_class={ClassifyDemonAddressV462(rdi)} rbx_class={ClassifyDemonAddressV462(rbx)}");

        DumpDemonBytesV462("code.rip-0x30", rip >= 0x30 ? rip - 0x30 : rip, 0x70);
        DumpDemonRegionAndPointersV462("rbx.parent", rbx, 0x180, rdi);
        DumpDemonRegionAndPointersV462("rdi.virtual-target", rdi, 0x180, rax);
        DumpDemonRegionAndPointersV462("rsi", rsi, 0x100, rdi);
        DumpDemonRegionAndPointersV462("rsp", rsp, 0x100, 0);

        if (rbx != 0)
        {
            FindDemonPointerValueV462("rbx.parent", rbx, 0x200, rdi, "RDI");
            FindDemonPointerValueV462("rbx.parent", rbx, 0x200, rax, "RAX");
            if (rip == DemonMainVirtualCallFaultRipV462)
            {
                Console.Error.WriteLine(
                    $"[DS-VPROBE][V46.2] main_relationship " +
                    $"rbx_plus_10={ReadDemonQwordTextV462(rbx + 0x10)} " +
                    $"rbx_plus_60={ReadDemonQwordTextV462(rbx + 0x60)}");
            }
            else
            {
                Console.Error.WriteLine(
                    $"[DS-VPROBE][V46.2] highgfx_relationship " +
                    $"rsi_minus_rbx=0x{(rsi >= rbx ? rsi - rbx : 0):X} " +
                    $"rbx_plus_60={ReadDemonQwordTextV462(rbx + 0x60)} " +
                    $"rbx_plus_68={ReadDemonQwordTextV462(rbx + 0x68)}");
            }
        }

        Console.Error.WriteLine("[DS-VPROBE][V46.2] ===================================================");
        Console.Error.Flush();
    }

    /// <summary>
    /// Called after the guest thread state is queued but before Pump/dispatch.
    /// It is read-only and proves whether the malformed pointer exists before
    /// HighGraphics executes its first guest instruction.
    /// </summary>
    private unsafe void ProbeDemonThreadStartV462(GuestThreadState thread)
    {
        if (thread is null ||
            (thread.EntryPoint != DemonHighGraphicsEntryV462 &&
             !string.Equals(thread.Name, "HighGraphics", StringComparison.Ordinal)))
        {
            return;
        }

        var ordinal = Interlocked.Increment(ref _demonHighGraphicsStartProbeCountV462);
        if (ordinal > 4)
        {
            return;
        }

        Console.Error.WriteLine("[DS-THREADSTART][V46.2] ==============================================");
        Console.Error.WriteLine(
            $"[DS-THREADSTART][V46.2] snapshot#{ordinal} name='{thread.Name}' " +
            $"handle=0x{thread.ThreadHandle:X16} entry=0x{thread.EntryPoint:X16} " +
            $"arg=0x{thread.Argument:X16} priority={thread.Priority} affinity=0x{thread.AffinityMask:X}");

        DumpDemonRegionAndPointersV462("highgfx.arg.pre-run", thread.Argument, 0x200, 0);

        if (thread.Argument != 0)
        {
            DumpDemonBytesV462("highgfx.arg+0x40", thread.Argument + 0x40, 0x80);
            for (var off = 0; off < 0x100; off += 8)
            {
                if (!TryReadDemonQwordV462(thread.Argument + (ulong)off, out var value))
                {
                    break;
                }

                if (ClassifyDemonAddressV462(value) == "mapped" &&
                    TryReadDemonQwordV462(value, out var head))
                {
                    var score = ScoreDemonUtf16QwordV462(head);
                    if (score >= 2)
                    {
                        Console.Error.WriteLine(
                            $"[DS-THREADSTART][V46.2] text_pointer offset=0x{off:X2} " +
                            $"ptr=0x{value:X16} head=0x{head:X16} " +
                            $"utf16='{DecodeDemonInlineUtf16QwordV462(head)}' score={score}");
                        DumpDemonBytesV462($"highgfx.arg+0x{off:X2}->text", value, 0x80);
                    }
                }
            }
        }

        Console.Error.WriteLine("[DS-THREADSTART][V46.2] ==============================================");
        Console.Error.Flush();
    }

    private unsafe void DumpDemonRegionAndPointersV462(
        string label,
        ulong address,
        int byteCount,
        ulong highlight)
    {
        DumpDemonBytesV462(label, address, byteCount);

        if (!TryGetDemonReadableBytesV462(address, byteCount, out var readable) || readable < 8)
        {
            return;
        }

        var limit = Math.Min(readable, byteCount);
        var followed = 0;
        for (var off = 0; off + 8 <= limit; off += 8)
        {
            var value = *(ulong*)(address + (ulong)off);
            var cls = ClassifyDemonAddressV462(value);
            var inline = DecodeDemonInlineUtf16QwordV462(value);
            var suffix = value == highlight && highlight != 0 ? " MATCH" : string.Empty;
            Console.Error.WriteLine(
                $"[DS-VPROBE][V46.2] {label}+0x{off:X3}=0x{value:X16} " +
                $"class={cls} inline_utf16='{inline}'{suffix}");

            if (cls == "mapped" && followed < 24 &&
                TryReadDemonQwordV462(value, out var head))
            {
                var headClass = ClassifyDemonAddressV462(head);
                var headText = DecodeDemonInlineUtf16QwordV462(head);
                var score = ScoreDemonUtf16QwordV462(head);
                Console.Error.WriteLine(
                    $"[DS-VPROBE][V46.2]   -> head=0x{head:X16} " +
                    $"head_class={headClass} head_utf16='{headText}' text_score={score}");
                if (score >= 2)
                {
                    DumpDemonBytesV462($"{label}+0x{off:X3}->text", value, 0x60);
                }

                followed++;
            }
        }
    }

    private unsafe void FindDemonPointerValueV462(
        string label,
        ulong baseAddress,
        int byteCount,
        ulong wanted,
        string wantedName)
    {
        if (wanted == 0 ||
            !TryGetDemonReadableBytesV462(baseAddress, byteCount, out var readable))
        {
            return;
        }

        var limit = Math.Min(readable, byteCount);
        var matches = 0;
        for (var off = 0; off + 8 <= limit; off += 8)
        {
            if (*(ulong*)(baseAddress + (ulong)off) == wanted)
            {
                Console.Error.WriteLine(
                    $"[DS-VPROBE][V46.2] pointer_match {label}+0x{off:X3} == " +
                    $"{wantedName}=0x{wanted:X16}");
                matches++;
            }
        }

        if (matches == 0)
        {
            Console.Error.WriteLine(
                $"[DS-VPROBE][V46.2] pointer_match {label}: no {wantedName}=0x{wanted:X16} in first 0x{limit:X} bytes");
        }
    }

    private unsafe void DumpDemonBytesV462(string label, ulong address, int requestedBytes)
    {
        if (address == 0)
        {
            Console.Error.WriteLine($"[DS-VPROBE][V46.2] {label}: NULL");
            return;
        }

        if (!TryGetDemonReadableBytesV462(address, requestedBytes, out var count))
        {
            Console.Error.WriteLine(
                $"[DS-VPROBE][V46.2] {label}: addr=0x{address:X16} " +
                $"unreadable class={ClassifyDemonAddressV462(address)} " +
                $"inline_utf16='{DecodeDemonInlineUtf16QwordV462(address)}'");
            return;
        }

        var ptr = (byte*)address;
        for (var row = 0; row < count; row += 32)
        {
            var rowCount = Math.Min(32, count - row);
            var hex = new StringBuilder(rowCount * 3);
            var utf16 = new StringBuilder(16);
            for (var i = 0; i < rowCount; i++)
            {
                if (i != 0)
                {
                    hex.Append(' ');
                }

                hex.Append(ptr[row + i].ToString("X2"));
            }

            for (var i = 0; i + 1 < rowCount; i += 2)
            {
                var ch = (char)(ptr[row + i] | (ptr[row + i + 1] << 8));
                utf16.Append(ch >= ' ' && !char.IsControl(ch) ? ch : '·');
            }

            Console.Error.WriteLine(
                $"[DS-VPROBE][V46.2] {label}+0x{row:X3} addr=0x{address + (ulong)row:X16} " +
                $"hex={hex} utf16='{utf16}'");
        }
    }

    private unsafe bool TryReadDemonQwordV462(ulong address, out ulong value)
    {
        value = 0;
        if (!TryGetDemonReadableBytesV462(address, 8, out var readable) || readable < 8)
        {
            return false;
        }

        value = *(ulong*)address;
        return true;
    }

    private unsafe string ReadDemonQwordTextV462(ulong address)
    {
        return TryReadDemonQwordV462(address, out var value)
            ? $"0x{value:X16}"
            : "unreadable";
    }

    private unsafe bool TryGetDemonReadableBytesV462(
        ulong address,
        int requestedBytes,
        out int readableBytes)
    {
        readableBytes = 0;
        if (address < 0x1000 ||
            address >= 0x0000800000000000UL ||
            requestedBytes <= 0)
        {
            return false;
        }

        MEMORY_BASIC_INFORMATION64 info;
        if (VirtualQuery(
                (void*)address,
                out info,
                (nuint)sizeof(MEMORY_BASIC_INFORMATION64)) == 0 ||
            info.RegionSize == 0 ||
            info.State != MEM_COMMIT ||
            (info.Protect & PAGE_GUARD) != 0)
        {
            return false;
        }

        var baseProtect = info.Protect & 0xFFu;
        if (baseProtect is not (0x02u or 0x04u or 0x08u or 0x20u or 0x40u or 0x80u))
        {
            return false;
        }

        var end = info.BaseAddress + info.RegionSize;
        if (end <= address)
        {
            return false;
        }

        readableBytes = (int)Math.Min(
            (ulong)requestedBytes,
            end - address);
        return readableBytes > 0;
    }

    private unsafe string ClassifyDemonAddressV462(ulong value)
    {
        if (value == 0)
        {
            return "null";
        }

        if (value < 0x1000)
        {
            return "small";
        }

        if (value >= 0x0000800000000000UL)
        {
            return "noncanonical";
        }

        return TryGetDemonReadableBytesV462(value, 1, out _)
            ? "mapped"
            : "canonical-unmapped";
    }

    private static int ScoreDemonUtf16QwordV462(ulong value)
    {
        var printable = 0;
        var zero = 0;
        for (var i = 0; i < 4; i++)
        {
            var ch = (char)((value >> (i * 16)) & 0xFFFF);
            if (ch == '\0')
            {
                zero++;
            }
            else if ((ch >= ' ' && ch <= '~') ||
                     (!char.IsControl(ch) && char.IsLetterOrDigit(ch)))
            {
                printable++;
            }
        }

        return printable >= 2 && zero <= 2 ? printable : 0;
    }

    private static string DecodeDemonInlineUtf16QwordV462(ulong value)
    {
        Span<char> chars = stackalloc char[4];
        var useful = 0;
        for (var i = 0; i < 4; i++)
        {
            var ch = (char)((value >> (i * 16)) & 0xFFFF);
            if (ch == '\0' || char.IsControl(ch) || ch < ' ')
            {
                chars[i] = '·';
            }
            else
            {
                chars[i] = ch;
                useful++;
            }
        }

        return useful == 0 ? string.Empty : new string(chars);
    }
}
