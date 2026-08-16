# DBFZ RIFF/ATRAC9 + App0 V1.8.15.2 SAFE

This is an idempotent continuation package for the successfully applied
V1.8.15.1 source state.

Why it exists:
- V1.8.15.1 successfully built and removed the old
  SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2 block.
- Re-running its precheck incorrectly treated that expected removal as an error.
- Global version/tag replacement also produced cosmetic duplicated strings such
  as DBFZ-RIFF-181511 and V1_8_15_1_1.

V1.8.15.2:
- accepts the applied RIFF/ATRAC9 + app0 state as AlreadyApplied;
- performs no source modifications;
- rebuilds, post-audits, and runs the 360-second diagnostic;
- includes regression checks preventing duplicated tag/version strings.
