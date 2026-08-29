SharpEmu V76.3.20.1 — Event-First WAIT / 100 ms Producerless Watchdog

V19 still accumulated ~42k WAIT_REGISTRY full collects in ~192 seconds.
The existing source already has exact producer-latched wakeups and a dedicated
fast-only drain. This package makes those paths authoritative for normal GPU
producer traffic and pushes the legacy global memory scan to the maximum
source-supported 100 ms cadence.

Producer-backed waits remain immediate because WaitMonitorSignalGate is pulsed
when exact producer evidence is latched. The 100 ms path remains only as the
correctness watchdog for direct CPU writes, retries and recovery.

No wait value is forged or changed. WAIT_REG_MEM comparison semantics remain
unchanged. Requires V20.0 and is cumulative.
