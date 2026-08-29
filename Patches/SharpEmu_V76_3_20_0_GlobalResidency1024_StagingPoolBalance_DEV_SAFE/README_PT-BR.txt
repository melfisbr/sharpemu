SharpEmu V76.3.20.0 — Global Residency 1024 / Staging Pool Balance

V19 reached the 640-entry global residency cap while using only about 220 MiB
of the configured 384 MiB and accumulated hundreds of budget fallbacks.
This package raises only the ENTRY cap to the source-supported maximum 1024
while keeping the persistent-global byte budget at 384 MiB.

It also increases reusable transient pools:
- host staging cache: 192 -> 256 MiB
- device buffer cache: 512/default -> 768 MiB

It does NOT:
- increase persistent global VRAM beyond 384 MiB;
- weaken generation validation;
- cache writable globals;
- alter waits, hazards, queue order, Bink or barriers.

Requires V19 + V18 + V17.0.1. Build is Debug and rollback is automatic.
