# V1.8.37.1 result analysis

Observed:
- Import88M: 198426 ms
- Vulkan: 200632 ms
- Splash: 201186 ms
- APR cooperative samples: 0
- APR host fallback samples: 37, all guest=0
- pthread_join cooperative samples: 0
- pthread_join host fallback: 1, waiter=0
- FatalCount: 0

Compared with V1.8.35:
- Vulkan: +8659 ms
- Splash: +8947 ms

Conclusion:
The scheduler-owned waiter mechanism was installed but the startup APR/join caller is the top-level
external/root guest executor, whose CurrentGuestThreadHandle is intentionally zero. Therefore the
next correction should not force that root executor into the scheduler. Instead V1.8.38 reuses the
stable synthetic pthread identity already maintained by KernelPthreadState only for the safe
identity/TLS import hotpath.
