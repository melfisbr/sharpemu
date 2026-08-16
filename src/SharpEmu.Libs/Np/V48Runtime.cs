// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V48: non-allocating Vector<T> ABI operations from captured libSceNpCppWebApi.prx.
using SharpEmu.HLE;
namespace SharpEmu.Libs.Np;
internal static class NpCppWebApiVectorV48Runtime
{
    // V48 ABI marker: begin/capacity/end/refcount/context offsets are evidence-derived per T.
    private static readonly object RefGate=new();
    private static int Fault(CpuContext c)=>c.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    private static int Ok=>(int)OrbisGen2Result.ORBIS_GEN2_OK;
    private static bool R(CpuContext c,ulong a,out ulong v)=>c.TryReadUInt64(a,out v);
    private static bool W(CpuContext c,ulong a,ulong v)=>c.TryWriteUInt64(a,v);
    public static int Construct(CpuContext c,int beginOffset,bool context)
    {
        var r=c[CpuRegister.Rax];var s=c[CpuRegister.Rdi];if(s==0)return Fault(c);
        for(var o=0;o<beginOffset;o+=8)if(!W(c,s+(ulong)o,0))return Fault(c);
        if(!W(c,s+(ulong)beginOffset,s)||!W(c,s+(ulong)beginOffset+8,s)||!W(c,s+(ulong)beginOffset+16,s)||!c.TryWriteUInt32(s+(ulong)beginOffset+24,0)||!W(c,s+(ulong)beginOffset+32,context?c[CpuRegister.Rsi]:0))return Fault(c);
        c[CpuRegister.Rax]=r;return Ok;
    }
    public static int IteratorAt(CpuContext c,int vectorOffset)
    {
        var d=c[CpuRegister.Rdi];var v=c[CpuRegister.Rsi];if(d==0||v==0||!R(c,v+(ulong)vectorOffset,out var p)||!c.TryWriteUInt32(d,0)||!W(c,d+8,p))return Fault(c);c[CpuRegister.Rax]=d;return Ok;
    }
    public static int Capacity(CpuContext c,int b,int n){var s=c[CpuRegister.Rdi];if(s==0||!R(c,s+(ulong)b,out var begin)||!R(c,s+(ulong)b+8,out var cap))return Fault(c);c[CpuRegister.Rax]=(cap-begin)/(ulong)n;return Ok;}
    public static int Size(CpuContext c,int b,int n){var s=c[CpuRegister.Rdi];if(s==0||!R(c,s+(ulong)b,out var begin)||!R(c,s+(ulong)b+16,out var end))return Fault(c);c[CpuRegister.Rax]=(end-begin)/(ulong)n;return Ok;}
    public static int Empty(CpuContext c,int b){var s=c[CpuRegister.Rdi];if(s==0||!R(c,s+(ulong)b,out var begin)||!R(c,s+(ulong)b+16,out var end))return Fault(c);c[CpuRegister.Rax]=begin==end?1UL:0UL;return Ok;}
    public static int Index(CpuContext c,int b,int n){var s=c[CpuRegister.Rdi];if(s==0||!R(c,s+(ulong)b,out var begin))return Fault(c);c[CpuRegister.Rax]=unchecked(begin+c[CpuRegister.Rsi]*(ulong)n);return Ok;}
    public static int SetContext(CpuContext c,int b){var r=c[CpuRegister.Rax];var s=c[CpuRegister.Rdi];if(s==0||!W(c,s+(ulong)b+32,c[CpuRegister.Rsi]))return Fault(c);c[CpuRegister.Rax]=r;return Ok;}
    public static int AddRef(CpuContext c,int b){var p=c[CpuRegister.Rdi]+(ulong)b+24;if(c[CpuRegister.Rdi]==0)return Fault(c);lock(RefGate){if(!c.TryReadUInt32(p,out var v))return Fault(c);v=unchecked(v+1u);if(!c.TryWriteUInt32(p,v))return Fault(c);c[CpuRegister.Rax]=v;}return Ok;}
    public static int SubRef(CpuContext c,int b){var p=c[CpuRegister.Rdi]+(ulong)b+24;if(c[CpuRegister.Rdi]==0)return Fault(c);lock(RefGate){if(!c.TryReadUInt32(p,out var old))return Fault(c);if(!c.TryWriteUInt32(p,unchecked(old-1u)))return Fault(c);c[CpuRegister.Rax]=old;}return Ok;}
    public static int PopBack(CpuContext c,int b,int n){var s=c[CpuRegister.Rdi];if(s==0||!R(c,s+(ulong)b,out var begin)||!R(c,s+(ulong)b+16,out var end))return Fault(c);if(end!=begin){end=unchecked(end-(ulong)n);if(!W(c,s+(ulong)b+16,end))return Fault(c);}c[CpuRegister.Rax]=end;return Ok;}
}
