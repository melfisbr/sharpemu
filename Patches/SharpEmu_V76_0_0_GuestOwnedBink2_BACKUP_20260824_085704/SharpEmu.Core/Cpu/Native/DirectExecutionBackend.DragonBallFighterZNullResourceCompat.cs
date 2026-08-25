// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_NULL_RESOURCE_FALLBACK_V1_7_0
	//
	// DBFZ PPSA09790 01.000.010.
	//
	// V1.6.9 runtime:
	//   RIP    = 0x800C22364
	//   RDI    = 0
	//   target = 0
	//
	// Eboot:
	//   0x800C22360 push rbp
	//   0x800C22361 mov rbp,rsp
	//   0x800C22364 mov rdi,[rdi]
	//   0x800C22367 pop rbp
	//   0x800C22368 jmp 0x800C22370
	//
	// Immediate caller:
	//   0x800C56550 mov rdi,r13
	//   0x800C56553 call 0x800C22360
	//
	// R13 is resolved from a singleton/shared resource field; the failing run
	// reached this wrapper with R13 == NULL.
	//
	// Compatibility:
	//   valid RDI -> original dereference + tail-call to 0x800C22370
	//   NULL RDI  -> return a process-local zeroed fallback resource
	//
	// The fallback is 0x1000 zeroed bytes. The immediate caller reads through
	// offsets 0x94 and 0xA4, so the page is intentionally large enough to
	// represent an empty resource without touching unmapped low memory.
	private static nint _dragonBallFighterZNullResourceFallbackPage;
	private static nint _dragonBallFighterZNullResourceFallbackStub;
	private static int _dragonBallFighterZNullResourceFallbackInstallState;

	private unsafe void TryPatchDragonBallFighterZNullResourceFallback()
	{
		if (string.Equals(
				Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_NULL_RESOURCE_FALLBACK"),
				"0",
				StringComparison.Ordinal))
		{
			return;
		}

		const ulong patchAddress = 0x0000000800C22360UL;
		const ulong normalTarget = 0x0000000800C22370UL;

		byte[] original =
		{
			0x55,                         // push rbp
			0x48, 0x89, 0xE5,             // mov rbp,rsp
			0x48, 0x8B, 0x3F,             // mov rdi,[rdi]
			0x5D,                         // pop rbp
			0xE9, 0x03, 0x00, 0x00, 0x00 // jmp 0x800C22370
		};

		if (!DragonBallFighterZNullResourceExecutableRange(
				patchAddress,
				original.Length))
		{
			return;
		}

		nint existingStub = Volatile.Read(ref _dragonBallFighterZNullResourceFallbackStub);
		if (existingStub != 0 &&
			DragonBallFighterZNullResourceEntryRedirectsTo(patchAddress, existingStub))
		{
			Console.Error.WriteLine(
				"[LOADER][TRACE] dbfz.null_resource_fallback already-installed " +
				"patch=0x0000000800C22360");
			return;
		}

		if (!DragonBallFighterZNullResourceMatches(patchAddress, original))
		{
			return;
		}

		if (Interlocked.CompareExchange(
				ref _dragonBallFighterZNullResourceFallbackInstallState,
				1,
				0) != 0)
		{
			return;
		}

		try
		{
			void* fallback = VirtualAlloc(
				null,
				(nuint)4096,
				12288u,
				4u); // PAGE_READWRITE

			if (fallback == null)
			{
				throw new InvalidOperationException(
					"VirtualAlloc failed for DBFZ null-resource fallback page.");
			}

			void* stubMemory = VirtualAlloc(
				null,
				(nuint)4096,
				12288u,
				64u); // PAGE_EXECUTE_READWRITE while emitting

			if (stubMemory == null)
			{
				throw new InvalidOperationException(
					"VirtualAlloc failed for DBFZ null-resource fallback stub.");
			}

			// Stub:
			//   test rdi,rdi
			//   jne  normal
			//   mov  rax,<fallback>
			//   ret
			// normal:
			//   mov  rdi,[rdi]
			//   mov  rax,0x800C22370
			//   jmp  rax
			byte[] stub = new byte[35];
			int offset = 0;

			stub[offset++] = 0x48;
			stub[offset++] = 0x85;
			stub[offset++] = 0xFF; // test rdi,rdi

			stub[offset++] = 0x0F;
			stub[offset++] = 0x85;
			stub[offset++] = 0x0B;
			stub[offset++] = 0x00;
			stub[offset++] = 0x00;
			stub[offset++] = 0x00; // jne normal (+11)

			stub[offset++] = 0x48;
			stub[offset++] = 0xB8;
			DragonBallFighterZNullResourceWriteUInt64(
				stub,
				ref offset,
				unchecked((ulong)(nint)fallback));
			stub[offset++] = 0xC3; // ret

			stub[offset++] = 0x48;
			stub[offset++] = 0x8B;
			stub[offset++] = 0x3F; // mov rdi,[rdi]

			stub[offset++] = 0x48;
			stub[offset++] = 0xB8;
			DragonBallFighterZNullResourceWriteUInt64(
				stub,
				ref offset,
				normalTarget);

			stub[offset++] = 0xFF;
			stub[offset++] = 0xE0; // jmp rax

			if (offset != stub.Length)
			{
				throw new InvalidOperationException(
					"DBFZ null-resource fallback stub length mismatch.");
			}

			byte* stubDestination = (byte*)stubMemory;
			for (int i = 0; i < stub.Length; i++)
			{
				stubDestination[i] = stub[i];
			}

			uint stubOldProtect = 0;
			if (!VirtualProtect(
					stubMemory,
					(nuint)4096,
					32u, // PAGE_EXECUTE_READ
					&stubOldProtect))
			{
				throw new InvalidOperationException(
					"VirtualProtect failed for DBFZ null-resource fallback stub.");
			}

			_ = FlushInstructionCache(
				GetCurrentProcess(),
				stubMemory,
				(nuint)stub.Length);

			ulong stubAddress = unchecked((ulong)(nint)stubMemory);
			byte[] redirect = new byte[12];
			redirect[0] = 0x48;
			redirect[1] = 0xB8;
			int redirectOffset = 2;
			DragonBallFighterZNullResourceWriteUInt64(
				redirect,
				ref redirectOffset,
				stubAddress);
			redirect[10] = 0xFF;
			redirect[11] = 0xE0;

			uint oldProtect = 0;
			if (!VirtualProtect(
					(void*)patchAddress,
					(nuint)redirect.Length,
					64u,
					&oldProtect))
			{
				throw new InvalidOperationException(
					"VirtualProtect failed for DBFZ null-resource entry redirect.");
			}

			try
			{
				byte* destination = (byte*)patchAddress;
				for (int i = 0; i < redirect.Length; i++)
				{
					destination[i] = redirect[i];
				}
			}
			finally
			{
				uint ignoredProtect = 0;
				_ = VirtualProtect(
					(void*)patchAddress,
					(nuint)redirect.Length,
					oldProtect,
					&ignoredProtect);
				_ = FlushInstructionCache(
					GetCurrentProcess(),
					(void*)patchAddress,
					(nuint)redirect.Length);
			}

			Volatile.Write(
				ref _dragonBallFighterZNullResourceFallbackPage,
				(nint)fallback);
			Volatile.Write(
				ref _dragonBallFighterZNullResourceFallbackStub,
				(nint)stubMemory);

			Console.Error.WriteLine(
				$"[LOADER][WARN] dbfz.null_resource_fallback installed " +
				$"patch=0x{patchAddress:X16} stub=0x{stubAddress:X16} " +
				$"fallback=0x{unchecked((ulong)(nint)fallback):X16} bytes=0x1000 " +
				"normal_path=preserved eboot_file=untouched");
		}
		catch (Exception ex)
		{
			Volatile.Write(
				ref _dragonBallFighterZNullResourceFallbackInstallState,
				0);
			Console.Error.WriteLine(
				"[LOADER][WARN] dbfz.null_resource_fallback install-failed: " +
				ex.Message);
		}
	}

	private static void DragonBallFighterZNullResourceWriteUInt64(
		byte[] destination,
		ref int offset,
		ulong value)
	{
		for (int i = 0; i < sizeof(ulong); i++)
		{
			destination[offset++] = (byte)(value >> (i * 8));
		}
	}

	private static unsafe bool DragonBallFighterZNullResourceEntryRedirectsTo(
		ulong address,
		nint stub)
	{
		byte* current = (byte*)address;
		if (current[0] != 0x48 ||
			current[1] != 0xB8 ||
			current[10] != 0xFF ||
			current[11] != 0xE0)
		{
			return false;
		}

		ulong encoded = 0;
		for (int i = 0; i < sizeof(ulong); i++)
		{
			encoded |= ((ulong)current[2 + i]) << (i * 8);
		}

		return encoded == unchecked((ulong)stub);
	}

	private static unsafe bool DragonBallFighterZNullResourceMatches(
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

	private static unsafe bool DragonBallFighterZNullResourceExecutableRange(
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

		ulong end = address + (ulong)length;
		ulong regionEnd = memoryInfo.BaseAddress + memoryInfo.RegionSize;
		if (end < address ||
			regionEnd < memoryInfo.BaseAddress ||
			address < memoryInfo.BaseAddress ||
			end > regionEnd)
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
