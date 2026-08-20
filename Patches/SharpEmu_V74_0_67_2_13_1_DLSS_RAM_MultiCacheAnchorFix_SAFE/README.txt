SharpEmu V74.0.67.2.13.1
DLSS Activation + RAM MultiCache Anchor Fix SAFE

WHY V2.13 DID NOT APPLY
=======================
RUN_1 passed.
RUN_2 failed only because:
  ram_anchor_ttl=0

RUN_3 invokes RUN_2 first, so it stopped before:
- native V2.13 provider rebuild;
- managed DLSS activation patch;
- RAM content-identity patch;
- Release host rebuild.

RUN_4 therefore correctly showed all new V2.13 markers as false.

ROOT CAUSE
==========
The accumulated checkout no longer uses the old V74.0.15 single-entry TTL
comparison shape searched by V2.13.

The active large-array cache owner is V74.0.64 multicache:
  _v74064LargeArraySnapshotTtlMs
  SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS
  SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES
  TryGetLargeArraySnapshotV74064
  StoreLargeArraySnapshotV74064
  [V74.0.64][ARRAY_CACHE_OWNER]

Therefore V2.13.1 does NOT rewrite TTL comparisons.

RAM FIX
=======
The new source patch only changes large-array identity to the sparse content
key when GuestImageWriteTracker is unavailable.

TTL remains owned by V74.0.64.

RUN_5 uses the existing V74.0.64 environment interface:
  SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES=2
  SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS=120000

Runtime proof:
  [V74.0.64][ARRAY_CACHE_OWNER] ... cache=... ttl_ms=120000
  [V74.0.15][ARRAY_SINGLEFLIGHT] ... ttl_ms=120000

This is safer than introducing a second TTL implementation.

DLSS FIX
========
The V2.13 DLSS work is retained:
- explicit NVSDK_NGX_FeatureCommonInfo path;
- explicit nvngx_dlss.dll discovery path;
- NGX logging callback;
- provider retained after failed native Initialize;
- bounded same-size retry every ~2 seconds;
- exact LastError repeated on failure;
- forced validation run using DLSS / Quality / pre-composite.

DLSS success remains strictly:
  selected=dlss
  state=active
  dlss_dispatches>0

BPE V2.11/V2.12 menu crash fixes are preserved.
