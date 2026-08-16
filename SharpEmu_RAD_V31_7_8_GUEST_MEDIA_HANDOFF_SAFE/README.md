# SharpEmu V72.4.3.2.31.7.8 SAFE — guest-media handoff

V31.7.7 proved that the RAD path is stable: all three host-injected movies
completed, the embedded child-window host stayed valid, the hard gate removed
the former RAM/VRAM/CPU/GPU explosion, and the extra 80 ms audio delay was gone.

The remaining architectural defect is ownership.  V31.7.7 still logs:

    bink2.ds_boot_attract_injected
    ps_studios_logo.bk2 -> logo_intro.bk2 -> attract_movie.bk2

That bypasses the title's own Bink/state-machine flow.  The PPSA01341 EBOOT
contains CComponentBinkSimpleMovie::Think, CCPLdrBinkSimpleMovie, StartIntro and
CCPLdrStateMachineOneShotMusicSkipIntroAnimation.  HostMovieBridge historically
also marks attract_movie, menus, story movies and credits as guest-driven.

## What changes

Only `HostMovieBridge.TryStartConfiguredBootSequence()` is structurally restored.
The host fallback may bootstrap:

1. ps_studios_logo.bk2
2. logo_intro.bk2
3. logo_intro_loop.bk2 (when present)

`attract_movie.bk2` is no longer injected by host auto boot.  Once the bootstrap
returns control, any attract movie must arrive through the guest's natural movie
open path.

## What is deliberately preserved

- V31.7.7 RAD embedded child-window API
- V31.7.7 zero-delay pre-reveal anchor
- V31.7.6 decoder lifecycle hard gate
- guest GPU payload backpressure
- post-roll BINK logo suppression
- explicit `/T0` on the PlayStation Studios clip
- existing attract sidecar as compatibility fallback

The sidecar remains temporarily because disabling it before proving the guest
sound path would risk losing audio. RUN_4 adds only a narrow
`SHARPEMU_LOG_IO_FILTER=pr_demons_souls_intro` trace so a following revision can
replace that fallback with the guest's actual audio event/timeline.

## Expected architectural proof

No line may contain `bink2.ds_boot_attract_injected`.
No host auto-boot order may contain `attract_movie.bk2`.
If attract_movie is later attached, `bink2.natural_guest_movie_observed` for that
movie must have appeared first.
