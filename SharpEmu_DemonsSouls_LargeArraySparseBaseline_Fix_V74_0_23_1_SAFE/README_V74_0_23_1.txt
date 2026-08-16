SharpEmu Demon's Souls - V74.0.23.1 SAFE

Purpose
-------
Repair the V74.0.23 packaging errors and fix the actual large-array cache coherency bug using the exact V73.0.20.4 source captured from the user's checkout.

What V74.0.23 got wrong
------------------------
1. validate_package.ps1 used a double-quoted regex containing $(?:...), so PowerShell attempted to execute ?:$reservedNames as a subexpression.
2. PRECHECK looked for V73.0.19.1 TEXTURE_CACHE_STALE/missing-baseline in AgcExports.cs. The exact source proves that validator lives in VulkanVideoPresenter.cs.
3. The proposed AGC bypass was therefore aimed at the wrong layer.

Exact source proof
------------------
Captured presenter SHA256:
0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8
Captured AGC SHA256:
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

VulkanVideoPresenter.TryBuildUntrackedTextureProbe rejects byteCount > 128 MiB before creating the sparse baseline. The 320 MiB / 80-layer texture therefore enters IsTextureContentCached without a baseline, is marked stale, removed from the texture cache, and rebuilt repeatedly.

Repair
------
V74.0.23.1 patches only VulkanVideoPresenter.cs. Array textures larger than 128 MiB and no larger than 512 MiB may build the existing sparse baseline. ComputeSparseGuestContentProbe reads only eight 64-byte samples (512 bytes total), so this does not copy or allocate the 320 MiB texture.

The old V74.0.23 SHARPEMU_LARGE_ARRAY_CACHE_TRUST experiment is OFF in RUN_4. HostMovieBridge and boot order are untouched. V74.0.21 Entry ABI and V74.0.15 array single-flight are preserved.

Run order
---------
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_LARGE_ARRAY_BASELINE_TEST.cmd

RUN_4 has no automatic timeout/kill. Close SharpEmu yourself when enough data has been collected; the result ZIP is then generated automatically.
