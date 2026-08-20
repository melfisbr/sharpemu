SharpEmu Demon's Souls AttractGuestStateCompletion V74.0.77.2.1 Launcher Fix SAFE

Purpose:
- Fix RUN_5_TEST_DEMONS on Windows PowerShell 5.1 where ProcessStartInfo.ArgumentList is unavailable/null.
- Does NOT modify SharpEmu source code or the V74.0.77.2 guest-state correction.
- Converts every $psi.ArgumentList.Add(...) call in the installed V74.0.77.2 scripts/run_test.ps1 into PowerShell-5.1-compatible ProcessStartInfo.Arguments construction.
- Makes an exact backup before editing and restores it automatically if post-validation fails.

Run from C:\Users\Edpo\Documents\GitHub\sharpemu\Patches:
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_LAUNCHER_FIX.cmd
4. RUN_4_TEST_DEMONS.cmd
