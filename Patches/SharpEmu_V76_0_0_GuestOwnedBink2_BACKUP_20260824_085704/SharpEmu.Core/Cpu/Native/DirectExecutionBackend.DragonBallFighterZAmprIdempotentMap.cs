// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_AMPR_SEGMENTED_MAP_V1_7_8_1_1
	//
	// First preserve the original whole-range TryBackFixedRange behavior.
	//
	// If a large fixed range fails:
	//   1. accept it when the entire interval is already readable (V1.7.7);
	//   2. otherwise, for multi-page ranges only, back the interval one PS5
	//      64 KiB guest page at a time.
	//
	// The segmented path is intentionally strict:
	// - every page is verified readable after materialization;
	// - already-backed pages are preserved and counted;
	// - an unreadable page that cannot be backed makes the complete request fail.
	//
	// This handles host reservation boundaries where one VirtualAlloc/commit over
	// multiple reserved regions can fail although each constituent page can be
	// committed independently.

	private const ulong DbfzAmprGuestPageSizeV178 = 0x10000UL;

	private static bool TryEnsureDbfzAmprFixedRange(
		CpuContext ctx,
		ulong address,
		ulong length,
		out bool alreadyBacked)
	{
		alreadyBacked = false;

		if (address == 0 ||
			length == 0 ||
			ulong.MaxValue - address < length - 1)
		{
			return false;
		}

		ICpuMemory memory = ctx.Memory;
		IGuestAddressSpace? addressSpace = null;

		for (var depth = 0; depth < 4; depth++)
		{
			if (memory is IGuestAddressSpace resolved)
			{
				addressSpace = resolved;
				break;
			}

			if (memory is not ICpuMemoryWrapper wrapper ||
				wrapper.Inner is null ||
				ReferenceEquals(wrapper.Inner, memory))
			{
				break;
			}

			memory = wrapper.Inner;
		}

		if (addressSpace is null)
		{
			return false;
		}

		if (addressSpace.TryBackFixedRange(
				address,
				length,
				executable: false))
		{
			return true;
		}

		if (IsDbfzAmprRangeAlreadyBacked(
				ctx.Memory,
				address,
				length))
		{
			alreadyBacked = true;
			return true;
		}

		// A one-page failure cannot benefit from segmentation.
		if (length <= DbfzAmprGuestPageSizeV178)
		{
			return false;
		}

		if (!TryBackDbfzAmprRangeByGuestPage(
				ctx.Memory,
				addressSpace,
				address,
				length,
				out var newlyBackedPages,
				out var existingPages,
				out var failedPage))
		{
			Console.Error.WriteLine(
				"[LOADER][TRACE] ampr.dispatch_map.segmented_failed " +
				$"address=0x{address:X16} size=0x{length:X} " +
				$"new_pages={newlyBackedPages} existing_pages={existingPages} " +
				$"failed_page=0x{failedPage:X16}");
			return false;
		}

		Console.Error.WriteLine(
			"[LOADER][TRACE] ampr.dispatch_map.segmented_materialized " +
			$"address=0x{address:X16} size=0x{length:X} " +
			$"new_pages={newlyBackedPages} existing_pages={existingPages}");

		return true;
	}

	private static bool TryBackDbfzAmprRangeByGuestPage(
		ICpuMemory memory,
		IGuestAddressSpace addressSpace,
		ulong address,
		ulong length,
		out int newlyBackedPages,
		out int existingPages,
		out ulong failedPage)
	{
		newlyBackedPages = 0;
		existingPages = 0;
		failedPage = 0;

		ulong offset = 0;

		while (offset < length)
		{
			var pageAddress = address + offset;
			var remaining = length - offset;
			var pageLength = Math.Min(
				DbfzAmprGuestPageSizeV178,
				remaining);

			if (IsDbfzAmprPageBacked(
					memory,
					pageAddress,
					pageLength))
			{
				existingPages++;
			}
			else
			{
				if (!addressSpace.TryBackFixedRange(
						pageAddress,
						pageLength,
						executable: false))
				{
					// Another overlapping materializer may have completed the
					// page between the first probe and TryBackFixedRange.
					if (!IsDbfzAmprPageBacked(
							memory,
							pageAddress,
							pageLength))
					{
						failedPage = pageAddress;
						return false;
					}

					existingPages++;
				}
				else
				{
					if (!IsDbfzAmprPageBacked(
							memory,
							pageAddress,
							pageLength))
					{
						failedPage = pageAddress;
						return false;
					}

					newlyBackedPages++;
				}
			}

			offset += pageLength;
		}

		return true;
	}

	private static bool IsDbfzAmprRangeAlreadyBacked(
		ICpuMemory memory,
		ulong address,
		ulong length)
	{
		if (length == 0 ||
			ulong.MaxValue - address < length - 1)
		{
			return false;
		}

		ulong offset = 0;

		while (offset < length)
		{
			var remaining = length - offset;
			var pageLength = Math.Min(
				DbfzAmprGuestPageSizeV178,
				remaining);

			if (!IsDbfzAmprPageBacked(
					memory,
					address + offset,
					pageLength))
			{
				return false;
			}

			offset += pageLength;
		}

		return true;
	}

	private static bool IsDbfzAmprPageBacked(
		ICpuMemory memory,
		ulong address,
		ulong length)
	{
		if (length == 0 ||
			ulong.MaxValue - address < length - 1)
		{
			return false;
		}

		Span<byte> probe = stackalloc byte[1];

		return memory.TryRead(address, probe) &&
			memory.TryRead(address + length - 1, probe);
	}
}
