// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.Core.Cpu;
using SharpEmu.HLE;
using SharpEmu.Libs.Kernel;
using System;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_APR_PAYLOAD_TRUTH_V1_7_5
	//
	// Evidence-only revision. It preserves the V1.7.4 import-dispatch hooks and
	// changes no HLE result, command-buffer record, file offset, destination, or
	// guest memory.
	//
	// It samples up to 64 bytes from R8 before and after
	// sceAmprAprCommandBufferReadFile. This proves whether a successful return
	// also materializes file bytes into guest memory.

	private const string DbfzAprReadNid = "mQ16-QdKv7k";
	private const uint DbfzPakChunk0AprId = 0x1F7DF498u;
	private const uint DbfzPakChunk1AprId = 0x9F531C5Fu;
	private const int DbfzGenericAprReadTraceLimit = 64;
	private const int DbfzPayloadSampleBytes = 64;

	private static int _dbfzAprReadTotalBefore;
	private static int _dbfzAprReadPak0Before;
	private static int _dbfzAprReadPak1Before;
	private static int _dbfzAprReadPak0After;
	private static int _dbfzAprReadPak1After;

	[ThreadStatic]
	private static int _dbfzAprReadThreadSequence;

	[ThreadStatic]
	private static int _dbfzAprReadThreadPakIndex;

	[ThreadStatic]
	private static ulong _dbfzAprReadThreadFileId;

	[ThreadStatic]
	private static ulong _dbfzAprReadThreadDestination;

	[ThreadStatic]
	private static ulong _dbfzAprReadThreadRequested;

	[ThreadStatic]
	private static bool _dbfzAprReadBeforeReadable;

	[ThreadStatic]
	private static ulong _dbfzAprReadBeforeHash;

	[ThreadStatic]
	private static int _dbfzAprReadBeforeSampleLength;

	private static void TraceDragonBallFighterZAprReadFile(
		string nid,
		CpuContext ctx,
		bool before,
		int returnValue)
	{
		// SHARPEMU_TITLE_SCOPED_DBFZ_APR_TRACE_V73_0_13
		// V73.6 proved this DBFZ evidence hook was sampling every Demon's Souls
		// APR read because both games share sceAmprAprCommandBufferReadFile.
		if (!KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA09790"))
		{
			return;
		}

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

			var destination = ctx[CpuRegister.R8];
			var requested = ctx[CpuRegister.R9];
			var sampleLength = unchecked((int)Math.Min(
				(ulong)DbfzPayloadSampleBytes,
				requested));

			_dbfzAprReadThreadSequence = sequence;
			_dbfzAprReadThreadPakIndex = pakIndex;
			_dbfzAprReadThreadFileId = fileId;
			_dbfzAprReadThreadDestination = destination;
			_dbfzAprReadThreadRequested = requested;
			_dbfzAprReadBeforeSampleLength = sampleLength;

			_dbfzAprReadBeforeReadable = TryHashGuestSample(
				ctx,
				destination,
				sampleLength,
				out _dbfzAprReadBeforeHash,
				out _);

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
				"[LOADER][WARN] dbfz.apr_payload before " +
				$"seq={sequence} pak={pakIndex} id=0x{fileId:X8} " +
				$"dest=0x{destination:X16} req={requested} " +
				$"sample={sampleLength} readable={_dbfzAprReadBeforeReadable} " +
				$"hash=0x{_dbfzAprReadBeforeHash:X16} " +
				$"rdi=0x{ctx[CpuRegister.Rdi]:X16} " +
				$"rsi=0x{ctx[CpuRegister.Rsi]:X16} " +
				$"rdx=0x{ctx[CpuRegister.Rdx]:X16}");
			return;
		}

		var currentSequence = _dbfzAprReadThreadSequence;
		var currentPakIndex = _dbfzAprReadThreadPakIndex;
		var currentFileId = unchecked((uint)_dbfzAprReadThreadFileId);
		var destinationAfter = _dbfzAprReadThreadDestination;
		var requestedAfter = _dbfzAprReadThreadRequested;
		var sampleLengthAfter = _dbfzAprReadBeforeSampleLength;

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

		var afterReadable = TryHashGuestSample(
			ctx,
			destinationAfter,
			sampleLengthAfter,
			out var afterHash,
			out var afterHex);

		var changed =
			afterReadable &&
			(!_dbfzAprReadBeforeReadable ||
			 afterHash != _dbfzAprReadBeforeHash);

		if (currentPakIndex < 0 &&
			currentSequence > DbfzGenericAprReadTraceLimit)
		{
			return;
		}

		Console.Error.WriteLine(
			"[LOADER][WARN] dbfz.apr_payload after " +
			$"seq={currentSequence} pak={currentPakIndex} id=0x{currentFileId:X8} " +
			$"result={returnValue} rax=0x{ctx[CpuRegister.Rax]:X16} " +
			$"dest=0x{destinationAfter:X16} req={requestedAfter} " +
			$"sample={sampleLengthAfter} before_readable={_dbfzAprReadBeforeReadable} " +
			$"after_readable={afterReadable} changed={changed} " +
			$"before_hash=0x{_dbfzAprReadBeforeHash:X16} " +
			$"after_hash=0x{afterHash:X16} after_hex={afterHex} " +
			$"totals={Volatile.Read(ref _dbfzAprReadTotalBefore)} " +
			$"pak0={Volatile.Read(ref _dbfzAprReadPak0Before)}/" +
			$"{Volatile.Read(ref _dbfzAprReadPak0After)} " +
			$"pak1={Volatile.Read(ref _dbfzAprReadPak1Before)}/" +
			$"{Volatile.Read(ref _dbfzAprReadPak1After)}");
	}

	private static bool TryHashGuestSample(
		CpuContext ctx,
		ulong address,
		int length,
		out ulong hash,
		out string preview)
	{
		const ulong FnvOffsetBasis = 14695981039346656037UL;
		const ulong FnvPrime = 1099511628211UL;

		hash = 0;
		preview = "-";

		if (length <= 0)
		{
			hash = FnvOffsetBasis;
			preview = string.Empty;
			return true;
		}

		if (address == 0 ||
			length > DbfzPayloadSampleBytes)
		{
			return false;
		}

		Span<byte> sample = stackalloc byte[DbfzPayloadSampleBytes];
		var slice = sample[..length];

		if (!ctx.Memory.TryRead(address, slice))
		{
			return false;
		}

		var current = FnvOffsetBasis;
		for (var index = 0; index < slice.Length; index++)
		{
			current ^= slice[index];
			current *= FnvPrime;
		}

		hash = current;

		var previewLength = Math.Min(length, 16);
		Span<char> chars = stackalloc char[previewLength * 2];
		const string Hex = "0123456789ABCDEF";

		for (var index = 0; index < previewLength; index++)
		{
			var value = slice[index];
			chars[index * 2] = Hex[value >> 4];
			chars[index * 2 + 1] = Hex[value & 0x0F];
		}

		preview = new string(chars);
		return true;
	}
}
