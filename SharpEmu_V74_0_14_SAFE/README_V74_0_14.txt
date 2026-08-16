SharpEmu V74.0.14 SAFE
========================

Purpose
-------
Correct the regressions exposed by:
SharpEmu_V74_0_13_2_FASTBOOT_PERF_HANDOFF_RESULT_20260815_172600.zip

Measured findings from V74.0.13.2
---------------------------------
1. Demon's Souls reached "Starting main loop" at 31.7831 s.
2. Runtime memory rose to working=8904 MB / private=13492 MB before failure.
3. Native lane logs reported tbb_limit=32 even though the performance test
   requested TBB=2.
4. The renderer created a 1024x1024 standalone array allocation with
   VkImage requirement 335544320 bytes (320 MiB) at guest address
   0x000000102A400000.
5. V74.0.13.2 had lowered the standalone texture budget to 384 MiB.
   Existing standalone textures + that array reached 416 MiB and triggered:
     [V74.0.8][TEX_CACHE] trim evicted=8 evicted_mb=416 ...
6. Immediately after the trim:
     ErrorDeviceLost
   followed by mitigated-child exit:
     HEAP_CORRUPTION / 0xC0000374
7. FASTBOOT_PERF.csv sampled only the small dotnet launcher (~21 MiB), not
   the actual mitigated process tree. The old summary therefore understated RAM.

Corrections in V74.0.14
-----------------------
- Does NOT replace DirectExecutionBackend.NativeWorker.cs with an old payload.
  That would overwrite later accumulated Dragon Ball FighterZ scheduler/worker
  work. Instead, V74.0.14 performs a surgical edit of only the
  NativeWorkerMaxConcurrent declaration when the current source uses a literal
  cap (the DBFZ V1.8.18/V1.8.19 form).
- The surgical reader honors SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT only when
  explicitly set and preserves the repository's current literal cap as its
  fallback for all other runs/games.
- If the current source already has an environment-aware limiter, it is left
  untouched and only rebuilt.
- Rebuilds Debug and Release win-x64 and preserves the V74.0.10 independent
  renderer/resource native lane.
- Requests TBB=2 and renderer/resource lane=8 for this Demon's Souls run and
  verifies the observed tbb_limit. A mismatch stops the diagnostic early.
- Keeps render_scale=0.5 and high-volume diagnostic families disabled.
- Restores standalone texture cache to 768 MiB. The exact 320 MiB texture was
  already observed under the 768 MiB profile without device loss, and that run
  later reached/completed ps_studios_logo.bk2.
- Keeps sampled/guest/device cache limits from V74.0.13.2 where no capacity
  failure was observed.
- Measures aggregate working/private/CPU across the dotnet + mitigated-child
  process tree instead of only the launcher.
- Expands fatal detection to "Vulkan device lost", ErrorDeviceLost,
  VK_ERROR_DEVICE_LOST, DeviceLostException, HEAP_CORRUPTION and 0xC0000374.
- Reads live logs with FileShare.ReadWrite|Delete and creates a result ZIP on
  normal stop or guarded diagnostic stop.

Bink scope
----------
This package intentionally does NOT change Bink decoding again. V74.0.13.2
failed before the first natural Bink request. The existing V74.0.13 robust
startup completion handoff is preserved while pre-video Vulkan/native
stability is retested.

Run order
---------
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_FASTBOOT_STABILITY.cmd
