# SharpEmu RAD V31.7.5 — cinematic resource gate + hard transition cutoff

This revision is based on the V31.7.4 runtime result. The first RAD-hosted movie is already visually correct, so the decoder/embedding path is preserved.

## What V31.7.4 proved

- RAD HWND embedding works for all three startup movies.
- `ps_studios_logo.bk2` embedded audio track 0 works.
- `attract_movie.bk2` has no embedded Bink audio and uses the existing Demon's Souls AT9 sidecar at +12.000 s / 1.0000x.
- During `attract_movie`, SharpEmu guest graphics/resource work continued behind the RAD child: V74 memory telemetry climbed to roughly 8.9 GB working set / 14.2 GB private while large texture/DCC activity continued.
- The accumulated checkout already contains `BinkHostPlaybackAssist.WaitForGuestCpuPermit()` in the native worker and `BinkHostPlaybackAssist.ShouldThrottleGuestGpu` in Vulkan. The external RAD path was not activating that movie session.
- Killing the RAD child 100 ms after nominal end still exposed the BinkPlay logo briefly.

## V31.7.5 changes

1. Immediately after a RAD HWND is verified and embedded, call `BinkHostPlaybackAssist.OnMovieFrame(moviePath)`.
2. Keep the session alive with a 200 ms host heartbeat while RAD is presenting.
3. Call `BinkHostPlaybackAssist.EndMovieSession(moviePath)` on renderer completion/dispose.
4. This reuses the existing CPU event-park and Vulkan guest-payload backpressure rather than adding a second scheduler hack.
5. Hide the RAD child 120 ms before the corrected nominal BK2 end and kill it at corrected nominal end with zero grace; the pre-reveal hidden HWND interval is subtracted from the timer so V31.7.4’s late boundary cannot expose post-roll branding.
6. Preserve first-video `/Z0 /T0`, stable HWND resize, and attract audio +12 s / 1.0000x.

No RAD/Bink binary, game media, AT9, BK2 or cached WAV is redistributed.
