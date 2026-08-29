SharpEmu V76.3.21.3
Guest Progress Recovery + Performance Merge — DEV SAFE

DIAGNOSIS
V21.2 is not stuck on Vulkan:
- dual physical queue is enabled;
- graphics/compute timeline drains completely;
- pending GPU becomes zero;
- no DeviceLost / AccessViolation / fatal.
The regression is that guest DCB/ACB production stops before the first natural
ps_studios_logo.bk2 open.

Observed V21.2 endpoint:
- AGC enqueue/processed marker: 1024
- graphics submission around 1176-1181
- direct scanout frame: 44
- no natural Bink request

Known V17.1 progression in the same 181s diagnostic:
- AGC >= 2048
- graphics submission >= 2064
- direct scanout frame >= 83
- natural ps_studios_logo.bk2 request occurs
- guest continues into attract/title path

RECOVERY
Restores the V17.1 scheduling envelope that allowed guest progress:
- max work/render 4096 -> 1024
- producer scan 4096 -> 512
- dependency closure age 50ms -> 300ms
- dependency closure 16 slices -> 8
- slice pause 250us -> 1000us
- ordered microbatch 64 -> 32
- compute chain 8 -> 4
- draw command buffer 32 -> 8
- wait full-scan 32ms -> 16ms
- producer item headroom -> 48

PRESERVED
- V21.2 global snapshot bounds repair
- V20/V21 residency and frontend caches
- dual physical Vulkan queue
- resource/timeline cross-queue synchronization
- V17.0.1 Async AGC command processor
- 192/96 queue, burst4, host lanes6, inflight16
- safe memcpy
- sideband OFF
- WAIT_REG_MEM values and hazard semantics
- Bink natural-request ownership
- host auto boot remains OFF

SUCCESS CRITERIA
Primary:
natural_ps_studios_request=True

Progress counters should also cross the V21.2 stall:
max_agc_processed_count > 1024
max_draw_submission > 1181
max_direct_scanout_frame > 44

Strong target:
AGC >= 2048, submission >= 2064, scanout >= 83.

This is a Debug development package.
