SharpEmu Demon's Souls V74.0.27 SAFE

Purpose
- Preserve the successful V74.0.25 real WRITE_DATA/WAIT recovery and V74.0.24 texture fixes.
- Revert the V74.0.26 10-lane A/B profile to the source-default host-lane policy because it did not improve time-to-first-natural-Bink.
- Implement the exact RDNA/GFX10 shader instructions that failed immediately after ps_studios_logo.bk2 in V74.0.26:
  DS opcode 0x76 = DS_READ_B64
  DS opcode 0x77 = DS_READ2_B64
  DS opcode 0x78 = DS_READ2ST64_B64 (same family, added before it becomes the next failure)
  VOP2 opcode 0x09 = V_MUL_I32_I24
  VOP2 opcode 0x0A = V_MUL_HI_I32_I24

RUN_4 remains guest-owned boot (Bink auto boot OFF) and has no automatic process kill.
The real Windows PowerShell AST validation happens in RUN_1 and the real .NET Release build happens in RUN_3.

Expected test window: V74.0.26 requested ps_studios_logo near 366 s, so keep RUN_4 alive through that movie and at least 60 s after completion.
