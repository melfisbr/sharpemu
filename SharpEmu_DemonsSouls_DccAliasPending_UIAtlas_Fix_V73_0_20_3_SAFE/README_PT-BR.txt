SharpEmu — Demon's Souls DCC Pending Alias + UI Atlas Fix V73.0.20.3

EXACT CURRENT BASELINE
======================
Presenter:
0CEE6F0F7BF74E90B9B74603F947D5BB52782426BEEA1959C9B1B6CC2EB66BD8

AgcExports:
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

EBOOT:
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

WHY V73.0.20.3
===============
V73.0.20.2 correctly found the real C# method definitions, but its next patch
assumed the local variables residentMatches and found were adjacent. The current
accumulated method does not preserve that exact textual form.

V73.0.20.3 removes that assumption entirely.

DCC FIX
=======
The old resolver rejects every matching DCC render target whose Vulkan image is
not resident yet:

    if (!IsGpuGuestImageAvailable(candidate...))
        continue;

That is the actual semantic bug.

The new code:
- asks whether candidate is resident only for diagnostics;
- increments residentMatches when true;
- DOES NOT continue when false;
- leaves the existing writer.Sequence selection intact.

Therefore the resolver chooses the newest matching DCC producer even when that
producer is still queued. TryCreateGuestDrawTexture marks the resolved alias and
lets it use the existing gpuWriterPending/reference-only path.

LARGE UI ARRAY FIX
==================
TryBuildUntrackedTextureProbe already performs a bounded sparse probe. V73.0.20.3
removes only:
    byteCount > MaxTrackedGuestImageBytes
from that method's guard.

The 1024x1024x80 (~320 MiB) array can therefore receive a sparse baseline
without a 320 MiB probe/copy and without missing-baseline churn.

PATCHING SAFETY
===============
- exact hash gated;
- method bodies are discovered by definition regex + balanced braces;
- no dependency on neighboring methods or local-variable ordering;
- two-file backup before editing;
- automatic rollback on patch/build failure;
- PowerShell parser validates all package scripts first.

TRACE
=====
[V73.0.20.3][LARGE_PROBE_SEEDED]
[V73.0.20.3][DCC_ALIAS_PENDING]
