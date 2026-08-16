# DBFZ NativeWorker Starvation Fix V1.8.18 SAFE

Evidence from V1.8.17.6:
- import setup optimization worked: 1 full setup, 7 cache hits;
- native worker prewarm is 8/8 with max_concurrent=16;
- guest dedicated threads create 1..14 run successfully;
- later guest threads are created but the critical AGC/RHI/Render/RTHeartBeat threads
  show no DEDICATED run;
- splash still appears at ~198.6 seconds;
- no fatal/abort during the 240-second window.

This A/B raises NativeWorkerMaxConcurrent from 16 to 32 and prewarms only 12.
It does not change GuestExecutionRunner, ready-dispatch semantics, Vulkan ordering,
or import handling. The test specifically measures whether guest threads created
after n=14 begin executing.

If n>=15 threads still never run with cap 32, the next repair should instrument/fix
native executor rent/return ownership rather than increasing capacity again.
