// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Text;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
    private const ulong DemonResourceNodeFaultRipV461 = 0x00000008010FEB81UL;
    private static int _demonResourceNodeProbeCount;

    /// <summary>
    /// V46.1 evidence-only probe for the Demon's Souls resource dependency crash.
    /// This method never mutates guest memory, registers, RIP, or exception state.
    /// </summary>
    private unsafe void ProbeDemonResourceNodeFaultV461(
        EXCEPTION_RECORD* exceptionRecord,
        void* contextRecord,
        ulong rip)
    {
        if (rip != DemonResourceNodeFaultRipV461 ||
            exceptionRecord == null ||
            contextRecord == null ||
            exceptionRecord->ExceptionCode != 0xC0000005u)
        {
            return;
        }

        var index = System.Threading.Interlocked.Increment(ref _demonResourceNodeProbeCount);
        if (index > 4)
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
        var r8  = ReadCtxU64(contextRecord, CTX_R8);
        var r9  = ReadCtxU64(contextRecord, CTX_R9);
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

        Console.Error.WriteLine("[DS-RESNODE][V46.1] ========================================");
        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] fault#{index} rip=0x{rip:X16} av_type={avType} av_target=0x{avTarget:X16}");
        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] r13(node)=0x{r13:X16} r9(prev?)=0x{r9:X16} r10(next?)=0x{r10:X16}");
        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] rax=0x{rax:X16} rbx=0x{rbx:X16} rcx=0x{rcx:X16} rdx=0x{rdx:X16}");
        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] rsi=0x{rsi:X16} rdi=0x{rdi:X16} rbp=0x{rbp:X16} rsp=0x{rsp:X16}");
        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] r8=0x{r8:X16} r11=0x{r11:X16} r12=0x{r12:X16} r14=0x{r14:X16} r15=0x{r15:X16}");

        DumpDemonProbeAddressV461("r13.node", r13, 0x100);
        DumpDemonProbeAddressV461("r13.minus80", r13 >= 0x80 ? r13 - 0x80 : 0, 0x80);
        DumpDemonProbeAddressV461("r9", r9, 0x40);
        DumpDemonProbeAddressV461("r10", r10, 0x40);
        DumpDemonProbeAddressV461("rsp", rsp, 0x100);
        DumpDemonProbeAddressV461("rbp", rbp, 0x80);

        // Walk the node's first 0x80 bytes as qwords. For mapped pointer-looking
        // values, also dump the pointee head. For inline text-looking qwords,
        // print a UTF-16 interpretation.
        if (IsDemonProbeReadableV461(r13, 0x80))
        {
            for (var off = 0; off < 0x80; off += 8)
            {
                var value = *(ulong*)(r13 + (ulong)off);
                var utf16 = DecodeInlineUtf16QwordV461(value);
                var pointerClass = ClassifyDemonProbePointerV461(value);
                Console.Error.WriteLine(
                    $"[DS-RESNODE][V46.1] node+0x{off:X2}=0x{value:X16} class={pointerClass} utf16='{utf16}'");

                if (pointerClass == "mapped")
                {
                    DumpDemonProbeAddressV461($"node+0x{off:X2}->", value, 0x30);
                }
            }
        }

        Console.Error.WriteLine("[DS-RESNODE][V46.1] ========================================");
        Console.Error.Flush();
    }

    private unsafe void DumpDemonProbeAddressV461(string label, ulong address, int requestedBytes)
    {
        if (address == 0)
        {
            Console.Error.WriteLine($"[DS-RESNODE][V46.1] {label}: NULL");
            return;
        }

        if (!TryGetDemonProbeReadableBytesV461(address, requestedBytes, out var count))
        {
            Console.Error.WriteLine(
                $"[DS-RESNODE][V46.1] {label}: addr=0x{address:X16} unreadable class={ClassifyDemonProbePointerV461(address)} inline_utf16='{DecodeInlineUtf16QwordV461(address)}'");
            return;
        }

        var sb = new StringBuilder(count * 3);
        var text = new StringBuilder(count / 2);
        var ptr = (byte*)address;
        for (var i = 0; i < count; i++)
        {
            if (i != 0)
            {
                sb.Append(' ');
            }

            sb.Append(ptr[i].ToString("X2"));
        }

        for (var i = 0; i + 1 < count && text.Length < 48; i += 2)
        {
            var ch = (char)(ptr[i] | (ptr[i + 1] << 8));
            if (ch == '\0')
            {
                text.Append('·');
            }
            else if (!char.IsControl(ch) && ch >= ' ')
            {
                text.Append(ch);
            }
            else
            {
                text.Append('·');
            }
        }

        Console.Error.WriteLine(
            $"[DS-RESNODE][V46.1] {label}: addr=0x{address:X16} bytes={count} hex={sb} utf16='{text}'");
    }

    private unsafe bool IsDemonProbeReadableV461(ulong address, int requestedBytes) =>
        TryGetDemonProbeReadableBytesV461(address, requestedBytes, out var count) &&
        count >= requestedBytes;

    private unsafe bool TryGetDemonProbeReadableBytesV461(
        ulong address,
        int requestedBytes,
        out int readableBytes)
    {
        readableBytes = 0;
        if (address < 0x1000 || address >= 0x0000800000000000UL || requestedBytes <= 0)
        {
            return false;
        }

        MEMORY_BASIC_INFORMATION64 info;
        if (VirtualQuery((void*)address, out info, (nuint)sizeof(MEMORY_BASIC_INFORMATION64)) == 0 ||
            info.RegionSize == 0 ||
            info.State != MEM_COMMIT ||
            (info.Protect & PAGE_GUARD) != 0 ||
            (info.Protect & 0xFFu) == PAGE_NOACCESS)
        {
            return false;
        }

        var end = info.BaseAddress + info.RegionSize;
        if (end <= address)
        {
            return false;
        }

        var available = end - address;
        readableBytes = (int)Math.Min((ulong)requestedBytes, available);
        return readableBytes > 0;
    }

    private unsafe string ClassifyDemonProbePointerV461(ulong value)
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

        return TryGetDemonProbeReadableBytesV461(value, 1, out _)
            ? "mapped"
            : "canonical-unmapped";
    }

    private static string DecodeInlineUtf16QwordV461(ulong value)
    {
        Span<char> chars = stackalloc char[4];
        var useful = 0;
        for (var i = 0; i < 4; i++)
        {
            var ch = (char)((value >> (i * 16)) & 0xFFFF);
            if (ch == '\0')
            {
                chars[i] = '·';
                continue;
            }

            if (char.IsControl(ch) || ch < ' ')
            {
                chars[i] = '·';
                continue;
            }

            chars[i] = ch;
            useful++;
        }

        return useful == 0 ? string.Empty : new string(chars);
    }
}
