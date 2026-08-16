SharpEmu — Demon's Souls Composite Replay A/B Exact Capture V73.0.21.2

PURPOSE
=======
V73.0.21.1 correctly stopped because the current source method layout was not
the layout assumed by the probe patch.

This package intentionally performs NO source edit.

RUN_1
- validates every PowerShell script with the native PowerShell parser
- validates the package manifest

RUN_2
- validates Demon's Souls eboot
- reads whatever current Presenter/Agc hashes are actually present
- requires the already-existing targetless replay implementation
- does not assume any TryBuildUntrackedTextureProbe source structure

RUN_3
- restores/builds SharpEmu.Libs
- builds SharpEmu.CLI
- verifies Presenter and Agc hashes did not change during build

RUN_4
- copies current Presenter and Agc sources into the RESULT before runtime
- enables SHARPEMU_REPLAY_TARGETLESS_COMPOSITES=1 only for the child process
- collects the compositor, 320 MiB atlas, DCC 0x45D550000, scanout, wait and
  guest-frame traces
- restores environment variables
- verifies source hashes are unchanged
- copies the exact sources again after runtime
- adds git HEAD/status/diff
- creates one RESULT ZIP containing runtime evidence + exact source

This avoids another speculative patch while directly testing whether the
targetless composites currently suppressed on the nearly-black 4K frames are
the missing final/UI composition.

VISUAL TEST
===========
After movie 2, report whether you see:
- normal menu/UI,
- partial UI,
- scene without UI,
- flickering/corrupted image,
- or the same black screen.

Any visual change during this A/B is important evidence.
