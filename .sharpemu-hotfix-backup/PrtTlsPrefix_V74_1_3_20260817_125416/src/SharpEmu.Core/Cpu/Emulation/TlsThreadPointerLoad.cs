// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;

namespace SharpEmu.Core.Cpu.Emulation;

/// <summary>
/// Recognizes the PS5 guest thread-pointer load encoded as mov reg, fs:[0].
/// Shared by the ahead-of-time TLS patcher and the fault-time recovery path.
/// </summary>
public static class TlsThreadPointerLoad
{
    public const int MaxLength = 12;

    public static bool TryDecode(
        ReadOnlySpan<byte> code,
        out int destinationRegister,
        out int length)
    {
        destinationRegister = 0;
        length = 0;

        int offset = 0;
        while (offset < code.Length && code[offset] == 0x66)
        {
            offset++;
        }

        if (offset >= code.Length || code[offset] != 0x64)
        {
            return false;
        }

        offset++;
        if (offset >= code.Length)
        {
            return false;
        }

        byte rex = 0;
        if (code[offset] >= 0x40 && code[offset] <= 0x4F)
        {
            rex = code[offset++];
        }

        // 8B /r, mod=00 rm=100, SIB=0x25, disp32=0 => absolute FS:[0].
        if (offset + 7 > code.Length || code[offset] != 0x8B)
        {
            return false;
        }

        byte modRm = code[offset + 1];
        byte sib = code[offset + 2];
        if ((modRm >> 6) != 0 || (modRm & 7) != 4 || sib != 0x25)
        {
            return false;
        }

        int displacement =
            code[offset + 3] |
            (code[offset + 4] << 8) |
            (code[offset + 5] << 16) |
            (code[offset + 6] << 24);

        if (displacement != 0)
        {
            return false;
        }

        destinationRegister = ((modRm >> 3) & 7) | (((rex & 4) != 0) ? 8 : 0);
        length = offset + 7;
        return true;
    }
}
