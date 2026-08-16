// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_NULL_SHARED_PTR_ASSIGN_COMPAT_V1_6_8
	//
	// Dragon Ball FighterZ PPSA09790 / 01.000.010:
	//
	//   0x800C6BED0 -> 0x800C7F1E0 copies source+0xC0/+0xC8
	//   0x800C6BF06 -> 0x800C7F220 copies source+0xD0/+0xD8
	//   0x800C222F0 computes sourceObject+0x40
	//
	// When sourceObject is NULL the latter yields the small non-pointer 0x40,
	// which reaches 0x80001130E as RSI and faults on `mov rax,[rsi]`.
	//
	// The compatibility rewrite below preserves the original self-assignment
	// early-out and normal copy path. It adds exactly one extra early-out:
	// RSI == 0x40. The on-disk eboot is never modified.
	private unsafe void TryPatchDragonBallFighterZNullSharedPtrAssignCompat()
	{
		if (string.Equals(
				Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_NULL_SHARED_PTR_COMPAT"),
				"0",
				StringComparison.Ordinal))
		{
			return;
		}

		const ulong patchAddress = 0x0000000800011300UL;
		const ulong callerAddress = 0x0000000800C6BE80UL;
		const ulong resolverC0Address = 0x0000000800C7F1E0UL;
		const ulong resolverD0Address = 0x0000000800C7F220UL;

		byte[] original =
		{
			0x55, 0x48, 0x89, 0xE5, 0x53, 0x50, 0x48, 0x89,
			0xFB, 0x48, 0x39, 0xF7, 0x74, 0x17, 0x48, 0x8B,
			0x06, 0x8B, 0x56, 0x10, 0x8B, 0x4B, 0x14, 0x48,
			0x89, 0xDF, 0x45, 0x31, 0xC0, 0x48, 0x89, 0xC6,
			0xE8, 0x7B, 0xF5, 0xFF, 0xFF, 0x48, 0x89, 0xD8,
			0x48, 0x83, 0xC4, 0x08, 0x5B, 0x5D, 0xC3, 0xCC
		};

		// Same semantics as the original helper, with:
		//
		//     cmp rsi,0x40
		//     je  return_destination
		//
		// inserted before the dereference. RBP is left untouched instead of
		// being pushed/popped; RBX is still preserved and the nested call keeps
		// SysV stack alignment.
		byte[] replacement =
		{
			0x53,                                           // push rbx
			0x48, 0x89, 0xFB,                               // mov rbx,rdi
			0x48, 0x39, 0xF7,                               // cmp rdi,rsi
			0x74, 0x1D,                                     // je  +0x1D -> return
			0x48, 0x83, 0xFE, 0x40,                         // cmp rsi,0x40
			0x74, 0x17,                                     // je  +0x17 -> return
			0x48, 0x8B, 0x06,                               // mov rax,[rsi]
			0x8B, 0x56, 0x10,                               // mov edx,[rsi+0x10]
			0x8B, 0x4B, 0x14,                               // mov ecx,[rbx+0x14]
			0x48, 0x89, 0xDF,                               // mov rdi,rbx
			0x45, 0x31, 0xC0,                               // xor r8d,r8d
			0x48, 0x89, 0xC6,                               // mov rsi,rax
			0xE8, 0x7A, 0xF5, 0xFF, 0xFF,                   // call 0x8000108A0
			0x48, 0x89, 0xD8,                               // mov rax,rbx
			0x5B,                                           // pop rbx
			0xC3,                                           // ret
			0xCC, 0xCC, 0xCC, 0xCC, 0xCC
		};

		byte[] callerSignature =
		{
			0x55, 0x48, 0x89, 0xE5, 0x41, 0x57, 0x41, 0x56,
			0x53, 0x48, 0x83, 0xEC, 0x18, 0x4C, 0x8B, 0x3D,
			0xF4, 0x2C, 0x4F, 0x05, 0x48, 0x89, 0xFB
		};

		byte[] resolverC0Signature =
		{
			0x55, 0x48, 0x89, 0xE5, 0x53, 0x50,
			0xC5, 0xF8, 0x10, 0x86, 0xC0, 0x00, 0x00, 0x00
		};

		byte[] resolverD0Signature =
		{
			0x55, 0x48, 0x89, 0xE5, 0x53, 0x50,
			0xC5, 0xF8, 0x10, 0x86, 0xD0, 0x00, 0x00, 0x00
		};

		if (!DragonBallFighterZCompatExecutableRange(patchAddress, original.Length) ||
			!DragonBallFighterZCompatExecutableRange(callerAddress, callerSignature.Length) ||
			!DragonBallFighterZCompatExecutableRange(resolverC0Address, resolverC0Signature.Length) ||
			!DragonBallFighterZCompatExecutableRange(resolverD0Address, resolverD0Signature.Length))
		{
			return;
		}

		if (DragonBallFighterZCompatMatches(patchAddress, replacement))
		{
			Console.Error.WriteLine(
				"[LOADER][TRACE] dbfz.null_shared_ptr_assign_compat already-installed " +
				"patch=0x0000000800011300 sentinel=0x40");
			return;
		}

		if (!DragonBallFighterZCompatMatches(patchAddress, original) ||
			!DragonBallFighterZCompatMatches(callerAddress, callerSignature) ||
			!DragonBallFighterZCompatMatches(resolverC0Address, resolverC0Signature) ||
			!DragonBallFighterZCompatMatches(resolverD0Address, resolverD0Signature))
		{
			return;
		}

		uint oldProtect = 0;
		if (!VirtualProtect(
				(void*)patchAddress,
				(nuint)replacement.Length,
				64u,
				&oldProtect))
		{
			Console.Error.WriteLine(
				"[LOADER][WARN] dbfz.null_shared_ptr_assign_compat protect-failed " +
				"patch=0x0000000800011300");
			return;
		}

		try
		{
			byte* destination = (byte*)patchAddress;
			for (int i = 0; i < replacement.Length; i++)
			{
				destination[i] = replacement[i];
			}
		}
		finally
		{
			uint ignoredProtect = 0;
			_ = VirtualProtect(
				(void*)patchAddress,
				(nuint)replacement.Length,
				oldProtect,
				&ignoredProtect);
			_ = FlushInstructionCache(
				GetCurrentProcess(),
				(void*)patchAddress,
				(nuint)replacement.Length);
		}

		Console.Error.WriteLine(
			"[LOADER][WARN] dbfz.null_shared_ptr_assign_compat installed " +
			"patch=0x0000000800011300 sentinel=0x40 " +
			"normal_copy=preserved self_assign=preserved eboot_file=untouched");
	}

	private static unsafe bool DragonBallFighterZCompatMatches(
		ulong address,
		byte[] expected)
	{
		byte* current = (byte*)address;
		for (int i = 0; i < expected.Length; i++)
		{
			if (current[i] != expected[i])
			{
				return false;
			}
		}

		return true;
	}

	private static unsafe bool DragonBallFighterZCompatExecutableRange(
		ulong address,
		int length)
	{
		if (length <= 0)
		{
			return false;
		}

		if (VirtualQuery(
				(void*)address,
				out var memoryInfo,
				(nuint)sizeof(MEMORY_BASIC_INFORMATION64)) == 0 ||
			memoryInfo.RegionSize == 0)
		{
			return false;
		}

		ulong endAddress = address + (ulong)length;
		ulong regionEnd = memoryInfo.BaseAddress + memoryInfo.RegionSize;

		if (endAddress < address ||
			regionEnd < memoryInfo.BaseAddress ||
			address < memoryInfo.BaseAddress ||
			endAddress > regionEnd)
		{
			return false;
		}

		uint protection = memoryInfo.Protect & 0xFF;
		bool committed =
			memoryInfo.State == 4096 &&
			(memoryInfo.Protect & PAGE_GUARD) == 0 &&
			protection != PAGE_NOACCESS;
		bool executable =
			protection == PAGE_EXECUTE ||
			protection == PAGE_EXECUTE_READ ||
			protection == PAGE_EXECUTE_READWRITE ||
			protection == PAGE_EXECUTE_WRITECOPY;

		return committed && executable;
	}
}
