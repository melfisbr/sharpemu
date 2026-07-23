# libc pthread_mutex stubs implementation

## Status: ✅ Complete

All three pthread_mutex functions are fully implemented in `KernelPthreadCompatExports.cs`.

### Implemented Functions

| Function | NID | Implementation |
|----------|-----|----------------|
| `pthread_mutex_init` | `ttHNfU+qDBU` (POSIX) / `cmo1RIYva9o` (sce:*) | `PthreadMutexInitCore()` at line 677 |
| `pthread_mutexattr_settype` | `mDmgMOGVUqg` (POSIX) / `iMp8QpE+XO4` (sce:*) | `PthreadMutexattrSettypeCore()` at line ~351 |
| `pthread_mutex_destroy` | `ltCfaGr2JGE` | `PthreadMutexDestroyCore()` at line 714 |

### Implementation Details

- **State Management**: Uses static `_mutexStates` dictionary instead of TLS variables (avoids per-thread overhead)
- **Attribute Storage**: Mutex attributes stored in static `_mutexAttrStates` dictionary  
- **Auto-registration**: All functions have `[SysAbiExport]` attributes for source-generator-based import stub wiring
- **Target Platforms**: Gen4 \| Gen5
- **Library**: `libKernel`

### Architecture Notes

The implementation follows the existing pattern in `KernelPthreadCompatExports.cs`:
1. Resolve/allocate opaque object via `TryAllocateOpaqueObject()`
2. Initialize state in static dictionaries (`_mutexStates`, `_mutexAttrStates`)
3. Write handle to target address via `KernelMemoryCompatExports.TryWriteUInt64Compat()`
4. Return `OrbisGen2Result` error codes

### Verification

- Build project to ensure stubs compile and registry generates correctly
- Test with PS5 game that triggers pthread_mutex operations during initialization
- Verify no Access Violation at import stub addresses after patching

## Tasks

- [x] Implement HLE stub for `pthread_mutex_init` (cmo1RIYva9o) - initialize mutex structure in static state dict
- [x] Implement HLE stub for `pthread_mutexattr_settype` (iMp8QpE+XO4) - handle attribute type switching  
- [x] Implement HLE stub for `pthread_mutex_destroy` - validate state and cleanup from static dict
