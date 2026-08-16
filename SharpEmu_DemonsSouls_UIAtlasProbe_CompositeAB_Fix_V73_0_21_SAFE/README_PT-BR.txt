SharpEmu — Demon's Souls UI Atlas Sparse Probe + Composite A/B V73.0.21

WHY THIS PACKAGE IS DIFFERENT
=============================
It was built from the exact source capture supplied by the user:

VulkanVideoPresenter.cs
0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8

AgcExports.cs
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

The package DOES NOT use a structural/regex patcher during APPLY.
It ships the complete corrected VulkanVideoPresenter.cs whose SHA256 is:

1E439A8DF46E2DC648D10CF54C2998A69CDF4B147985923EFFF99055CCD8A385

RUN_2 performs the exact transformation in memory on the current source and
refuses to continue unless that dry-run produces exactly the shipped payload
hash. Therefore an anchor mismatch cannot first appear in RUN_3.

FUNCTIONAL FIX
==============
TryBuildUntrackedTextureProbe samples at most 8 x 64 bytes, but the current
source rejects the probe when logical byteCount > MaxTrackedGuestImageBytes
(128 MiB). The 1024x1024x80 resource is ~320 MiB, so it never gets a baseline.
That causes repeated stale/refresh/singleflight churn.

V73.0.21 removes ONLY the logical-size rejection from the sparse probe.
No full 320 MiB copy is added by this change.

BLACK-SCREEN A/B
================
The current exact AgcExports.cs already contains an opt-in diagnostic:
SHARPEMU_REPLAY_TARGETLESS_COMPOSITES=1

RUN_4 enables that switch ONLY for the diagnostic SharpEmu child process.
It does not make replay permanent in source.

This tests whether the targetless composites currently suppressed after the
real 4K writer contain the missing UI/final composition. If replay fixes the
screen, the next correction can make a narrower frame-valid replay rule rather
than globally enabling the old fallback.

The diagnostic also isolates the unresolved 0x45D550000 DCC source and the
320 MiB atlas cache behavior.
