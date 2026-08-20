SharpEmu Demon's Souls Post-Attract Audio Drain + Bink Postroll Fence V1.1.12 SAFE

OBJECTIVE
=========
Keep the existing RAD player path, but fix two transition regressions:

1. After attract_movie ends and logo_intro starts, attract audio can become
   audible again in the background.
2. A Bink/RAD post-roll logo can briefly become visible after attract_movie.

ROOT CAUSE — AUDIO
==================
The existing V1.1.6 ownership latch deliberately silences guest AudioOut and
AudioOut2 while the RAD/attract sidecar owns startup sound. At attract teardown
the latch is released immediately.

That can expose guest PCM that was generated while the host owner was active.

Runtime evidence also showed logo_intro_loop using NIHAV for VIDEO while
TITLE_LOOP_AUDIO reports host_audio_probe=False and guest_audio_owner=True.
Therefore the repeated sound is not treated as a NIHAV-host-audio decode.

V1.1.12:
- stops deterministic attract WaveOut/PlaySound at the exact RAD nominal end;
- keeps AudioOut/AudioOut2 silently paced for 1500 ms by default;
- does not stop guest threads or queue progression;
- blocks any post-attract host-audio ownership restart for:
    logo_intro.bk2
    logo_intro_loop.bk2
    main_menu.bk2
- the block is single-use and title-transition scoped.

Environment override:
  SHARPEMU_DS_POST_ATTRACT_GUEST_DRAIN_MS
Default: 1500
Clamp: 250..5000

ROOT CAUSE — BINK POSTROLL LOGO
===============================
The old RAD implementation hid PlayerWindow once shortly before nominal end.
A one-shot hide is not a permanent visibility guarantee: the RAD process can
re-show its HWND or create another top-level renderer-owned window during
post-roll.

V1.1.12 adds an attract-only persistent hide fence:
- default begins 350 ms before nominal movie end;
- re-hides PlayerWindow and every HWND owned by RendererProcessId every 10 ms;
- does not query window titles;
- never targets SharpEmu's process/window;
- stops at nominal end;
- nominal end hides again and kills the RAD renderer.

Environment overrides:
  SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_LEAD_MS
    default 350; clamp 120..1500

  SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_MS
    default 1200; clamp 250..3000

RAD POLICY
==========
This package does not replace RAD with NIHAV or FFmpeg.

If the exact experimental V75.1.0 SharpEmu.BinkNative.dll previously generated
by this conversation is found, RUN_3 backs it up and removes only that known
SHA256 so the existing RAD path remains selected.

Known experimental DLL SHA256:
F221BE19DE8F8668E2FDD33F7685073017B94B763A965C8D00D99D766D0D302C

Unknown/native DLLs are NEVER removed.

PRESERVED
=========
- Options/START current-movie skip
- V1.1.3 completion shim
- V1.1.4 post-Studios black cover
- V1.1.6 AudioOut + AudioOut2 pacing-preserving mute
- V1.1.9 attract WaveOut release
- V1.1.10 head-aligned attract stems
- V1.1.11 ownership boundary when already installed
- existing game-state/completion semantics
- external RAD fallback/decoder behavior

EXPECTED RUNTIME MARKERS
========================
[BINK-POSTROLL][V1.1.12] fence_armed file='attract_movie.bk2' ...
[BINK-POSTROLL][V1.1.12] attract_nominal_end ... audio_stopped=True postroll_hidden=True guest_drain_armed=True
[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_armed ...
[BINK-AUDIO-OWNER][V1.1.12] post_attract_host_audio_blocked next='logo_intro.bk2' ...
[BINK-AUDIO-OWNER][V1.1.12] post_attract_guest_drain_released ...

FORBIDDEN RESULT
================
- visible Bink/RAD post-roll logo after attract_movie
- attract WaveOut continuing/restarting after attract_nominal_end
- post-attract NIHAV/FFmpeg host-audio extraction for logo_intro/title loop

FILES TOUCHED
=============
src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs
src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs

No MainWindow change.
No AudioOut/AudioOut2 source rewrite is needed: both already consult
IsStartupGuestAudioMuteActiveV116(), which V1.1.12 extends with the drain.
