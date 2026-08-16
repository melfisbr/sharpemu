V74.0.23 fixes the next measured bottleneck after V74.0.22.

V74.0.15 removed the concurrent 320 MiB array snapshot explosion, but the accumulated V73.0.19.1 cache validator still classifies the exact 80-layer 1024x1024 array at 0x102A400000 as stale with reason=missing-baseline. V74.0.22 logged 26 such refreshes in 173.95 s, while ARRAY_SINGLEFLIGHT reuse reached count=384.

V74.0.23 adds an opt-in fast path BEFORE that validator. It applies only to array uploads >=64 MiB, only when VulkanVideoPresenter reports the exact TextureContentIdentity as already resident, and only while GuestImageWriteTracker.PeekDirty(address) is false. It does not fake pixels, remove layers, or create a replacement texture. The first materialization still follows the full existing path.

The feature defaults OFF. RUN_4 alone sets SHARPEMU_LARGE_ARRAY_CACHE_TRUST=1. V74.0.21 Entry ABI/_init_env remains required. HostMovieBridge is not modified and host Bink auto boot remains OFF.
