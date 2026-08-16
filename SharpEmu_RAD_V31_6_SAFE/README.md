# SharpEmu RAD V31.6 — Demon's Souls attract audio

V31.5.1 proved the external RAD path is finally decoding the three boot movies
with correct video.  The remaining symptom was audio only: the third movie,
`attract_movie.bk2`, was silent.

The key distinction is container ownership:

- `ps_studios_logo.bk2` / `logo_intro.bk2`: keep RAD video + embedded Bink audio.
- `attract_movie.bk2`: V31.6 reads the Bink container header first.
- If `attract_movie.bk2` reports zero embedded audio tracks, SharpEmu starts the
  already-audited Demon's Souls opening AT9 stems at +12.000 seconds.
- The sidecar uses **1.0000 tempo**.  The old V30 0.7000 tempo existed only to
  compensate for slow NIHAV video and must not be reused now that RAD is at
  native playback speed.
- No audio sidecar is started for a movie that actually has embedded tracks.
- RUN_3 prebuilds the +12 s / 1.0000x WAV cache, so the third movie does not wait for ffmpeg on first playback.

The package does not include RAD binaries, Bink SDK DLLs, game AT9 files, WAV
files, or any copyrighted game media.

## Run

From the repository root:

```powershell
.\SharpEmu_RAD_V31_6_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
.\SharpEmu_RAD_V31_6_SAFE\RUN_2_PRECHECK.cmd
.\SharpEmu_RAD_V31_6_SAFE\RUN_3_APPLY_BUILD.cmd
.\SharpEmu_RAD_V31_6_SAFE\RUN_4_DEMONS_SOULS_TEST.cmd
```

`RUN_2_PRECHECK` prints the Bink audio-track count/IDs for all three boot movies.
For the observed failure we expect `attract_movie.bk2 ... tracks=0`.

During the third movie, look for:

```text
bink2.rad_audio_header file='attract_movie.bk2' ... tracks=0
bink2.rad_attract_audio_sidecar ... offset_s=12.000 tempo=1.0000
bink2.ds_intro_audio_start file='attract_movie.bk2' ... mode=tail12
```

The first two movies should remain unchanged and should not receive the AT9
sidecar.

Rollback:

```powershell
.\SharpEmu_RAD_V31_6_SAFE\RUN_ROLLBACK_LAST.cmd
```
