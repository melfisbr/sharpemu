SharpEmu - Demon's Souls EBOOT SaveData Audit Fix V73.0.18.2

WHY 18.1
========
V73.0.18 PACKAGE VALIDATION passed, but the user's accumulated source has:
SHA256 9CC3F444B8375F582E1A8AD29F89A127FB0DF8358152915374C07E9911B13735

That source is newer than the baseline used to build V73.0.18, so the original
package correctly refused to overwrite it.

V73.0.18.2 IS STRUCTURAL
========================
It does NOT ship an old SaveDataExports.cs payload.
It patches the user's current SaveDataExports.cs in-place and preserves all
unrelated accumulated changes.

The patcher:
1. changes DefaultBlockSize to 65536 bytes;
2. replaces any literal 32768 used-block formula with DefaultBlockSize;
3. adds exact PPSA01341 import z1JA8-iJt3k = sceSaveDataBackup if absent;
4. replaces only SaveDataPrepare() so RSI=&prepareParam is honored;
5. leaves CreateTransactionResource/Mount3/Commit and all unrelated APIs intact.

Safety:
- accepts exact current SHA256 9CC3F444B8375F582E1A8AD29F89A127FB0DF8358152915374C07E9911B13735;
- can also accept a newer source only when all structural anchors are present;
- creates a backup before editing;
- restores the original file automatically if patching, restore or build fails;
- compile verifies SharpEmu.Libs and SharpEmu.CLI.

EBOOT
=====
PPSA01341 SHA256
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

Run:
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK_REPO.cmd
RUN_3_APPLY_AND_BUILD.cmd
RUN_4_DEMONS_DIAGNOSTIC.cmd


V73.0.18.2 PARSER FIX
=====================
V73.0.18.1 was rejected by Windows PowerShell before the structural patch ran:
  "$Name:" inside an unused helper was parsed as an invalid drive-qualified
  variable reference.

The user's APPLY script then executed its rollback path successfully, so
SaveDataExports.cs remained on the accumulated baseline:
9CC3F444B8375F582E1A8AD29F89A127FB0DF8358152915374C07E9911B13735

V73.0.18.2 removes that unused helper and RUN_1 now invokes the native
System.Management.Automation.Language.Parser on every package .ps1 file.
