SharpEmu — Demon's Souls DCC Pending Alias + UI Atlas Fix V73.0.20.2

CURRENT BASELINE
================
Presenter:
0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8

AgcExports:
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

EBOOT:
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

WHY 20.2
========
V73.0.20.1 rolled back because the patcher required the literal signature:
    private static bool TryResolveDccMetadataAlias(
The method exists, as the PRECHECK proved, but the accumulated source uses a
different declaration/modifier/return-type formatting.

V73.0.20.2 discovers actual C# METHOD DEFINITIONS using a regex anchored at a
line that begins with an access modifier and ends at the requested method name.
It therefore does not confuse callsites with declarations and does not require
"private static bool".

PRECHECK prints the exact definitions it found before any source write.

This package intentionally accepts only the exact current source hashes above,
or a source already carrying both V73.0.20.2 markers.

FUNCTIONAL FIXES
================
1. Large sparse texture probe:
   removes only the logical-size rejection inside TryBuildUntrackedTextureProbe.
   The bounded sparse probe can seed the 1024x1024x80 / 320 MiB array without
   copying the full resource.

2. DCC pending alias:
   TryResolveDccMetadataAlias keeps a metadata/shape-compatible render target
   while its Vulkan image is pending, prefers resident candidates, otherwise
   chooses the newest observed writer.

3. TryCreateGuestDrawTexture marks a resolved DCC alias and lets it use the
   existing gpuWriterPending/reference-only dependency path.

TRACE
=====
[V73.0.20.2][LARGE_PROBE_SEEDED]
[V73.0.20.2][DCC_ALIAS_PENDING]

SCOPE
=====
Only:
src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs
src\SharpEmu.Libs\Agc\AgcExports.cs
