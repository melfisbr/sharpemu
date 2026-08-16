SharpEmu - Demon's Souls UI Texture Materialization Fix V73.0.19

This package targets UI/texture DATA COHERENCY after the files have already
been read successfully.

It structurally patches the current accumulated source; it does not overwrite
AgcExports.cs or VulkanVideoPresenter.cs with old snapshots.

Changes:
1. Demon Souls cached textures get an 8 x 64-byte sparse backing-memory probe
   when GuestImageWriteTracker is disabled.
2. A changed probe invalidates the cached texture and ships fresh texels.
3. Render-thread stale VkImages are retired through the existing submission
   timeline rather than destroyed while in use.
4. Vulkan texture self-heal can read normal guest memory, tracked libc heap and
   the low-46-bit GPU alias.
5. CPU-prefilled UI/font render-target seed uses the same alias-aware AGC reader.

No global texture-cache disable is used, so this avoids reintroducing the large
CPU/RAM cost of copying every texture on every draw.

Run RUN_1 -> RUN_2 -> RUN_3 -> RUN_4.


V73.0.19.1 STRUCTURAL ADAPTATION
================================
Observed accumulated source:
VulkanVideoPresenter.cs
B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245

AgcExports.cs
9951870F2D0ED6C66F0743F87780F6981A3ECA46B27BB4BA95FD0784E9DA5C98

V73.0.19 rolled back because the cache-hit block contains checkout-specific
logic and did not match one exact multiline template.

V73.0.19.1 does not replace that block. It structurally locates the
_textureCache.TryGetValue(key, out var cached) condition and inserts stale
eviction immediately before it. Therefore all existing accumulated cache-hit
logic remains intact.

The guest-image sparse-probe seed is also inserted structurally after the
_guestImageExtents[texture.Address] assignment instead of matching a whole
surrounding block.

No V73.0.17 prerequisite is introduced.
