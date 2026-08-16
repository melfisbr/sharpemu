# SharpEmu RAD V31.7.6 — real guest hard gate + attract A/V stabilization

This revision preserves the V31.7.5 playback path that already made
`ps_studios_logo.bk2` and `logo_intro.bk2` play correctly inside the SharpEmu
window.

## Root cause confirmed by V31.7.5

The V31.7.5 result reported `RAD_GUEST_THROTTLE_BEGIN=3`, but
`GUEST_GPU_BACKPRESSURE_MARKERS=0`. During `attract_movie.bk2`,
`Core.Res.TaskManager` continued entering the V74 native lane and SharpEmu
continued creating guest images, buffers, compute pipelines and texture
snapshots. The run reached about 7006 MiB working set and 12383 MiB private
memory before the user stopped the 117 s movie.

The V31.7.5 RAD bridge called `BinkHostPlaybackAssist.OnMovieFrame()` and
`EndMovieSession()`. In the accumulated Bink helper lineage those compatibility
entry points are no-ops. V31.7.5 also did not set
`SHARPEMU_BINK_THROTTLE_GUEST_GPU=1`, which is a hard prerequisite of
`ShouldThrottleGuestGpu`.

## V31.7.6 changes

* The embedded RAD child starts the real decoder lifecycle with
  `NotifyHostMovieDecoderStarted(moviePath)`.
* V31.7.6 verifies (and, only if the original V14 anchors are still present,
  restores) the V14 lifecycle hooks that pair decoder start/stop with
  `HostMovieExecutionGateV7243214.Begin()/End()`.
* The RAD bridge does **not** call the HLE gate directly, avoiding a double
  session count. Teardown is exactly-once through
  `NotifyHostMovieDecoderStopped()`.
* RUN_4 forces `SHARPEMU_BINK_THROTTLE_GUEST_GPU=1`.
* `ShouldThrottleGuestGpu` is reordered so an active decoder wins over a stale
  boot-complete latch. This is required for the long third movie.
* RUN_4 enables the lightweight Bink session log and post-movie working-set trim.
* The heartbeat remains telemetry only; it no longer pretends to activate the
  gate.
* Transition cutoff, `/I2 /Z0 /T0`, child-HWND embedding and the first two
  movies are unchanged.
* `attract_movie` sidecar remains +12.000 s / 1.0000x. No additional `atempo`
  correction is applied until the video clock is no longer starved by guest
  work.

## Expected proof

During the third video, the result should show real lifecycle markers:
`RAD_HARD_GATE_STARTED`, `HOST_MOVIE_DECODER_STARTED`, and either guest GPU
backpressure or no new `Core.Res.TaskManager` native-lane entries. The new
summary reports `ATTRACT_CORE_RES_NATIVE_ENTERS_DURING_HARD_GATE`,
`ATTRACT_PEAK_WORKING_MB` and `ATTRACT_PEAK_PRIVATE_MB` for direct comparison
with V31.7.5.

No RAD/Bink executable, SDK DLL, BK2, AT9 or generated WAV is redistributed.
