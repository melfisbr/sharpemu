# V74.0.77.2 SAFE

Target: Demon’s Souls PPSA01341 post-attract guest-state completion.

This patch is intentionally narrow: it changes only `HostMovieBridge.cs` and
reuses the already-existing one-frame Bink guest completion contract. It does
not replace the guest UI, does not force a framebuffer, and does not auto-play
the next movie.

The precheck performs a fresh local audit of
`F:\JOGOSPS5\PPSA01341\eboot.bin` (override with `SHARPEMU_DEMONS_EBOOT`) and
requires the Bink/AGC state-machine strings before any source change.
