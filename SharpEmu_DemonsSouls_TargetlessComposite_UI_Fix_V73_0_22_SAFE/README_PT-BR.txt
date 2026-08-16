SharpEmu — Demon's Souls Targetless Composite UI Fix V73.0.22

V73.0.21.2 PROVED THE MISSING PATH
==================================
With targetless-composite replay enabled, the real LANGUAGE SELECT screen
appeared after movie 2.

Captured result:
- deferred_composite_replayed=124
- deferred_composite_draws=248
- deferred_composite_suppressed=0
- cp5_present_success=133
- runtime_unresolved=0
- device_lost=0

The diagnostic produced 325,961 stderr lines because SHARPEMU_LOG_AGC_SHADER=1
also enables the Vulkan shader hot trace in the current presenter. Therefore the
observed ~12-minute / ~0.1 FPS run is not a clean normal-performance result.

V73.0.22
========
Exact captured AgcExports baseline:
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

Exact patched payload:
2A68E4F9E3BBAACC50409D03EB146235546392A8F036C8628D5CF6B2560E4DE1

For PPSA01341 the proven targetless-composite replay becomes the default.
Other titles retain the existing suppression behavior.

Overrides:
SHARPEMU_REPLAY_TARGETLESS_COMPOSITES=1  force replay
SHARPEMU_REPLAY_TARGETLESS_COMPOSITES=0  force old suppression

The title decision is evaluated at runtime through
KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA01341"), so it is
not frozen before the game title is configured.

A low-volume marker is emitted for frames 1..8 and powers of two:
[V73.0.22][DS_COMPOSITE_REPLAY]

PERFORMANCE TEST
================
RUN_4 explicitly disables the high-volume AGC/Vulkan shader traces and leaves
the replay environment override unset, proving the title-scoped source rule.
Close SharpEmu as soon as LANGUAGE SELECT becomes visible; SUMMARY.txt records
wall_seconds.

The successful A/B presenter already contains V74.0.23.1's 512-byte sparse
baseline for the 320 MiB arrays, so this package does not modify presenter code.
