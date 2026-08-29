SharpEmu V76.3.20.2 — Dual Queue Deep Feed A/B

This is the aggressive third package in the series. It is intentionally tested
only after V20.0 and V20.1.

V19 has real graphics+compute physical queues, but sustained render still shows
long Idle windows. This package gives the already-working dual-queue backend a
deeper bounded host feed:
- pending work 192 -> 256
- retained payload 96 -> 128 MiB
- submission burst 4 -> 8
- max in-flight guest submissions 16 -> 24
- watched-producer scan depth 512 -> 1024

It preserves:
- six reserved host lanes;
- resource-scoped dual-queue hazards/timeline;
- compute chain 4;
- Async AGC;
- V20.0 residency;
- V20.1 event-first waits;
- safe memcpy;
- Bink and all visibility boundaries.

This is an A/B performance package. If boot/FPS/latency regresses, RUN_5
restores the immediately previous V20.1 source.
