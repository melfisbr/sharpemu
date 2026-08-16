SharpEmu V74.0.26 - Demon's Souls Job-Pool Lane Packing FastBoot

V74.0.25 result:
- all 7 startup WAIT_REG_MEM labels resumed naturally;
- WRITE_DATA packet-position path reached count 2048;
- WAIT_RESUME reached count 1024;
- no forced WAIT labels;
- no DeviceLost / heap corruption;
- 320 MiB array remained stable (owner=1, reuse=15, no missing-baseline refresh);
- natural Bink was still 0 after 107.04 s;
- 258 low-noise WAIT_RESUME samples included 26 >1 s and 24 >4 s;
- maximum sampled wait was 7160.489 ms;
- peak tree memory was 9420.5 MiB working / 14750.1 MiB private.

Why V74.0.26:
DirectExecutionBackend already contains a Demon's Souls-aware host-affinity policy.
Its source comment records a 16-logical-processor benchmark:
  reserved 0 / 4 / 6 / 8 -> 6.08 / 6.78 / 7.20 / 5.62 fps.
The best measured case leaves 10 host lanes usable by guest threads.

On the user's 24-thread Ryzen 9 3900, the ratio-based default is 9 reserved,
which leaves 15 guest-usable lanes. Demon's Souls only asks for guest CPUs 0-12,
so the 13 BPE JobWorkerThread workers can occupy distinct host lanes and do not
receive the packing benefit described by the source.

RUN_4 therefore keeps the accumulated source intact and sets:
  SHARPEMU_RESERVED_HOST_LANES = ProcessorCount - 10
On a 24-thread host this is 14, leaving 10 guest-usable host lanes.

This is a controlled A/B profile, not a claim that 10 lanes are already proven
optimal on the Ryzen 9 3900. V74.0.25 is the baseline. If V74.0.26 improves
WAIT latency / CPU / natural Bink progress, the result supports adjusting the
Demon's Souls scheduling profile. If it worsens, there is no source rollback:
close the process and the environment is restored automatically.

RUN ORDER:
  RUN_1_VALIDATE_PACKAGE.cmd
  RUN_2_PRECHECK.cmd
  RUN_3_APPLY_BUILD.cmd
  RUN_4_DEMONS_JOBPOOL_LANE_PACKING.cmd

RUN_3 does not modify source. It verifies the accumulated fixes and rebuilds
Release win-x64, then verifies source hashes are unchanged.

RUN_4 has no auto-kill. Close the SharpEmu window yourself. For a useful A/B,
allow at least 180 seconds if a natural movie has not appeared earlier.
