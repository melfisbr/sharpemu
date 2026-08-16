// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V50: exact leaf-body translations from captured libSceNpCppWebApi.prx.
using SharpEmu.HLE;
namespace SharpEmu.Libs.Np;
internal static class NpCppWebApiLeafV50Runtime
{
    // V50 ABI marker: every wrapper is backed by an exact leaf machine-code body in API_EVIDENCE.csv.
    private static int Fault(CpuContext c)=>c.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    private static int Ok=>(int)OrbisGen2Result.ORBIS_GEN2_OK;
    public static int Noop(CpuContext c)=>Ok;
    public static int Zero16(CpuContext c){var r=c[CpuRegister.Rax];Span<byte>b=stackalloc byte[16];b.Clear();if(c[CpuRegister.Rdi]==0||!c.Memory.TryWrite(c[CpuRegister.Rdi],b))return Fault(c);c.SetXmmRegister(0,0,0);c[CpuRegister.Rax]=r;return Ok;}
    public static int Copy16(CpuContext c){Span<byte>b=stackalloc byte[16];if(c[CpuRegister.Rdi]==0||c[CpuRegister.Rsi]==0||!c.Memory.TryRead(c[CpuRegister.Rsi],b)||!c.Memory.TryWrite(c[CpuRegister.Rdi],b))return Fault(c);var high=System.Buffers.Binary.BinaryPrimitives.ReadUInt64LittleEndian(b.Slice(8,8));c[CpuRegister.Rax]=high;return Ok;}
    public static int Lea(CpuContext c,int o){c[CpuRegister.Rax]=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);return Ok;}
    public static int Get8(CpuContext c,int o){var a=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);if(!c.TryReadByte(a,out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Get32(CpuContext c,int o){var a=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);if(!c.TryReadUInt32(a,out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Get64(CpuContext c,int o){var a=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);if(!c.TryReadUInt64(a,out var v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Has64(CpuContext c,int o){var a=unchecked(c[CpuRegister.Rdi]+(ulong)(long)o);if(!c.TryReadUInt64(a,out var v))return Fault(c);var r=c[CpuRegister.Rax];c[CpuRegister.Rax]=(r&~0xFFUL)|(v==0?0UL:1UL);return Ok;}
    public static int CopyRef32(CpuContext c,int o){if(c[CpuRegister.Rsi]==0||!c.TryReadUInt32(c[CpuRegister.Rsi],out var v)||!c.TryWriteUInt32(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int CopyRef64(CpuContext c,int o){if(c[CpuRegister.Rsi]==0||!c.TryReadUInt64(c[CpuRegister.Rsi],out var v)||!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),v))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int StoreReg64(CpuContext c,int o){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),c[CpuRegister.Rsi]))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int CopyRef32Flag(CpuContext c,int o,int flag){if(c[CpuRegister.Rsi]==0||!c.TryReadUInt32(c[CpuRegister.Rsi],out var v)||!c.TryWriteUInt32(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),v)||!c.Memory.TryWrite(unchecked(c[CpuRegister.Rdi]+(ulong)(long)flag),new byte[]{1}))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int CopyRef64Flag(CpuContext c,int o,int flag){if(c[CpuRegister.Rsi]==0||!c.TryReadUInt64(c[CpuRegister.Rsi],out var v)||!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),v)||!c.Memory.TryWrite(unchecked(c[CpuRegister.Rdi]+(ulong)(long)flag),new byte[]{1}))return Fault(c);c[CpuRegister.Rax]=v;return Ok;}
    public static int Zero32(CpuContext c,int o){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt32(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),0))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int Zero64(CpuContext c,int o){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),0))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int Zero32Flag(CpuContext c,int o,int flag){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt32(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),0)||!c.Memory.TryWrite(unchecked(c[CpuRegister.Rdi]+(ulong)(long)flag),new byte[]{0}))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int Zero64Flag(CpuContext c,int o,int flag){var r=c[CpuRegister.Rax];if(!c.TryWriteUInt64(unchecked(c[CpuRegister.Rdi]+(ulong)(long)o),0)||!c.Memory.TryWrite(unchecked(c[CpuRegister.Rdi]+(ulong)(long)flag),new byte[]{0}))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
}
