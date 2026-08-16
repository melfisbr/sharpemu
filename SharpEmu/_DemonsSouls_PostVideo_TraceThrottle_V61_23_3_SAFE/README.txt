SharpEmu V61.23.3 — Post-video realtime/trace-throttle correction

Evidence from V61.23.2:
- stderr.log exceeded 110 MB.
- 5,094 WAIT suspensions and 7,824 queue resumes were logged.
- 49 guest flip captures occurred and deviceLost stayed false.
- On-screen overlay showed about 0.1 FPS.

The diagnostic itself was perturbing runtime heavily.
V61.23.3 disables high-frequency AGC/shader/Vulkan resource tracing and
collects only low-frequency process telemetry plus normal emulator logs.

No synchronization value is fabricated and no WAIT_REG_MEM is bypassed.
