SharpEmu Demon's Souls Title-Loop Audio Release V1.1.14 SAFE

VERIFIED PROBLEM
================
V1.1.13 fixed the attract soundtrack leaking into the title transition, but
runtime telemetry proves that it also muted legitimate guest-owned audio while
logo_intro_loop.bk2 was active.

Evidence:
  title_chain_guest_mute_hold ... file='logo_intro_loop.bk2'
  TITLE_LOOP_AUDIO ... host_audio_probe=False guest_audio_owner=True

While logo_intro_loop frames were actively decoding, AudioOut2 was still
silenced with non-zero peaks:
  peak=0.1005
  peak=0.1310
  peak=0.1122

Therefore V1.1.13 held the guest-audio latch one movie too far.

V1.1.14
=======
Correct lifecycle:

  attract_movie end
      -> arm guest discard

  logo_intro.bk2
      -> keep discard active
      -> stale attract guest PCM continues to be consumed silently

  logo_intro_loop.bk2
      -> stop any stale host WaveOut/PlaySound again
      -> release V1.1.13 guest-audio latch
      -> guest owns title-loop audio

If the user skips so quickly that the old V1.1.12 1500 ms minimum drain is
still active, that small residual drain remains authoritative. It then expires
normally. This preserves the anti-bleed protection without permanently
silencing the loop.

UNCHANGED
=========
- attract_movie RAD video/audio behavior
- logo_intro RAD video behavior
- logo_intro_loop NIHAV VIDEO backend
- V1.1.12 Bink/RAD post-roll visual fence
- Options/START skip
- completion shim
- black cover
- AudioOut/AudioOut2 pacing

TOUCHED SOURCE
==============
src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs

HostMovieBridge V1.1.13 hook is preserved and reused.
