# SharpEmu Demon's Souls — Natural Bink Descriptorless Direct Fallback V74.0.11 SAFE

V74.0.10 proved the native-lane correction:

- Core.Res.TaskManager: 4 -> 64,881 imports
- EVENT_FASTPATH: 2,048 -> 16,384
- presenter timeline: 1,318 -> 14,604
- 0x45D550000: 949 binds / 949 GPU writers
- natural `ps_studios_logo.bk2` request reached
- compute failures / FailFast / device loss remain zero

The next failure is now exact:

    bink2.first_frame_primed size=640x360 frame=0
    Bink2 NIHAV bridge attached: ps_studios_logo.bk2
    bink2.yuv_pair_not_found ... textures=0 []

There is a valid host-decoded movie frame, but at that moment the guest exposes
zero draw/compute texture descriptors. A Y/UV substitution cannot possibly
bind to an empty descriptor list.

V74.0.11 adds a narrow fallback:

1. only when host natural Bink playback is active;
2. only when guest texture descriptor count is zero;
3. never while HostMovieBridge direct auto-presentation is active;
4. directly submits the host BGRA frame and temporarily gives it exclusive
   presentation ownership;
5. pumps the natural decoder from the present tick, so movie playback no
   longer depends on new guest graphics/compute dispatches;
6. if a real guest Y/UV pair later appears, direct fallback is released
   immediately and the existing V73.20/V74.0.6.3 YUV substitution resumes.

The guest still reads the real BK2. This patch does not restore the old
one-frame completion shim and does not fake movie completion.

Presenter baseline:
0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66

V74.0.11 presenter:
B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41

Native lane prerequisite/preserved:
F4AF1A786A5F949F420050BA763762918D1AFAD98270684A26EBF5E6D1B82E38
