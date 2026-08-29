SharpEmu V76.3.20.5 — Resident Global Hotset 1536 DEV SAFE

Requires V20.4.

Evidence:
V20.0 reached exactly 1024 resident global entries, about 371.6 MiB resident,
with zero budget fallback. This means the entry cap, not only byte budget, was
being reached.

Change:
- implementation clamp: 1024 -> 2048 (adaptive one-anchor transform)
- runtime entries: 1536
- resident global budget: 512 MiB
- host staging reuse cache: 256 MiB
- DEVICE_LOCAL immutable buffer cache: 1024 MiB
- resident shader max: 2048
- descriptor set cache max: 4096
- V19 admission thresholds preserved (3 observations normal, 2 medium/large)

This does NOT make writable globals resident and does NOT cache guest bytes
without generation checks. Existing BaseAddress/length/descriptor geometry and
guest-write-generation validation remains authoritative.

V20.3 balanced queue and V20.4 watched producer path remain active.
Build: Debug/win-x64.
Automatic rollback on failure.
