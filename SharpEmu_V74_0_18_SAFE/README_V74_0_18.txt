SharpEmu V74.0.18 SAFE — Demon's Souls native memcpy + native-scale A/B

WHY THIS PACKAGE EXISTS
- V74.0.17 reached 33,554,432 managed import calls before the first startup movie.
- Every 8,388,608-call checkpoint identified NID Q3VBxCXhUHs, which is libc memcpy.
- DirectExecutionBackend already contains a native intrinsic for Q3VBxCXhUHs, but IsHlePreferredNid blocks it before intrinsic selection.
- V74.0.17 also forced SHARPEMU_RENDER_SCALE=0.25; the presented guest image was 960x540 and the visible Sony/PlayStation content appeared tiny/shifted.

WHAT V74.0.18 CHANGES
1. Adds an opt-in runtime exception to the HLE-preferred guard for Q3VBxCXhUHs only. Default remains unchanged.
2. RUN_4 enables SHARPEMU_NATIVE_MEMCPY_INTRINSIC=1 only for this Demon's Souls run.
3. Restores SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC=1 because the V74.0.17 pthread A/B did not improve startup.
4. Restores SHARPEMU_RENDER_SCALE=1.0 for a correctness baseline and records first/guest presented dimensions.
5. Leaves DCC history disabled and preserves V74.0.15 large-array single-flight/snapshot reuse.
6. Fixes result parsing for RAD bridge completion and TimeSpan-form GatherResourceFileInfo durations.

RUN ORDER
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_MEMCPY_NATIVE_SCALE.cmd

EXPECTED RUNTIME MARKERS
[V74.0.18][MEMCPY_FASTPATH] native intrinsic enabled for libc:memcpy (Q3VBxCXhUHs)
[V74.0.17][PTHREAD_FASTBOOT] opaque_owner_sync=enabled default=enabled

SAFETY
- No forced WAIT_REG_MEM values.
- No fake producer writes.
- No global removal of the HLE-preferred memcpy policy.
- Source backup + rollback on build failure.
