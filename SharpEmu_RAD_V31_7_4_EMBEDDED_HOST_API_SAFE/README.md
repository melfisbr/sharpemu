# SharpEmu RAD V31.7.4 — PS5-like Embedded Movie Transition Repair

This revision is based on the successful V31.7.3 embedded-host result. V31.7.3
proved that all three RAD/BinkPlay renderer HWNDs can be reparented into the
SharpEmu SDL window, but the runtime test exposed three remaining presentation
problems:

1. `ps_studios_logo.bk2` contains one embedded Bink audio track (`id=0`) but was
   silent with the implicit BinkPlay default.
2. BinkPlay remained alive for roughly 2.2 seconds after the nominal movie frame
   duration and exposed its own BINK VIDEO post-roll/logo inside SharpEmu.
3. `attract_movie.bk2` stuttered while its external AT9-derived audio sounded
   slow. V31.7.3 also called `SetWindowPos(...FRAMECHANGED...)` every 100 ms even
   when the SharpEmu client size had not changed, and the runtime opened the
   legacy `from12-v29-1p000.wav` attract cache.

## V31.7.4 changes

- Parses Bink frame count, dimensions, FPS and embedded audio-track metadata from
  the BK2 header before launch.
- Starts BinkPlay with `/I2 /Z0`; when embedded tracks exist, explicitly selects
  them in track-index order (`/T0` for `ps_studios_logo.bk2`).
- Keeps the RAD renderer HWND hidden while BinkPlay initializes, reparents it,
  waits for the playback activity anchor, and only then reveals it.
- Starts a nominal-duration timer from the playback-ready point. At the BK2 frame
  duration plus a small configurable grace (`SHARPEMU_RAD_NOMINAL_END_GRACE_MS`,
  default 100 ms), the child HWND is hidden before the RAD process is stopped.
  BinkPlay's own post-roll logo therefore must never become the transition frame.
- Promotes the RAD renderer to `AboveNormal` process priority when Windows permits, so heavy guest CPU work is less likely to starve video cadence.
- Replaces the 100 ms `SWP_FRAMECHANGED|SWP_SHOWWINDOW` churn with a 250 ms size
  check that calls `SetWindowPos` only when the SharpEmu client dimensions have
  actually changed. No `SWP_FRAMECHANGED` is used during playback.
- Rebuilds the full native-rate opening mix and the exact runtime attract-audio cache
  `demons-souls-intro-<key>-from12-v29-1p000.wav` on every apply using
  `atempo=1.0000`, 48 kHz stereo PCM. This removes stale tempo data from the file
  that `BinkDemonSoulsIntroAudioV7243227` actually opens.
- Keeps the existing rule that `attract_movie.bk2` (zero embedded Bink tracks)
  uses the external Demon's Souls opening stems only after the embedded RAD
  playback anchor.
- NIHAV/FFmpeg video fallback remains forbidden in RAD mode.

## Expected runtime markers

For the first movie:

    bink2.rad_audio_track_select file='ps_studios_logo.bk2' switch='/T0' output=windows-audio

For every movie:

    bink2.rad_renderer_revealed ... initial_logo_suppressed=True
    bink2.rad_host_attached ... render_location=sharpemu-child-window
    bink2.rad_nominal_end ... postroll_logo_suppressed=True

A normal fixed-size run should report only a very small number of
`bink2.rad_host_resize ... changed=True` events instead of continuous resize
traffic.

## Important distinction

This is still the RAD decoder process hosted as a child HWND of SharpEmu. The
RAD Video Tools installation audited on the test machine did not contain a Bink
SDK runtime DLL, so same-process Bink SDK decoding is not claimed by this
package. No proprietary RAD/Bink binary or game media is redistributed.
