# V74.0.7.1 CS0103 API-name repair

V74.0.7 reached compilation and produced one error:
`InvalidateTextureCacheAddressV56` does not exist.

The accumulated presenter already contains the correct API,
`InvalidateSampledTextureCacheForGuestAddressV56`, which performs the exact
same-address sampled-cache invalidation required before retiring a sampled-only
GuestImage.

V74.0.7.1 changes only that call. The V74.0.7 residency budget and swapchain
staging retirement remain unchanged.

Baseline SHA256:
`7E2BAF55BE358C248FAC6755DE8C15BA5F2BBB6ACC7BB1F4C3B78CE2F4E7D6E8`

Corrected payload SHA256:
`1D8EE63DCB2F4E2A1EEC595535F40224FBE06E1DD16531233597F24740A02A28`

# SharpEmu Demon's Souls — Sampled GuestImage Residency Fix V74.0.7 SAFE

## V74.0.6.3 result

The compute correction is confirmed successful:

- compute dispatch failures: 0
- compute texture null invariant: 0
- CLR FailFast: 0
- raw EVENT_FASTPATH progressed through n=1024

The run was intentionally stopped by the memory safety guard at about 50 s:

- peak working set: ~11.8 GiB
- peak private bytes: ~17.1 GiB

Only 6 >=8 MiB CPU texture snapshot breadcrumbs remained, so the previous
large managed snapshot loop is no longer sufficient to explain the resident
memory growth.

## Root residency defect

`CreateTextureResource()` promotes a normal sampled 2D texture into
`_guestImages` whenever that guest address does not already have one.

The promoted `GuestImageResource` is then global presenter state. Unlike:
- guest-buffer cache (byte-budgeted),
- host/device buffer pools (byte-budgeted),
- pipeline caches (entry-budgeted),
- guest-image variant cache (bounded),

the sampled `_guestImages` promotion had no byte budget. A sampled asset could
therefore retain a VkImage/DeviceMemory until presenter teardown.

V74.0.7 labels only these sampled-origin images as `SampledCacheOnly`, records
their exact Vulkan `imageRequirements.Size`, and applies a 512 MiB default
budget. When the budget is exceeded, the oldest sampled-only images are
retired to 75% of budget using the existing submission timeline. Real
render-target, storage, or display use promotes an image out of this eviction
class before it can be trimmed.

## Second retention defect

`RecordTextureUploads()` already contains the V73.17 rule that cached texture
staging is one-shot and must retire after the owning fence. Compute and
offscreen paths pass a retirement list. The direct swapchain translated-draw
path did not.

V74.0.7 adds a per-frame retirement list and frees those cached staging
buffers when the frame-slot fence signals.

The V74.0.6.3 compute texture restore is preserved unchanged.
