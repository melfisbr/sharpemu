SharpEmu V76.3.20.3 — Balanced Dual Queue Recovery DEV SAFE

Purpose:
- Preserve V18 dual physical graphics/compute queues.
- Preserve V19/V20.0 shader frontend and global residency improvements.
- Preserve V17 async AGC, Chain4, producer slices and V15.1 safe memcpy.
- Revert only the V20.2 pressure increase: 256/128, burst8, inflight24, scan1024.
- Restore 192/96, burst4, inflight16, scan512.
- Restore the proven 16 ms producer-less scan fallback instead of V20.1's 100 ms experiment.

Why:
V20.2 proved dual queues are real (graphics and compute both submit), but boot
regressed to ~66.6 s and slow waits rose to 25. V20.0 main loop was ~48.6 s.

Build: Debug/win-x64.
Rollback: automatic on restore/build failure, plus RUN_5.
