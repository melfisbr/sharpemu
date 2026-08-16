# Dragon Ball FighterZ Import-Loop Unlock Boundary Fix V1.7.6

Target eboot SHA256: `106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018`

## V1.7.5 proved APR payload correctness

```text
Pak0PayloadCallCount=1280
Pak1PayloadCallCount=2
Pak0PayloadReadableAfterCount=1280
Pak1PayloadReadableAfterCount=2
Pak0PayloadChangedCount=1279
Pak1PayloadChangedCount=2
Pak0RequestedBytes=104908226
Pak1RequestedBytes=8652123
GlobalShaderCacheFatal=False
AbortCalled=False
NativeException=False
LastVEH=
```

Real PAK data reached guest memory. Examples included PNG signatures and readable
configuration/text data.

The run then ended because SharpEmu itself forced a guest unwind:

```text
Import-loop guard fired at import#51347456:
nid=tn3VlD0hG60
ret=0x0000000800C00815
```

`tn3VlD0hG60` is `scePthreadMutexUnlock`.

The current loop guard already resets its pattern history on:
- `sceKernelUsleep`
- pthread condition waits

but not on successful mutex/rwlock unlock operations.

## V1.7.6

This revision adds the four existing normal-path unlock exports as loop-guard
boundaries:

```text
tn3VlD0hG60  scePthreadMutexUnlock
2Z+PpY6CaJg  pthread_mutex_unlock
EgmLo6EWgso  scePthreadRwlockUnlock
+L98PIbGttk  pthread_rwlock_unlock
```

The import-loop guard remains enabled globally. Unresolved/import-only tight loops
that never make synchronization progress can still trip it.

No pthread return value, ownership rule, AMPR behavior, PAK data, game file or
guest memory is modified.
