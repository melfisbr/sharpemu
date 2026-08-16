# SharpEmu RAD V31.7.2 — Embedded Host API

This package addresses the two V31.6 observations:

1. `radvideo64.exe`/BinkPlay rendered correctly but appeared as an independent
   desktop window.
2. `attract_movie.bk2` external AT9 audio was started before a reliable RAD
   first-frame anchor and could therefore lead the video.

## What V31.7.2 implements

- `IRadBinkHostApi`: a SharpEmu-facing backend boundary.
- `RadBinkEmbeddedHostApiV724323171`: Windows implementation that finds the
  SharpEmu SDL HWND, hides BinkPlay, changes the RAD HWND to `WS_CHILD`, reparents
  it with `SetParent`, and keeps it resized to the SharpEmu client area.
- Strict policy: if reparenting fails, RAD is killed.  The package does not leave
  an independent BinkPlay window as a fallback.
- `attract_movie` audio starts only after successful embedding plus a decode
  activity anchor.  `SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS` defaults to 80 ms.

## Important distinction: hosted player vs. true in-process Bink SDK

The audited RAD Video Tools installation contains `radvideo64.exe`/BinkPlay but
no Bink SDK runtime DLL.  RAD documents the Windows SDK runtime as a DLL that
ships with the integrating application.  Therefore V31.7.2 cannot truthfully turn
RAD Video Tools into a same-process decoder.  It integrates the official RAD
renderer into the SharpEmu window and exposes an API boundary that can later be
implemented by a licensed Bink SDK provider without changing HostMovieBridge.

No proprietary RAD/Bink binary is included in this package.

## V31.7.2 repair

This revision fixes the user's V31.7 install failure before runtime testing:

- robust `%~dp0.` package-root passing in `RUN_1_VALIDATE_PACKAGE.cmd`;
- semantic audio-hook validation instead of the brittle contiguous
  `BinkDemonSoulsIntroAudioV7243227.NotifyPresentationStarted` text marker;
- duplicate `toolPath` constructor argument removed;
- `SetParent` last-error handling made deterministic for a former top-level RAD
  HWND.

The V31.7 attempt rolled back before build, so V31.7.2 is intended to be applied
on top of the still-working V31.6 baseline.

## V31.7.2 compiler repair

V31.7.1 reached the real SharpEmu.Libs build and exposed CS0266 at the two
GetWindowThreadProcessId calls.  The Win32 signature was already correct.  The
problem was C# name binding: `(window, _) =>` declares `_` as the nint lParam
parameter, so `_ = GetWindowThreadProcessId(...)` tried to assign the returned
uint into nint.  V31.7.2 renames that callback parameter to `ignored`; the
assignment target `_` is then the intended discard.  No ABI or behavior change
was required.
