# SharpEmu Demon's Souls — FastBoot + Startup Bink Handoff V74.0.12 SAFE

This package corrects both issues visible in the V74.0.11.2 result.

## Processing bottleneck

The previous comprehensive diagnostic generated about 131 MiB / 1.32 million
stderr lines. More than 1.1 million were per-transition guest-thread logs.
Those are disabled in the timed V74.0.12 run. The new collector does not
re-read the entire growing log; it processes only appended bytes.

This lets the measured boot run close to normal emulator conditions instead
of benchmarking Console.Error and PowerShell/WMI diagnostics.

## PlayStation Studios movie handoff

The host decoder itself is healthy: `ps_studios_logo.bk2` completed in 9.48 s
at frame 254.

The guest handoff was not healthy. The existing `BinkGuestCompletionShim`
was never used because `TryTakeOverGuestMovie()` returned false
unconditionally.

V74.0.12 enables that existing shim only for the two known one-shot startup
movies:

- ps_studios_logo.bk2
- logo_intro.bk2

`logo_intro_loop.bk2` is explicitly excluded because it is the title /
Press-Start loop.

The presenter also starts the direct host fallback from its render tick for
those one-shot startup movies, so the guest may safely wait for real host
playback completion. When playback completes, exclusive visual ownership is
released immediately.

Presenter baseline:
1F4D6BF5B71AC0B773052D0FFC9C267CF8C9A0CD3868A33E5368FE8F828088CA

Presenter V74.0.12:
B88D645BDF3890A95DEDF91F3CF76B1BB97F4F108EB288DA429A89B9FB774245
