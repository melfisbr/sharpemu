# SharpEmu V74.0.120.0 — Draw Feed NoAlloc / Global Lookup / Layout Canonical SAFE

Required baseline:
- V118.0.1 GPU-resident ShaderId active
- V117.16 fence-safe descriptor cache active
- V119 execution-graph/ReBAR direct-global path present
- V117.15 texture-backing alias must NOT be present

Evidence from the supplied V118.0.1 run:
- 0.4 FPS / 200 draws/s
- CPU 77%, GPU 37%
- DeviceLost=0
- 32,768 resident shader lookups, 24,522 compute fast hits, 4,049 graphics fast hits
- renderer windows show Draw around 30-61% of self-time
- hot offscreen draws frequently have no vertex/index payload and globals shaped
  [262144,262144,262144,1036,1036]
- V119 ReBAR direct globals remove staging/copy barriers but still perform very large
  amounts of guest->mapped-GPU CPU feed.

V120.0 attacks CPU work performed before the already-hot resident pipeline:
1. GuestBufferAllocation lookup: sorted-list linear scan -> exact binary search.
2. PrepareGuestBufferAllocations:
   - all-read-only draw/dispatch: return with no List allocation;
   - exactly one writable range: direct EnsureGuestBufferAllocation, no sort/merge Lists.
3. Vertex resource setup:
   - zero vertex bindings: no Dictionary and no HashSet;
   - one vertex binding: direct create/return, no Dictionary and no HashSet.
4. Render-target feedback lookup: no LINQ FirstOrDefault closure in the per-texture loop.
5. Resource layout string: exact 256-bit storage-mask structural key -> canonical string.
6. Render-target and blend layout strings: exact value keys for up to 8 attachments -> canonical string.
7. Zero-vertex layout returns string.Empty without StringBuilder.
8. Runtime enables existing DRAW_RESOURCE_PHASES and COMPUTE_RESOURCE_PHASES telemetry.

DeviceLost safety:
- no VkImage/VkImageView reuse
- no texture ownership/lifetime changes
- no guest-buffer-content cache
- no write-generation tracker changes
- no command-buffer reuse
- no queue widening
- no barrier changes
- no Pair2 changes
- no vkQueueSubmit changes
- no dual physical queue

This package reduces host CPU draw-feed bookkeeping. It does not claim that the remaining
guest->GPU bytes can be skipped without a proven coherency mechanism; the phase profiler is
enabled specifically so the next structural change is selected from measured texture/global/
descriptor/pipeline self-time.
