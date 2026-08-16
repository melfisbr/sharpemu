// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Core.Cpu;
using SharpEmu.HLE;
using System;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_APR_READ_TRACE_V1_7_4_1_1_1
	//
	// V1.7.4.1: compile correction — CpuContext is defined in SharpEmu.HLE.
	// Instrumentation only. No guest semantics are changed.
	//
	// DBFZ V1.7.3 resolved:
	//   pakchunk0-ps5.pak -> APR id 0x1F7DF498
	//   pakchunk1-ps5.pak -> APR id 0x9F531C5F
	//
	// Generated export metadata maps:
	//   mQ16-QdKv7k -> sceAmprAprCommandBufferReadFile
	//
	// Historical call evidence shows the file id in RCX for this export.
	// We log all calls for the two DBFZ PAK ids and only the first 64 generic
	// ReadFile calls so a bad/non-PAK stream cannot flood the diagnostic log.

	private const string DbfzAprReadNid = "mQ16-QdKv7k";
	private const uint DbfzPakChunk0AprId = 0x1F7DF498u;
	private const uint DbfzPakChunk1AprId = 0x9F531C5Fu;
	private const int DbfzGenericAprReadTraceLimit = 64;

	private static int _dbfzAprReadTotalBefore;
	private static int _dbfzAprReadPak0Before;
	private static int _dbfzAprReadPak1Before;
	private static int _dbfzAprReadPak0After;
	private static int _dbfzAprReadPak1After;

	[ThreadStatic]
	private static int _dbfzAprReadThreadSequence;

	[ThreadStatic]
	private static int _dbfzAprReadThreadPakIndex;

	private static void TraceDragonBallFighterZAprReadFile(
		string nid,
		CpuContext ctx,
		bool before,
		int returnValue)
	{
		if (!string.Equals(
				nid,
				DbfzAprReadNid,
				StringComparison.Ordinal))
		{
			return;
		}

		var fileId = unchecked((uint)ctx[CpuRegister.Rcx]);
		var pakIndex =
			fileId == DbfzPakChunk0AprId ? 0 :
			fileId == DbfzPakChunk1AprId ? 1 :
			-1;

		if (before)
		{
			var sequence = Interlocked.Increment(
				ref _dbfzAprReadTotalBefore);

			_dbfzAprReadThreadSequence = sequence;
			_dbfzAprReadThreadPakIndex = pakIndex;

			if (pakIndex == 0)
			{
				_ = Interlocked.Increment(
					ref _dbfzAprReadPak0Before);
			}
			else if (pakIndex == 1)
			{
				_ = Interlocked.Increment(
					ref _dbfzAprReadPak1Before);
			}

			if (pakIndex < 0 &&
				sequence > DbfzGenericAprReadTraceLimit)
			{
				return;
			}

			Console.Error.WriteLine(
				"[LOADER][WARN] dbfz.apr_read before " +
				$"seq={sequence} pak={pakIndex} id=0x{fileId:X8} " +
				$"rdi=0x{ctx[CpuRegister.Rdi]:X16} " +
				$"rsi=0x{ctx[CpuRegister.Rsi]:X16} " +
				$"rdx=0x{ctx[CpuRegister.Rdx]:X16} " +
				$"rcx=0x{ctx[CpuRegister.Rcx]:X16} " +
				$"r8=0x{ctx[CpuRegister.R8]:X16} " +
				$"r9=0x{ctx[CpuRegister.R9]:X16}");
			return;
		}

		var currentSequence = _dbfzAprReadThreadSequence;
		var currentPakIndex = _dbfzAprReadThreadPakIndex;

		if (currentPakIndex == 0)
		{
			_ = Interlocked.Increment(
				ref _dbfzAprReadPak0After);
		}
		else if (currentPakIndex == 1)
		{
			_ = Interlocked.Increment(
				ref _dbfzAprReadPak1After);
		}

		if (currentPakIndex < 0 &&
			currentSequence > DbfzGenericAprReadTraceLimit)
		{
			return;
		}

		Console.Error.WriteLine(
			"[LOADER][WARN] dbfz.apr_read after " +
			$"seq={currentSequence} pak={currentPakIndex} id=0x{fileId:X8} " +
			$"result={returnValue} rax=0x{ctx[CpuRegister.Rax]:X16} " +
			$"totals={Volatile.Read(ref _dbfzAprReadTotalBefore)} " +
			$"pak0={Volatile.Read(ref _dbfzAprReadPak0Before)}/" +
			$"{Volatile.Read(ref _dbfzAprReadPak0After)} " +
			$"pak1={Volatile.Read(ref _dbfzAprReadPak1Before)}/" +
			$"{Volatile.Read(ref _dbfzAprReadPak1After)}");
	}
}
