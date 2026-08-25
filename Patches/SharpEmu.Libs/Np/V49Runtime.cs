// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V49: deterministic primitive service-field extension using the V44-validated SysV ABI policy.
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using SharpEmu.HLE;
namespace SharpEmu.Libs.Np;
internal static class NpCppWebApiServiceScalarV49Runtime
{
    // V49 ABI marker: primitive service sidecar families are class-disjoint from V44 implemented classes.
    private readonly record struct ObjectKey(ulong Address,int TypeId);
    private sealed class ObjectState { public object Gate { get; }=new(); public Dictionary<int,ulong> Fields { get; }=new(); public ulong LibContext { get; set; } }
    internal enum ValueSource { U8Ref,U32Ref,U64Ref,Register }
    internal enum ReturnKind { Bool,U32,U64,Float32,Float64 }
    private static readonly ConditionalWeakTable<object,ConcurrentDictionary<ObjectKey,ObjectState>> States=new();
    private static ConcurrentDictionary<ObjectKey,ObjectState> Map(CpuContext c)=>States.GetValue(c.Memory,static _=>new ConcurrentDictionary<ObjectKey,ObjectState>());
    private static ObjectState Get(CpuContext c,ulong a,int t)=>Map(c).GetOrAdd(new ObjectKey(a,t),static _=>new ObjectState());
    private static ObjectState? TryGet(CpuContext c,ulong a,int t){if(a==0)return null;return Map(c).TryGetValue(new ObjectKey(a,t),out var s)?s:null;}
    private static bool Read(CpuContext c,ulong a,int n,out ulong v){v=0;if(a==0)return false;Span<byte>b=stackalloc byte[8];var s=b[..n];if(!c.Memory.TryRead(a,s))return false;v=n switch{1=>s[0],4=>BinaryPrimitives.ReadUInt32LittleEndian(s),8=>BinaryPrimitives.ReadUInt64LittleEndian(s),_=>0};return n is 1 or 4 or 8;}
    private static int Ok=>(int)OrbisGen2Result.ORBIS_GEN2_OK;
    public static int Construct(CpuContext c,int t){var a=c[CpuRegister.Rdi];if(a==0)return Ok;var s=Get(c,a,t);lock(s.Gate){s.Fields.Clear();s.LibContext=c[CpuRegister.Rsi];}return Ok;}
    public static int Destruct(CpuContext c,int t){var a=c[CpuRegister.Rdi];if(a!=0)Map(c).TryRemove(new ObjectKey(a,t),out _);return Ok;}
    public static int SetValue(CpuContext c,int t,int f,ValueSource src,bool norm)
    {
        var a=c[CpuRegister.Rdi];if(a==0)return Ok;ulong raw;
        switch(src){case ValueSource.U8Ref:if(!Read(c,c[CpuRegister.Rsi],1,out raw))return Ok;break;case ValueSource.U32Ref:if(!Read(c,c[CpuRegister.Rsi],4,out raw))return Ok;break;case ValueSource.U64Ref:if(!Read(c,c[CpuRegister.Rsi],8,out raw))return Ok;break;case ValueSource.Register:raw=c[CpuRegister.Rsi];break;default:return Ok;}
        if(norm)raw=raw==0?0UL:1UL;var s=Get(c,a,t);lock(s.Gate)s.Fields[f]=raw;return Ok;
    }
    public static int GetValue(CpuContext c,int t,int f,ReturnKind k)
    {
        ulong raw=0;var s=TryGet(c,c[CpuRegister.Rdi],t);if(s is not null){lock(s.Gate)_=s.Fields.TryGetValue(f,out raw);}
        switch(k){case ReturnKind.Bool:c[CpuRegister.Rax]=raw==0?0UL:1UL;break;case ReturnKind.U32:c[CpuRegister.Rax]=raw&uint.MaxValue;break;case ReturnKind.U64:c[CpuRegister.Rax]=raw;break;case ReturnKind.Float32:c.SetXmmRegister(0,raw&uint.MaxValue,0);break;case ReturnKind.Float64:c.SetXmmRegister(0,raw,0);break;}return Ok;
    }
    public static int IsSet(CpuContext c,int t,int f){var set=false;var s=TryGet(c,c[CpuRegister.Rdi],t);if(s is not null){lock(s.Gate)set=s.Fields.ContainsKey(f);}c[CpuRegister.Rax]=set?1UL:0UL;return Ok;}
    public static int Unset(CpuContext c,int t,int f){var s=TryGet(c,c[CpuRegister.Rdi],t);if(s is not null){lock(s.Gate)s.Fields.Remove(f);}return Ok;}
}
