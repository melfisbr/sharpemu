V61.23.6.1.1 SAFE — source audit for remaining post-video stall.

V61.23.5 evidence:
- epoch_reset=0 and device_lost=0.
- All three Bink movies complete.
- A 3840x2160 guest frame is presented.
- Runtime continues to hundreds of submissions, but the title remains visually stalled.
- New unsatisfied label pairs recur at 0x442EFF3/2xx, 0x442CFF3/2xx, 0x442BFF3/2xx.
- Many zero-dimension indirect/direct dispatches and sampled non-resident render targets remain.

This package does NOT modify emulator source. It collects the exact current source
windows needed to make the next semantic patch safely, rather than guessing against
an unseen local source revision.
