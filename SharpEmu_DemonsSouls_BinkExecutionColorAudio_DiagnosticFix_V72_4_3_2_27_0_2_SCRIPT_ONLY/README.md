# SharpEmu Demon's Souls V27.0.2 Diagnostic Fix

SCRIPT-ONLY. No source change and no build.

The V27.0.1 source/runtime repair already completed successfully. The only
remaining failure was the diagnostic launcher using
`ProcessStartInfo.ArgumentList`, which is not exposed by Windows PowerShell
5.1/.NET Framework.

V27.0.2 uses the classic `ProcessStartInfo.Arguments` property and also keeps
the PowerShell 5.1-compatible environment-variable enum syntax:

`[System.EnvironmentVariableTarget]::Process`

The runner verifies before launch:

- V27 decoder markers are installed;
- V27 external intro audio is installed;
- V27 buffered runtime defaults are installed;
- deployed NIHAV SHA-256 is exactly:
  `cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18`

Run only:

1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_DEMONS_SOULS_TEST.cmd`

No apply/build is needed. Close SharpEmu normally after checking the boot
videos/title. The runner creates:

`SharpEmu_V72_4_3_2_27_0_2_BINK_RESULT_<timestamp>.zip`
