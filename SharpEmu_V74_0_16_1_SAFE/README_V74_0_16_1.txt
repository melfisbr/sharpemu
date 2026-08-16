V74.0.16.1 repairs the V74.0.16 patcher result anchor. It does not change the intended DCC-history semantics.

SharpEmu V74.0.16.1 SAFE — DCC resident-alias history + generation-safe snapshot reuse

V74.0.15 result:
- 320MB array single-flight: owner=1, reuse=15, duplicate snapshot bytes avoided=4800MB.
- max allocation burst: 5292 -> 850MB/2s compared with V74.0.14.
- peak process tree: ~8013MB working / ~12352MB private.
- no Vulkan DeviceLost and no heap corruption.
- main loop: 35.7169s; no natural startup movie within 241s.
- repeated DCC sampled surfaces still entered the safe unresolved-DCC fallback.

V74.0.16.1:
- caches only DCC aliases first proven by the ordinary resolver and still backed by a live GPU image;
- history is opt-in and short-lived (runner: 2000ms), default disabled;
- never CPU-decodes DCC bytes and never manufactures texture contents;
- makes V74.0.5 non-DCC snapshot TTL configurable; write generation remains in the cache key;
- default snapshot TTL remains 2000ms, runner uses 10000ms;
- preserves V74.0.15 array single-flight, TBB=2 and stable 768MB texture cache.
