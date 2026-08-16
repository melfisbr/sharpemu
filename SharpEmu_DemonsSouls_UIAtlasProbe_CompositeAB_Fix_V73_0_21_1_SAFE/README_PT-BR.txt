SharpEmu Demon's Souls V73.0.21.1

Reason for this revision
------------------------
V73.0.21 correctly refused to overwrite the repository because the presenter's
SHA256 had changed after the exact source capture.

Observed current hash:
2902CDEA16B5134061B2722EF68CB8A97FCA7D33FCDA2538AD4BB14420AC17E5

V73.0.21.1 does NOT ship an older complete VulkanVideoPresenter.cs.
It preserves every unrelated change in the current presenter and edits only
the bounded TryBuildUntrackedTextureProbe method if its old logical-size guard
is still present.

Safety
------
RUN_2:
- requires the exact reported current hash when an edit is needed;
- locates the probe method and its next-method boundary;
- rewrites only the size guard in memory;
- verifies the size guard is gone and the marker occurs exactly once;
- verifies AgcExports still exposes SHARPEMU_REPLAY_TARGETLESS_COMPOSITES;
- if any structural assumption fails, automatically creates
  SharpEmu_V73_0_21_1_SOURCE_CAPTURE_<timestamp>.zip with the exact current
  presenter and AGC sources.

RUN_3:
- repeats validation + precheck;
- backs up the current presenter;
- applies the bounded change;
- builds SharpEmu.Libs and SharpEmu.CLI;
- rolls back automatically on failure.

RUN_4:
- enables SHARPEMU_REPLAY_TARGETLESS_COMPOSITES=1 only in the diagnostic child
  process;
- collects composite replay/suppression, 320 MiB atlas cache churn, DCC
  0x45D550000, scanout, waits and guest-frame evidence;
- restores environment variables afterwards.
