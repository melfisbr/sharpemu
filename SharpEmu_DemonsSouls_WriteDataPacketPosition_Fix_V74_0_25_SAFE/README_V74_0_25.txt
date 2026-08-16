SharpEmu V74.0.25 SAFE — Demon's Souls WRITE_DATA packet-position repair

Purpose
-------
V74.0.24 fixed the stale texture source loop and preserved the 320 MiB array fixes,
but seven startup WAIT_REG_MEM DCBs remained registered for the entire run. Historical
captures of this same title show those same label families are satisfied by real
WRITE_DATA producers and their queues resume.

The accumulated source introduced a special WRITE_DATA path which waits for the host
fence of every earlier shader submission in the logical queue before applying the
immediate WRITE_DATA payload. V74.0.25 adds an opt-in path that restores the earlier
queue-position behavior for WRITE_DATA only: prior batched commands are flushed and the
real packet payload is applied at its logical PM4 position without waiting for unrelated
host shader completion.

Safety
------
- Default behavior is unchanged unless SHARPEMU_WRITE_DATA_PACKET_POSITION=1.
- RUN_4 alone enables the gate.
- No WAIT_REG_MEM label is synthesized or force-written.
- RELEASE_MEM, DMA_DATA, ACQUIRE_MEM and GPU->CPU visibility paths are unchanged.
- V74.0.21 entry ABI, V74.0.15 single-flight, V74.0.23.1 sparse baseline and V74.0.24
  fresh stale-source behavior are required and preserved.
- HostMovieBridge and boot order are not changed.
- RUN_4 has no timer/auto-kill.

Run
---
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_WRITE_DATA_PACKET_POSITION_TEST.cmd
