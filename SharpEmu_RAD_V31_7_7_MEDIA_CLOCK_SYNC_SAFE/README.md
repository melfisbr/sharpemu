# SharpEmu RAD V31.7.7 — shared RAD media-clock A/V anchor

This revision is intentionally narrow. V31.7.6 already fixed the high CPU/GPU/RAM growth during `attract_movie.bk2`, and the user confirmed all three videos now play correctly. V31.7.7 preserves that hard gate unchanged and removes the remaining host-side audio lag.

## Why this is needed

The current boot sequence is injected by `HostMovieBridge` (`direct_boot` / `auto_boot_order`) before the title's normal guest sound/movie flow owns the boot sequence. Therefore the final architecture should indeed be guest/EBOOT-driven, but the current injected bridge cannot obtain natural guest A/V events for this sequence.

V31.7.6 started the attract sidecar after the RAD child HWND had already been revealed and also added `SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS=80`. That creates an avoidable audio-behind-video offset even when both streams run at exactly 1.0000x.

## V31.7.7 change

* preserves V31.7.6 real decoder lifecycle + HLE event gate + GPU backpressure;
* changes the default RAD audio anchor delay from 80 ms to 0 ms;
* adds a `beforeReveal` callback to the embedded RAD host API;
* for zero-track `attract_movie.bk2`, prepares the existing AT9 sidecar while RAD initializes;
* fires `NotifyPresentationStarted()` at the RAD playback anchor while the child HWND is still hidden;
* reveals the RAD child immediately after the audio trigger;
* keeps the existing +12.000 s content offset and 1.0000x tempo;
* does not change the first two videos, track selection, transition cutoff, or resource hard gate.

Expected runtime ordering for the third movie:

```text
bink2.rad_required_started
bink2.rad_renderer_window_ready
bink2.ds_intro_audio_start file='attract_movie.bk2'
bink2.rad_attract_audio_anchor_pre_reveal ... delay_ms=0
bink2.rad_before_reveal_callback ... success=True
bink2.rad_renderer_revealed file='attract_movie.bk2'
bink2.rad_host_attached ...
bink2.rad_guest_hard_gate_started ...
```

This is still a host media-clock bridge, not the final guest-driven implementation. A future architectural step should stop injecting the boot movies and instead intercept/implement the title's real movie/audio calls so the EBOOT/runtime owns the media clock naturally.
