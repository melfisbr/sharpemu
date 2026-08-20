# SharpEmu V74.0.87 — Cooperative Gate Quantum

Target: Demon's Souls PPSA01341 accumulated V86.4 checkout.

V86.4 successfully reduced large CPU snapshot churn and released resident bridge memory, but FPS did not improve. The runtime instead shows severe `gpuState.Gate` contention, including multi-second `DEDICATED_WAIT_DRAIN` waits. V87 bounds uninterrupted Gate ownership at the existing V72 complete-packet hook.

## Runtime policy

- Default quantum: 16 V72 packet-boundary hooks OR 1 ms, whichever occurs first.
- The current PM4 packet/ordered side effect is always completed before Gate release.
- `Monitor.Exit` / host scheduler yield / `Monitor.Enter` is guarded by `Monitor.IsEntered` and `try/finally`.
- `SHARPEMU_AGC_GATE_QUANTUM_PACKETS=0` and `SHARPEMU_AGC_GATE_QUANTUM_MS=0` disable V87 and restore uninterrupted legacy Gate ownership.
- V81.2 Vulkan boundaries, V82 nonblocking visibility, V84 adaptive compute, V85 PM4/release changes and V86.4 resident retention are preserved.

## Diagnostic

RUN_4 no longer pipes native stderr directly into PowerShell `Tee-Object`. `cmd.exe` merges stdout/stderr first; PowerShell then appends UTF-8 lines. This avoids `NativeCommandError` records and UTF-16/NUL logs that invalidated the V86.4 summary.
