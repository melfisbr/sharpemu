SharpEmu Demon's Souls Post-Attract Title-Chain Guest Audio Fence V1.1.13 SAFE

PURPOSE
=======
Fix the remaining attract soundtrack audible during logo_intro_loop while
preserving the now-correct attract movie and V1.1.12 Bink post-roll fence.

RUNTIME-PROVEN ROOT CAUSE
=========================
V1.1.12 correctly:
- arms the attract Bink/RAD visual post-roll fence;
- stops the attract deterministic WaveOut;
- stops PlaySound;
- starts a 1500 ms guest AudioOut/AudioOut2 drain.

But that drain is time-based. It expires and logs guest_audio_restored=True
long before logo_intro_loop begins.

The runtime later states:
  TITLE_LOOP_AUDIO host_audio_probe=False guest_audio_owner=True
and attaches NIHAV as the VIDEO backend for logo_intro_loop.

Therefore the remaining soundtrack is guest AudioOut/AudioOut2, not a new
NIHAV host-audio decode.

V1.1.13
=======
The guest mute is now lifecycle-based:

  attract teardown
      -> title-chain guest mute ARMED

  logo_intro.bk2 attach
      -> HOLD

  logo_intro_loop.bk2 attach/repeat
      -> HOLD

  first different movie attach
      -> RELEASE

No guest thread is stopped.
AudioOut/AudioOut2 keep their normal pacing/consumption. Only host submission
remains silent while the title-chain latch is active.

HostMovieBridge is hooked directly before mode rewriting/audio probing because
the optimized logo_intro_loop path deliberately reports host_audio_probe=False.

PRESERVED
=========
- attract_movie RAD playback and correct attract music
- logo_intro RAD playback
- logo_intro_loop NIHAV VIDEO path
- V1.1.12 persistent Bink/RAD post-roll visual fence
- V1.1.9 WaveOut reveal sync
- V1.1.10 attract stem alignment
- Options/START skip
- completion shim
- post-Studios black cover
- guest pacing and guest execution

TOUCHED SOURCE
==============
src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs
src\SharpEmu.Libs\Media\HostMovieBridge.cs

No MainWindow changes.
No RAD renderer changes.
No AudioOut/AudioOut2 source rewrite is necessary because both already consult
IsStartupGuestAudioMuteActiveV116(), now extended with the lifecycle latch.
