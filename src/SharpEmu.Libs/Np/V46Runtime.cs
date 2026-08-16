// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V46: expanded IntrusivePtr ABI implementation derived from captured libSceNpCppWebApi.prx.

using System.Buffers.Binary;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Np;

internal static class NpCppWebApiIntrusivePtrV46Runtime
{
    // V46 ABI marker: IntrusivePtr = { object*, deleter, LibContext* } (24 bytes), pointee refcount int32 at +0.
    private const int StateSize = 24;
    private static readonly object RefCountGate = new();
    private static int MemoryFault(CpuContext ctx) => ctx.SetReturn(OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
    private static bool TryReadState(CpuContext ctx, ulong a, out ulong p, out ulong d, out ulong c)
    {
        Span<byte> b=stackalloc byte[StateSize];
        if(a==0 || !ctx.Memory.TryRead(a,b)){p=d=c=0;return false;}
        p=BinaryPrimitives.ReadUInt64LittleEndian(b[..8]);
        d=BinaryPrimitives.ReadUInt64LittleEndian(b.Slice(8,8));
        c=BinaryPrimitives.ReadUInt64LittleEndian(b.Slice(16,8));
        return true;
    }
    private static bool TryWriteState(CpuContext ctx, ulong a, ulong p, ulong d, ulong c)
    {
        if(a==0)return false;
        Span<byte> b=stackalloc byte[StateSize];
        BinaryPrimitives.WriteUInt64LittleEndian(b[..8],p);
        BinaryPrimitives.WriteUInt64LittleEndian(b.Slice(8,8),d);
        BinaryPrimitives.WriteUInt64LittleEndian(b.Slice(16,8),c);
        return ctx.Memory.TryWrite(a,b);
    }
    private static bool TryReadPointer(CpuContext ctx, ulong a, out ulong p){if(a==0){p=0;return false;}return ctx.TryReadUInt64(a,out p);}
    private static bool TryInc(CpuContext ctx, ulong p, out uint v)
    {
        v=0;if(p==0)return true;
        lock(RefCountGate){if(!ctx.TryReadUInt32(p,out var cur))return false;v=unchecked(cur+1u);return ctx.TryWriteUInt32(p,v);}
    }
    private static int Preserve(CpuContext ctx,ulong r){ctx[CpuRegister.Rax]=r;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
    public static int ConstructDefault(CpuContext ctx){var r=ctx[CpuRegister.Rax];if(!TryWriteState(ctx,ctx[CpuRegister.Rdi],0,0,0))return MemoryFault(ctx);return Preserve(ctx,r);}
    public static int ConstructCopy(CpuContext ctx)
    {
        var self=ctx[CpuRegister.Rdi];var src=ctx[CpuRegister.Rsi];
        if(!TryReadState(ctx,src,out var p,out var d,out var c)||!TryWriteState(ctx,self,p,d,c))return MemoryFault(ctx);
        if(p!=0){if(!TryInc(ctx,p,out var count))return MemoryFault(ctx);ctx[CpuRegister.Rax]=count;}else ctx[CpuRegister.Rax]=self;
        return (int)OrbisGen2Result.ORBIS_GEN2_OK;
    }
    public static int ConstructPointerContext(CpuContext ctx)
    {
        var r=ctx[CpuRegister.Rax];var p=ctx[CpuRegister.Rsi];
        if(!TryWriteState(ctx,ctx[CpuRegister.Rdi],p,0,ctx[CpuRegister.Rdx]))return MemoryFault(ctx);
        if(p!=0){if(!TryInc(ctx,p,out var count))return MemoryFault(ctx);ctx[CpuRegister.Rax]=count;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}return Preserve(ctx,r);
    }
    public static int ConstructPointerDeleterContext(CpuContext ctx)
    {
        var r=ctx[CpuRegister.Rax];var p=ctx[CpuRegister.Rsi];
        if(!TryWriteState(ctx,ctx[CpuRegister.Rdi],p,ctx[CpuRegister.Rdx],ctx[CpuRegister.Rcx]))return MemoryFault(ctx);
        if(p!=0){if(!TryInc(ctx,p,out var count))return MemoryFault(ctx);ctx[CpuRegister.Rax]=count;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}return Preserve(ctx,r);
    }
    public static int AddRef(CpuContext ctx){var r=ctx[CpuRegister.Rax];if(!TryReadPointer(ctx,ctx[CpuRegister.Rdi],out var p))return MemoryFault(ctx);if(p==0)return Preserve(ctx,r);if(!TryInc(ctx,p,out var c))return MemoryFault(ctx);ctx[CpuRegister.Rax]=c;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
    public static int Get(CpuContext ctx){if(!TryReadPointer(ctx,ctx[CpuRegister.Rdi],out var p))return MemoryFault(ctx);ctx[CpuRegister.Rax]=p;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
    public static int GetDeleter(CpuContext ctx){var s=ctx[CpuRegister.Rdi];if(s==0||!ctx.TryReadUInt64(s+8,out var v))return MemoryFault(ctx);ctx[CpuRegister.Rax]=v;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
    public static int GetRef(CpuContext ctx){if(!TryReadPointer(ctx,ctx[CpuRegister.Rdi],out var p))return MemoryFault(ctx);if(p!=0&&!TryInc(ctx,p,out _))return MemoryFault(ctx);ctx[CpuRegister.Rax]=p;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
    public static int OperatorBool(CpuContext ctx){if(!TryReadPointer(ctx,ctx[CpuRegister.Rdi],out var p))return MemoryFault(ctx);ctx[CpuRegister.Rax]=p==0?0UL:1UL;return (int)OrbisGen2Result.ORBIS_GEN2_OK;}
}
