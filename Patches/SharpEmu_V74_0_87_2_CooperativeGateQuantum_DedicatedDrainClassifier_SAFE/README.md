SharpEmu V74.0.87.2 — Cooperative Gate Quantum / Dedicated Drain Classifier SAFE

Goal
----
Apply the V87 cooperative gpuState.Gate quantum at the dedicated V72 helper
TryDrainPendingWaitersOnGateOwnerV74072, never at ParseSubmittedDcbCore.

Why V87.2
---------
V87.1 correctly discovered the current checkout has four GATE_OWNER_WAIT_DRAIN
markers and two SubmittedGpuState method candidates:
  1. ParseSubmittedDcbCore
  2. TryDrainPendingWaitersOnGateOwnerV74072
V87.2 classifies the dedicated GateOwner/Drain helper explicitly. RUN_1 contains
a regression fixture with the same 4-marker / 2-candidate ambiguity and also runs
the exact transform against the current checkout in read-only mode.

Safety
------
- No rigid SHA gate.
- RUN_1 performs hashes, PowerShell parsing, locator regression, transform/idempotence,
  and current-checkout read-only dry-run.
- RUN_3 writes only after the same dry-run passes.
- Automatic rollback if apply/build fails.
- V81.2 Vulkan boundaries and accumulated V82/V84/V85/V86.4 are preserved.
- Gate quantum defaults: 16 V72 boundaries or 1 ms; env 0/0 restores legacy.

Commands
--------
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
.\SharpEmu_V74_0_87_2_CooperativeGateQuantum_DedicatedDrainClassifier_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
.\SharpEmu_V74_0_87_2_CooperativeGateQuantum_DedicatedDrainClassifier_SAFE\RUN_2_PRECHECK.cmd
.\SharpEmu_V74_0_87_2_CooperativeGateQuantum_DedicatedDrainClassifier_SAFE\RUN_3_APPLY_BUILD.cmd
.\SharpEmu_V74_0_87_2_CooperativeGateQuantum_DedicatedDrainClassifier_SAFE\RUN_4_TEST_DIAGNOSTIC.cmd
