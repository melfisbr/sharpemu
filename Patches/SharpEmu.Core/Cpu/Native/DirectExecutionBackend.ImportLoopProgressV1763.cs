// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.Core.Cpu.Native;

public sealed unsafe partial class DirectExecutionBackend
{
	// SHARPEMU_IMPORT_LOOP_UNLOCK_BOUNDARY_V1_7_6_3
	//
	// Keep the original IsImportLoopGuardBoundary implementation untouched.
	// This companion classification is OR'ed into ImportStubEntry.IsLoopGuardBoundary
	// during SetupImportStubs.
	//
	// These are already-resolved synchronization exports. Reaching unlock means
	// the guest left a critical section and therefore made observable forward
	// progress; it must reset synthetic import-pattern history just like the
	// existing sleep/cond-wait progress boundaries do.
	private static bool IsSynchronizationProgressBoundaryV1763(string nid) =>
		nid is
			"tn3VlD0hG60" or // scePthreadMutexUnlock
			"2Z+PpY6CaJg" or // pthread_mutex_unlock
			"EgmLo6EWgso" or // scePthreadRwlockUnlock
			"+L98PIbGttk";   // pthread_rwlock_unlock
}
