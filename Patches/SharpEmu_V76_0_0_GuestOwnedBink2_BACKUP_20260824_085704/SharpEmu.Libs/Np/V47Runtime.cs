// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V47: Iterator/ConstIterator exact ABI from captured libSceNpCppWebApi.prx.
using System.Buffers.Binary;
using SharpEmu.HLE;
namespace SharpEmu.Libs.Np;
internal static class NpCppWebApiIteratorV47Runtime
{
    // V47 ABI marker: iterator refcount int32 +0, current pointer +8, object size 16.
    private static readonly object RefGate=new();
    private static int Fault(CpuContext c)=>c.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    private static int Ok=>(int)OrbisGen2Result.ORBIS_GEN2_OK;
    private static bool WriteU32(CpuContext c,ulong a,uint v)=>c.TryWriteUInt32(a,v);
    private static bool WriteU64(CpuContext c,ulong a,ulong v)=>c.TryWriteUInt64(a,v);
    private static bool ReadU64(CpuContext c,ulong a,out ulong v)=>c.TryReadUInt64(a,out v);
    public static int ConstructDefault(CpuContext c){var r=c[CpuRegister.Rax];var s=c[CpuRegister.Rdi];if(s==0||!WriteU32(c,s,0)||!WriteU64(c,s+8,0))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int ConstructPointer(CpuContext c){var r=c[CpuRegister.Rax];var s=c[CpuRegister.Rdi];if(s==0||!WriteU32(c,s,0)||!WriteU64(c,s+8,c[CpuRegister.Rsi]))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int Dereference(CpuContext c){var s=c[CpuRegister.Rdi];if(s==0||!ReadU64(c,s+8,out var p))return Fault(c);c[CpuRegister.Rax]=p;return Ok;}
    public static int Increment(CpuContext c,int n){var s=c[CpuRegister.Rdi];if(s==0||!ReadU64(c,s+8,out var p)||!WriteU64(c,s+8,unchecked(p+(ulong)n)))return Fault(c);c[CpuRegister.Rax]=s;return Ok;}
    public static int Decrement(CpuContext c,int n){var s=c[CpuRegister.Rdi];if(s==0||!ReadU64(c,s+8,out var p)||!WriteU64(c,s+8,unchecked(p-(ulong)n)))return Fault(c);c[CpuRegister.Rax]=s;return Ok;}
    public static int Assign(CpuContext c){var s=c[CpuRegister.Rdi];var x=c[CpuRegister.Rsi];if(s==0||x==0||!ReadU64(c,x+8,out var p)||!WriteU64(c,s+8,p))return Fault(c);c[CpuRegister.Rax]=s;return Ok;}
    public static int Compare(CpuContext c,bool equal){var a=c[CpuRegister.Rdi];var b=c[CpuRegister.Rsi];if(a==0||b==0||!ReadU64(c,a+8,out var p)||!ReadU64(c,b+8,out var q))return Fault(c);var e=p==q;c[CpuRegister.Rax]=(e==equal)?1UL:0UL;return Ok;}
    public static int Plus(CpuContext c,int n)
    {
        var d=c[CpuRegister.Rdi];var s=c[CpuRegister.Rsi];var count=c[CpuRegister.Rdx];if(d==0||s==0)return Fault(c);
        Span<byte> b=stackalloc byte[16];if(!c.Memory.TryRead(s,b))return Fault(c);var p=BinaryPrimitives.ReadUInt64LittleEndian(b.Slice(8,8));BinaryPrimitives.WriteUInt64LittleEndian(b.Slice(8,8),unchecked(p+count*(ulong)n));if(!c.Memory.TryWrite(d,b))return Fault(c);c[CpuRegister.Rax]=d;return Ok;
    }
    public static int AddRef(CpuContext c){var p=c[CpuRegister.Rdi];if(p==0)return Fault(c);lock(RefGate){if(!c.TryReadUInt32(p,out var v))return Fault(c);v=unchecked(v+1u);if(!c.TryWriteUInt32(p,v))return Fault(c);c[CpuRegister.Rax]=v;}return Ok;}
    public static int SubRef(CpuContext c){var p=c[CpuRegister.Rdi];if(p==0)return Fault(c);lock(RefGate){if(!c.TryReadUInt32(p,out var old))return Fault(c);if(!c.TryWriteUInt32(p,unchecked(old-1u)))return Fault(c);c[CpuRegister.Rax]=old;}return Ok;}
    public static int Destruct(CpuContext c)=>Ok;
}
