// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V51: exact libc.prx leaf-body translations.
using SharpEmu.HLE;
namespace SharpEmu.Libs.LibcCompat;
internal static class LibcLeafV51Runtime
{
    // V51 ABI marker: exact leaf bodies only; no internal-call emulation is guessed.
    private static int Fault(CpuContext c)=>c.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    private static int Ok=>(int)OrbisGen2Result.ORBIS_GEN2_OK;
    public static int Noop(CpuContext c)=>Ok;
    public static int Const32(CpuContext c,uint v){c[CpuRegister.Rax]=v;return Ok;}
    public static int ReturnRdi64(CpuContext c){c[CpuRegister.Rax]=c[CpuRegister.Rdi];return Ok;}
    public static int ReturnEdi32(CpuContext c){c[CpuRegister.Rax]=(uint)c[CpuRegister.Rdi];return Ok;}
    public static int Load8(CpuContext c,int o){if(!c.TryReadByte(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Load32(CpuContext c,int o){if(!c.TryReadUInt32(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Load64(CpuContext c,int o){if(!c.TryReadUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Store64Rsi(CpuContext c,int o){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),c[CpuRegister.Rsi]))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int LeaRdi(CpuContext c,int o){c[CpuRegister.Rax]=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);return Ok;}
}
