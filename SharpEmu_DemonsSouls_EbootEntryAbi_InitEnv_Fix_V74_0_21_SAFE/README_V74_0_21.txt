SharpEmu V74.0.21 SAFE — Demon's Souls EBOOT entry ABI + libc _init_env repair

PURPOSE
This package corrects the process-entry handoff discovered during the EBOOT/guest audit.
It deliberately does NOT apply the V74.0.20 HostMovieBridge boot-order change.

SOURCE CHANGES
1. CpuDispatcher.cs
   - expands EntryParams from the reduced 0x20 layout to 0x118 bytes;
   - supports argv[33] instead of only three inline pointers;
   - writes the real guest entry address at +0x110;
   - keeps the current native return trampoline unchanged for this revision;
   - emits a compact [V74.0.21][ENTRY_ABI] frame diagnostic.

2. DirectExecutionBackend.cs
   - allows libc _init_env to use the already-loaded LLE libc implementation only when
     SHARPEMU_LLE_INIT_ENV=1;
   - default behavior outside the diagnostic runner remains gated.

3. KernelExports.cs
   - replaces the silent _init_env HLE no-op with a compatibility fallback that validates
     the incoming EntryParams and logs whether the full 0x118 layout reached libc;
   - return semantics remain success-compatible if LLE _init_env is unavailable.

RUN_4 TEST PROFILE
- SHARPEMU_BINK_AUTO_BOOT=0: no host-forced movie order during this ABI test.
- SHARPEMU_LLE_INIT_ENV=1 and SHARPEMU_LLE_LIBC_SAFE_ONLY=1.
- SHARPEMU_LOG_PROC_PARAM=1 and SHARPEMU_LOG_PROC_PARAM_PTRS=1.
- Stops automatically after entry/proc-param/init-env proof plus a short observation window,
  or at the absolute diagnostic deadline.

NOT CHANGED
- HostMovieBridge boot sequence / V74.0.20.
- Native DirectExecutionBackend CALL-vs-JMP entry trampoline.
- GPU/AGC, texture, Bink decoder, audio or pthread behavior.

EXPECTED EBOOT
F:\JOGOSPS5\PPSA01341\eboot.bin
SHA256: 22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E
