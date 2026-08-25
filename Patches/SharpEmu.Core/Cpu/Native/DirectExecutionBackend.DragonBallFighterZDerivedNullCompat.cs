// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_DERIVED_NULL_CONTAINER_COMPAT_V1_6_9
	//
	// DBFZ PPSA09790 01.000.010.
	//
	// Proven runtime/static chain:
	//   0x800C6BA97 -> 0x800C222F0 returns source + 0x40.
	//   source == NULL therefore becomes the sentinel 0x40.
	//   0x800C221DB is the only direct caller of 0x800C46DA0.
	//   0x800C46DAA reads [RSI+0x10].
	//   RSI == 0x40 therefore faults at address 0x50.
	//
	// The installed trampoline preserves the complete normal function.
	// Only RSI==0x40 takes a compatibility branch. That branch constructs
	// an empty destination: the original zero-16 initializer is called and
	// destination +0x10/+0x14 are also zeroed.
	private static nint _dragonBallFighterZDerivedNullContainerStub;
	private static int _dragonBallFighterZDerivedNullContainerInstallState;

	private unsafe void TryPatchDragonBallFighterZDerivedNullContainerCompat()
	{
		if (string.Equals(
				Environment.GetEnvironmentVariable("SHARPEMU_DBFZ_DERIVED_NULL_CONTAINER_COMPAT"),
				"0",
				StringComparison.Ordinal))
		{
			return;
		}

		const ulong patchAddress = 0x0000000800C46DA0UL;

		byte[] originalSignature =
		{
			0x55, 0x48, 0x89, 0xE5, 0x41, 0x57, 0x41, 0x56,
			0x53, 0x50, 0x44, 0x8B, 0x7E, 0x10, 0x49, 0x89,
			0xF6, 0x48, 0x89, 0xFB, 0xE8, 0xD7, 0x9A, 0x3C,
			0xFF
		};

		if (!DragonBallFighterZDerivedNullExecutableRange(
				patchAddress,
				originalSignature.Length))
		{
			return;
		}

		nint installedStub = Volatile.Read(ref _dragonBallFighterZDerivedNullContainerStub);
		if (installedStub != 0 &&
			DragonBallFighterZDerivedNullEntryRedirectsTo(patchAddress, installedStub))
		{
			Console.Error.WriteLine(
				"[LOADER][TRACE] dbfz.derived_null_container_compat already-installed " +
				"patch=0x0000000800C46DA0 sentinel=0x40");
			return;
		}

		if (!DragonBallFighterZDerivedNullMatches(patchAddress, originalSignature))
		{
			return;
		}

		if (Interlocked.CompareExchange(
				ref _dragonBallFighterZDerivedNullContainerInstallState,
				1,
				0) != 0)
		{
			return;
		}

		void* stubMemory = null;
		try
		{
			byte[] stub =
			{
			0x55, 0x48, 0x89, 0xE5, 0x41, 0x57, 0x41, 0x56, 0x53, 0x50, 0x48, 0x89,
			0xFB, 0x48, 0x83, 0xFE, 0x40, 0x74, 0x51, 0x44, 0x8B, 0x7E, 0x10, 0x49,
			0x89, 0xF6, 0x48, 0xB8, 0x90, 0x08, 0x01, 0x00, 0x08, 0x00, 0x00, 0x00,
			0xFF, 0xD0, 0x49, 0x8B, 0x36, 0x41, 0x8B, 0x56, 0x10, 0x48, 0x89, 0xDF,
			0x31, 0xC9, 0x45, 0x31, 0xC0, 0x48, 0xB8, 0xA0, 0x08, 0x01, 0x00, 0x08,
			0x00, 0x00, 0x00, 0xFF, 0xD0, 0x41, 0x83, 0xFF, 0x02, 0x7C, 0x0F, 0x48,
			0x89, 0xDF, 0x48, 0xB8, 0xF0, 0x6D, 0xC4, 0x00, 0x08, 0x00, 0x00, 0x00,
			0xFF, 0xD0, 0x48, 0x89, 0xD8, 0x48, 0x83, 0xC4, 0x08, 0x5B, 0x41, 0x5E,
			0x41, 0x5F, 0x5D, 0xC3, 0x48, 0x89, 0xDF, 0x48, 0xB8, 0x90, 0x08, 0x01,
			0x00, 0x08, 0x00, 0x00, 0x00, 0xFF, 0xD0, 0x48, 0xC7, 0x43, 0x10, 0x00,
			0x00, 0x00, 0x00, 0x48, 0x89, 0xD8, 0x48, 0x83, 0xC4, 0x08, 0x5B, 0x41,
			0x5E, 0x41, 0x5F, 0x5D, 0xC3,
			};

			stubMemory = VirtualAlloc(
				null,
				(nuint)4096,
				12288u,
				64u);

			if (stubMemory == null)
			{
				throw new InvalidOperationException(
					"VirtualAlloc failed for DBFZ derived-null compatibility stub.");
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
					32u,
					&stubOldProtect))
			{
				throw new InvalidOperationException(
					"VirtualProtect failed for DBFZ derived-null compatibility stub.");
			}

			_ = FlushInstructionCache(
				GetCurrentProcess(),
				stubMemory,
				(nuint)stub.Length);

			ulong stubAddress = unchecked((ulong)(nint)stubMemory);
			byte[] redirect = new byte[12];
			redirect[0] = 0x48;
			redirect[1] = 0xB8;
			for (int i = 0; i < sizeof(ulong); i++)
			{
				redirect[2 + i] = (byte)(stubAddress >> (i * 8));
			}
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
					"VirtualProtect failed for DBFZ derived-null entry redirect.");
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
				ref _dragonBallFighterZDerivedNullContainerStub,
				(nint)stubMemory);

			Console.Error.WriteLine(
				$"[LOADER][WARN] dbfz.derived_null_container_compat installed " +
				$"patch=0x{patchAddress:X16} stub=0x{stubAddress:X16} sentinel=0x40 " +
				"empty_init=zero24 normal_path=preserved eboot_file=untouched");
		}
		catch (Exception ex)
		{
			Volatile.Write(ref _dragonBallFighterZDerivedNullContainerInstallState, 0);
			Console.Error.WriteLine(
				"[LOADER][WARN] dbfz.derived_null_container_compat install-failed: " +
				ex.Message);
		}
	}

	private static unsafe bool DragonBallFighterZDerivedNullEntryRedirectsTo(
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

	private static unsafe bool DragonBallFighterZDerivedNullMatches(
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

	private static unsafe bool DragonBallFighterZDerivedNullExecutableRange(
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
