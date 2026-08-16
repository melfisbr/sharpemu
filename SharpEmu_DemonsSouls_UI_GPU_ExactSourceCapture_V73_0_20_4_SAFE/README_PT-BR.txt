SharpEmu — Demon's Souls Exact UI/GPU Source Capture V73.0.20.4

This is intentionally NOT another speculative patch.

The three previous DCC patch attempts were rejected safely because the current
AgcExports.cs body differs from older accumulated snapshots. V73.0.20.4 locks
onto the exact current hashes:

VulkanVideoPresenter.cs
0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8

AgcExports.cs
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

Demon's Souls eboot
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

WHAT IT DOES
============
- validates every PowerShell script with the native PowerShell parser;
- validates exact current source hashes;
- validates required UI/DCC method/marker names;
- copies the two current source files byte-for-byte into a result folder;
- captures focused contexts and git diff/provenance;
- re-hashes both source files after capture and aborts if either changed;
- creates a ZIP for analysis.

WHAT IT DOES NOT DO
===================
- no source modification;
- no patch;
- no build;
- no emulator execution;
- no rollback is needed because there are no writes.

The next correction can be tested locally against these exact two files before
being delivered, including dry-run patching and static C# checks.
