// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using SharpEmu.HLE;

namespace SharpEmu.Core.Cpu.Native;

public sealed partial class DirectExecutionBackend
{
	private sealed class SemanticTraceState
	{
		public long Sequence { get; init; }
		public long Seen { get; init; }
		public string Nid { get; init; } = string.Empty;
		public string Name { get; init; } = string.Empty;
		public string Library { get; init; } = string.Empty;
		public ulong Caller { get; init; }
		public SemanticMemorySnapshot[] MemoryBefore { get; init; } = Array.Empty<SemanticMemorySnapshot>();
	}

	private readonly record struct SemanticMemorySnapshot(
		string Register, ulong Address, bool Readable, ulong Hash,
		ulong FirstQword, ulong LastQword, int ByteCount);

	private static readonly ConcurrentDictionary<string,long> _semanticTraceSeen = new(StringComparer.Ordinal);
	private static readonly bool _semanticTraceEnabled = SemanticFlag("SHARPEMU_SEMANTIC_TRACE");
	private static readonly bool _semanticTraceFull = string.Equals(
		Environment.GetEnvironmentVariable("SHARPEMU_SEMANTIC_TRACE_MODE"),
		"full", StringComparison.OrdinalIgnoreCase);
	private static readonly string? _semanticTraceFilter =
		Environment.GetEnvironmentVariable("SHARPEMU_SEMANTIC_TRACE_FILTER");
	private static readonly int _semanticTraceMemoryBytes = SemanticInt("SHARPEMU_SEMANTIC_TRACE_MEM_BYTES",64,0,256);
	private static readonly int _semanticTraceInitial = SemanticInt("SHARPEMU_SEMANTIC_TRACE_INITIAL",64,1,4096);
	private static readonly int _semanticTraceEvery = SemanticInt("SHARPEMU_SEMANTIC_TRACE_EVERY",256,1,1000000);

	private static bool SemanticFlag(string n) =>
		string.Equals(Environment.GetEnvironmentVariable(n),"1",StringComparison.Ordinal) ||
		string.Equals(Environment.GetEnvironmentVariable(n),"true",StringComparison.OrdinalIgnoreCase);

	private static int SemanticInt(string n,int fallback,int min,int max)
	{
		return int.TryParse(Environment.GetEnvironmentVariable(n), NumberStyles.Integer,
			CultureInfo.InvariantCulture, out var v) ? Math.Clamp(v,min,max) : fallback;
	}

	private static bool ShouldSemanticTrace(string nid,string name,string library,long seen)
	{
		if (!_semanticTraceEnabled) return false;
		if (!string.IsNullOrWhiteSpace(_semanticTraceFilter) &&
			!nid.Contains(_semanticTraceFilter,StringComparison.OrdinalIgnoreCase) &&
			!name.Contains(_semanticTraceFilter,StringComparison.OrdinalIgnoreCase) &&
			!library.Contains(_semanticTraceFilter,StringComparison.OrdinalIgnoreCase))
			return false;
		return _semanticTraceFull || seen <= _semanticTraceInitial || seen % _semanticTraceEvery == 0;
	}

	private static SemanticTraceState? BeginSemanticTrace(
		CpuContext cpuContext,string nid,string? name,string? library,
		long sequence,ulong caller,nint argPackPtr)
	{
		if (!_semanticTraceEnabled) return null;
		name ??= string.Empty; library ??= string.Empty;
		var seen=_semanticTraceSeen.AddOrUpdate(nid,1,static (_,oldValue)=>oldValue+1);
		if (!ShouldSemanticTrace(nid,name,library,seen)) return null;

		var args=new[] {
			cpuContext[CpuRegister.Rdi], cpuContext[CpuRegister.Rsi],
			cpuContext[CpuRegister.Rdx], cpuContext[CpuRegister.Rcx],
			cpuContext[CpuRegister.R8], cpuContext[CpuRegister.R9]
		};
		var regs=new[] {"rdi","rsi","rdx","rcx","r8","r9"};
		var mem=new SemanticMemorySnapshot[6];
		for(var i=0;i<6;i++) mem[i]=CaptureSemanticMemory(cpuContext,regs[i],args[i],_semanticTraceMemoryBytes);

		Console.Error.WriteLine(
			$"[SEMTRACE][CALL] seq={sequence} seen={seen} nid={Token(nid)} name={Token(name)} library={Token(library)} " +
			$"caller=0x{caller:X16} rdi=0x{args[0]:X16} rsi=0x{args[1]:X16} rdx=0x{args[2]:X16} " +
			$"rcx=0x{args[3]:X16} r8=0x{args[4]:X16} r9=0x{args[5]:X16} rsp=0x{cpuContext[CpuRegister.Rsp]:X16} " +
			$"stack0=0x{ReadImportStackArgument(argPackPtr,0):X16} stack1=0x{ReadImportStackArgument(argPackPtr,1):X16} " +
			$"stack2=0x{ReadImportStackArgument(argPackPtr,2):X16} stack3=0x{ReadImportStackArgument(argPackPtr,3):X16} " +
			$"stack4=0x{ReadImportStackArgument(argPackPtr,4):X16} stack5=0x{ReadImportStackArgument(argPackPtr,5):X16}");
		foreach(var s in mem)
			if(s.Readable)
				Console.Error.WriteLine(
					$"[SEMTRACE][MEMBEFORE] seq={sequence} nid={Token(nid)} reg={s.Register} addr=0x{s.Address:X16} " +
					$"bytes={s.ByteCount} hash=0x{s.Hash:X16} first=0x{s.FirstQword:X16} last=0x{s.LastQword:X16}");
		Console.Error.Flush();
		return new SemanticTraceState {Sequence=sequence,Seen=seen,Nid=nid,Name=name,Library=library,Caller=caller,MemoryBefore=mem};
	}

	private static void EndSemanticTrace(CpuContext cpuContext,SemanticTraceState? state,ulong rax,bool resolved,string? result)
	{
		if(state is null) return;
		var retuse=CaptureReturnUse(cpuContext,state.Caller,out var code);
		Console.Error.WriteLine(
			$"[SEMTRACE][RET] seq={state.Sequence} seen={state.Seen} nid={Token(state.Nid)} rax=0x{rax:X16} " +
			$"resolved={(resolved?1:0)} result={Token(result??string.Empty)} retuse={retuse} code={code}");
		foreach(var before in state.MemoryBefore)
		{
			if(!before.Readable) continue;
			var after=CaptureSemanticMemory(cpuContext,before.Register,before.Address,before.ByteCount);
			if(!after.Readable)
			{
				Console.Error.WriteLine(
					$"[SEMTRACE][MEMAFTER] seq={state.Sequence} nid={Token(state.Nid)} reg={before.Register} " +
					$"addr=0x{before.Address:X16} readable=0 changed=unknown");
				continue;
			}
			Console.Error.WriteLine(
				$"[SEMTRACE][MEMAFTER] seq={state.Sequence} nid={Token(state.Nid)} reg={before.Register} " +
				$"addr=0x{before.Address:X16} readable=1 changed={(before.Hash!=after.Hash?1:0)} " +
				$"before=0x{before.Hash:X16} after=0x{after.Hash:X16} " +
				$"first_before=0x{before.FirstQword:X16} first_after=0x{after.FirstQword:X16}");
		}
		Console.Error.Flush();
	}

	private static SemanticMemorySnapshot CaptureSemanticMemory(CpuContext cpuContext,string reg,ulong address,int count)
	{
		if(count<=0 || address<0x10000)
			return new SemanticMemorySnapshot(reg,address,false,0,0,0,0);
		var b=new byte[count];
		if(!cpuContext.Memory.TryRead(address,b))
			return new SemanticMemorySnapshot(reg,address,false,0,0,0,count);
		ulong hash=14695981039346656037UL;
		foreach(var x in b){hash^=x;hash*=1099511628211UL;}
		return new SemanticMemorySnapshot(reg,address,true,hash,Qword(b,0),Qword(b,Math.Max(0,b.Length-8)),b.Length);
	}

	private static ulong Qword(byte[] b,int o)
	{
		if(o<0 || o+8>b.Length) return 0;
		return (ulong)b[o] | ((ulong)b[o+1]<<8) | ((ulong)b[o+2]<<16) | ((ulong)b[o+3]<<24) |
			((ulong)b[o+4]<<32) | ((ulong)b[o+5]<<40) | ((ulong)b[o+6]<<48) | ((ulong)b[o+7]<<56);
	}

	private static string CaptureReturnUse(CpuContext cpuContext,ulong caller,out string text)
	{
		text="-";
		if(caller<0x10000) return "unknown";
		var b=new byte[16];
		if(!cpuContext.Memory.TryRead(caller,b)) return "unreadable";
		text=Convert.ToHexString(b);
		if(Prefix(b,0x85,0xC0)||Prefix(b,0x48,0x85,0xC0)) return "test_return_zero";
		if(Prefix(b,0x3D)||Prefix(b,0x48,0x3D)||Prefix(b,0x83,0xF8)||Prefix(b,0x48,0x83,0xF8)) return "compare_return";
		if((b[0]>=0x70&&b[0]<=0x7F)||(Prefix(b,0x0F)&&b[1]>=0x80&&b[1]<=0x8F)) return "conditional_branch";
		if(Prefix(b,0x48,0x89)||Prefix(b,0x89)) return "store_or_move_return";
		return "other";
	}
	private static bool Prefix(byte[] b,params byte[] p)
	{
		if(b.Length<p.Length) return false;
		for(var i=0;i<p.Length;i++) if(b[i]!=p[i]) return false;
		return true;
	}
	private static string Token(string s)
	{
		if(string.IsNullOrEmpty(s)) return "-";
		var x=new StringBuilder(Math.Min(s.Length,256));
		foreach(var c in s){if(x.Length>=256) break;x.Append(char.IsWhiteSpace(c)||c=='='?'_':c);}
		return x.ToString();
	}
}
