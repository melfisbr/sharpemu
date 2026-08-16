SharpEmu Universal Loader / OFW Compatibility V62.0.2 SAFE

This revision fixes the false baseline assumption in V62.0.

V62.0 required the exact text:
  header.ProgramHeaderEntrySize != ProgramHeaderSize
The user's current SelfLoader no longer has that exact old state.

V62.0.2:
- detects current PH validation structurally;
- applies the PH-size widening only if the exact old block really exists;
- preserves an already-fixed/custom implementation;
- builds SharpEmu.Core + SharpEmu.CLI;
- scans every F:\JOGOSPS5\**\eboot.bin without starting games;
- classifies bare ELF / wrapped ELF / invalid candidate / unknown-or-encrypted;
- validates ELF64, little endian, x86-64, PH bounds, PH entry size and PT_LOAD;
- embeds exact current SelfLoader/ProgramHeader/ElfHeader snapshots and source
  windows into the result ZIP for the next compatibility patch.

This package does not pretend that OFW metadata decrypts retail SELF files.

V62.0.2 correction:
- fixes Windows PowerShell 5.1 parser failure in EBOOT_MATRIX object creation;
- removes inline `property=if(...)` usage;
- precomputes summary counters instead of nested pipeline interpolation;
- no additional loader semantic changes are introduced by this revision.
