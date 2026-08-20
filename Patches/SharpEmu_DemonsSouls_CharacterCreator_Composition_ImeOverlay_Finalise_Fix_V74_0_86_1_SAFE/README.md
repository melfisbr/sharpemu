# SharpEmu Demon's Souls Character Creator / UI Composite / IME Overlay / Finalise Fix V74.0.86.1 SAFE

This SAFE patch targets four symptoms observed in Character Creation:
1. NEW GAME / Character Creator UI showing green-magenta artifacts.
2. Host text input working, but with a very simple dialog instead of a PS-style OSK.
3. Character model not appearing because UI-Bink composition can bleed into scene sampling.
4. Finalise path still vulnerable to an access-violation after the UI/IME path completes.

It upgrades V74.0.86 by:
- merging the presenter-owned UI-Bink frame snapshot + sticky sampled-plane protection,
- preserving the V74.0.86 typed DCC guard,
- replacing the small input form with a larger OSK-style overlay,
- adding runtime evidence for whether Finalise still hits an access violation.
