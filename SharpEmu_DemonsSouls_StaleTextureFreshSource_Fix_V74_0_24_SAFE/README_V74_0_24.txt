SharpEmu V74.0.24 SAFE

V74.0.23.1 successfully fixed the 320 MiB array baseline loop: 0x102A400000 had missing-baseline=0, refresh=0, owner=1, reuse=15.

New evidence: all 26 remaining TEXTURE_CACHE_STALE events are guest-bytes-changed, and three addresses repeat the exact same OLD->NEW hash pair multiple times (44EE00000 x17, 108A500000 x4, 108B400000 x4). That proves the stale resource is evicted, but its already-translated old source snapshot is then uploaded again and becomes the same old baseline.

V74.0.24 refreshes the source of a stale <=64 MiB texture from current guest memory before rebuilding it. Tiled resources preserve Detile metadata and replace only TiledSource bytes; linear resources replace RgbaPixels. The existing sparse validator remains authoritative.

No HostMovieBridge/boot order/AGC changes. V74.0.21 Entry ABI, V74.0.15 single-flight and V74.0.23.1 large-array baseline are required and preserved. RUN_4 does not auto-kill SharpEmu.
