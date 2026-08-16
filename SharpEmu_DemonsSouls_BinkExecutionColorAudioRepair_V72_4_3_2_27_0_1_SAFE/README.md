# SharpEmu Demon's Souls V27.0.1 — Runtime Deploy + Diagnostic Repair

This package repairs two package-side defects found after V27 was successfully
applied and built.

## Defect 1 — diagnostic PowerShell parser error

V27 used an invalid enum token in the environment-restore call. V27.0.1 uses:

`[System.EnvironmentVariableTarget]::Process`

throughout the runner and the package validator parses every `.ps1` before any
repository action.

## Defect 2 — native NIHAV did not survive `dotnet build`

`SharpEmu.CLI.csproj` contains the V61 deployment target
`CopySharpEmuNihavToolV6113166`. Every CLI build copied:

`.sharpemu-tools\bink2\src\nihav\nihav-tool\target\release\nihav-tool.exe`

back into:

`artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe`

This reverted the V27 native/LTO runtime after each build.

V27.0.1 installs the benchmarked native executable at the stable path:

`.sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe`

and changes the existing MSBuild deployment source to that file. Future CLI
builds therefore keep deploying the optimized runtime instead of restoring the
old one.

Expected native SHA-256:

`cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18`

## Scope

V27 source corrections to video buffering, U/V repair, centered color gate, and
external Demon's Souls intro audio are preserved. V27.0.1 does not replace or
undo those source changes.

## Run order

From the repository root:

1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_DEMONS_SOULS_TEST.cmd`

After step 4, close SharpEmu normally after checking the videos/title. The
runner creates:

`SharpEmu_V72_4_3_2_27_0_1_BINK_RESULT_<timestamp>.zip`

Send that ZIP back for the next audit.

A manual `RUN_ROLLBACK_LAST.cmd` is included.
