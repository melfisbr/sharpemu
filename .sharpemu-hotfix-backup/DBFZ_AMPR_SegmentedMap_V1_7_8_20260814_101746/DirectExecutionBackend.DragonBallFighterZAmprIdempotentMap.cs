// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System;

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_DBFZ_AMPR_IDEMPOTENT_MAP_V1_7_7
	//
	// AMPR map materialization is allowed to be idempotent. TryBackFixedRange
	// can reject an already-backed interval because the host address space does
	// not permit mapping the same pages twice. That must not be converted into a
	// guest map failure when every 64 KiB guest page in the requested interval
	// is already readable.
	//
	// A partially missing interval is NOT accepted: every page start and the
	// final byte must already be readable before an overlapping/repeated map is
	// treated as success.

	private static bool TryEnsureDbfzAmprFixedRange(
		CpuContext ctx,
		ulong address,
		ulong length,
		out bool alreadyBacked)
	{
		alreadyBacked = false;

		if (address == 0 || length == 0)
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

		if (!IsDbfzAmprRangeAlreadyBacked(
				ctx.Memory,
				address,
				length))
		{
			return false;
		}

		alreadyBacked = true;
		return true;
	}

	private static bool IsDbfzAmprRangeAlreadyBacked(
		ICpuMemory memory,
		ulong address,
		ulong length)
	{
		const ulong GuestPageSize = 0x10000UL;

		if (length == 0 ||
			ulong.MaxValue - address < length - 1)
		{
			return false;
		}

		Span<byte> probe = stackalloc byte[1];

		ulong offset = 0;
		while (offset < length)
		{
			if (!memory.TryRead(address + offset, probe))
			{
				return false;
			}

			var remaining = length - offset;
			if (remaining <= GuestPageSize)
			{
				break;
			}

			offset += GuestPageSize;
		}

		var lastAddress = address + length - 1;
		if (!memory.TryRead(lastAddress, probe))
		{
			return false;
		}

		return true;
	}
}
