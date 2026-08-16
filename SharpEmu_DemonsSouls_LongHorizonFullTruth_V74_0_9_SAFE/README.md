# SharpEmu Demon's Souls — Long-Horizon Full Truth V74.0.9 SAFE

This package deliberately does **not** change emulator source.

The V74.0.8.2 comprehensive result proved that its 120-second horizon was
shorter than the previously successful V73.18 guest-first reference.

Reference comparison:

- V73.18 result ended around 479.5 seconds when natural
  `ps_studios_logo.bk2` was observed.
- V73.18 at ~120 seconds: about 14.8 GiB working / 20.2 GiB private.
- V74.0.8.2 after its transient peak settles around 6.1 GiB working /
  11.3 GiB private at 120 seconds.
- V74.0.8.2: compute failures 0, FailFast 0, device loss 0,
  EVENT_FASTPATH reached 2048.

A source/scheduler change based on the 120-second endpoint would therefore be
premature.

V74.0.9 runs the same comprehensive truth domains for a hard maximum of
600 seconds. If the natural guest Bink request occurs first, it keeps up to
60 additional seconds (within the hard horizon) to capture Y/UV/compositor
evidence.

It additionally enables one low-volume AGC target filter only:

    SHARPEMU_TRACE_RENDER_TARGET_ADDRESS=0x45D550000

This captures bound/writer/rejected evidence for the known 4K frontend
compositor without enabling full AGC shader tracing.

The live console reports every ~30 seconds:

- EVENT_FASTPATH max n;
- presenter timeline completed/submitted;
- seconds since event/timeline progress;
- 0x45D bound/writer/rejected counts;
- natural Bink and compute YUV counts;
- working/private memory;
- dedicated/shared GPU memory;
- GPU and CPU utilization.
