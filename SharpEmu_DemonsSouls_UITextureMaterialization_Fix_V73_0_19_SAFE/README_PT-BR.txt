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
