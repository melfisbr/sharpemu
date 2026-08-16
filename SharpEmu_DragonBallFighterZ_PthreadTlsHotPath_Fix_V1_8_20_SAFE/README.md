# DBFZ Pthread TLS HotPath Fix V1.8.20 SAFE

V1.8.19 proved the graphics threads are not starved: RenderThread/RHI/AGC all
execute and later block normally; RenderThreadTimeoutCount=0.

The remaining measurable problem is startup throughput: the title reaches more
than 92 million import calls before the first Vulkan splash (~199.36 s).
scePthreadGetspecific is one of the repeated sparse checkpoints.

Current getspecific performs:
1. current guest-thread lookup;
2. global `_tlsKeys.ContainsKey(key)`;
3. outer ConcurrentDictionary lookup by guest thread;
4. inner ConcurrentDictionary lookup by key.

For getspecific, invalid key and valid-but-unset both already return zero, so the
global key-existence lookup is redundant for the current ABI behavior. Each
GuestExecutionRunner also keeps one host thread per guest pthread, so this patch
caches only the per-thread values dictionary reference in ThreadStatic storage.
Actual key/value reads remain in ConcurrentDictionary; setspecific updates the
cached reference and destructor cleanup clears it.

No mutex, condition variable, scheduler, Vulkan, Pad or SharePlay semantics are
changed.
