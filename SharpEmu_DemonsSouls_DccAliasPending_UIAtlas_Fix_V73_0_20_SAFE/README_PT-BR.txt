SharpEmu — Demon's Souls DCC Pending Alias + UI Atlas Fix V73.0.20

EBOOT
=====
PPSA01341
SHA256 22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

EVIDENCE FROM V73.0.19.1
========================
texture_cache_stale=11
texture_cache_refresh=11
texture_fallback=0
draw_reject=0
runtime_unresolved=0
device_lost=0
flip_checkpoints=6
CP5_PRESENT result=Success observed 12 times.

Therefore the presenter is alive and the V73.0.19 cache refresh path worked.

The two 4K display buffers were still almost black:
- 0x457C00000: 9,311 non-black pixels / 8,294,400
- 0x459C00000: 29,698 non-black pixels / 8,294,400

DCC evidence:
- unresolved_dcc_cpu_snapshot_suppressed=60
- total_suppressed_mb reached 2180
- 0x460890000: 28 suppressions
- 0x45D550000: 24 suppressions
- 0x4888C0000: 7 suppressions
- 0x45BC00000: 1 suppression

The existing DCC alias resolver only selected candidates whose VkImage was
already resident. A matching DCC render target that was queued but not resident
was discarded, then the sampled texture path fell toward a CPU snapshot of
compressed guest RAM. Newer SharpEmu correctly suppresses that snapshot, which
leaves black data.

V73.0.20 changes this:
1. Metadata+shape-compatible DCC aliases remain selectable while their producer
   is pending.
2. Resident aliases are preferred; otherwise the newest writer is selected.
3. A pending resolved alias enters the existing reference-only
   gpuWriterPending path instead of CPU snapshotting compressed RAM.
4. Adds [V73.0.20][DCC_ALIAS_PENDING].
5. Fixes the 80-layer / 320 MiB atlas sparse probe:
   sparse probes read only 512 bytes and are now allowed for large resources.
6. Removes the V73.0.19.1 missing-baseline eviction loop for that array and adds
   [V73.0.20][LARGE_PROBE_SEEDED].

SCOPE
=====
Only:
src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs
src\SharpEmu.Libs\Agc\AgcExports.cs

No SaveData, APR, Bink, audio or input changes.
