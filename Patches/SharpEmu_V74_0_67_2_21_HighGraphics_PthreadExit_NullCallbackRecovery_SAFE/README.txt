SharpEmu V74.0.67.2.21
HighGraphics pthread_exit Null Callback Recovery SAFE

CRASH PROOF
===========
The supplied Debug runtime now successfully loads the DLSS native provider:
  exists=1 loaded=1
and NGX instance-extension negotiation begins.

The crash happens later and is unrelated to provider deployment.

Captured AV:
  code=0xC0000005
  RIP=0
  access=execute
  target=0
  guest thread=HighGraphics
  last_import=3kg7rT0NQIs (scePthreadExit)
  last import result_valid=False
  last import RDI=0

SOURCE CONTRACT
===============
scePthreadExit currently:
  1. RunThreadLocalDestructors(ctx)
  2. RunThreadDtors(ctx)
  3. RequestCurrentEntryExit("scePthreadExit", value)

Both destructor paths may call guest callbacks through TryCallGuestFunction.
The observed execute-null occurs while scePthreadExit is still in progress.

FIX
===
V2.21 adds an exact VEH recovery only for:
  AV execute
  target=0
  RIP=0
  HighGraphics
  last import exactly scePthreadExit NID
  import result still invalid/in-progress
  exit value RDI=0
  valid active host-return sentinel and writable active return slot

Recovery:
  RAX=0
  RIP=ActiveEntryReturnSentinelRip

This terminates only the failing nested cleanup callback. Control returns to
managed pthread-exit cleanup; scePthreadExit then remains responsible for the
normal guest-thread exit.

It does NOT:
- recover arbitrary RIP=0 faults;
- skip WAIT_REG_MEM;
- abort the HighGraphics worker;
- mark the guest thread abandoned;
- change DLSS/provider behavior;
- change V2.19 profile passthrough;
- change V2.20 Debug/Release deployment.

EXPECTED
========
If the same boot case occurs:
  [V74.0.67.2.21][PTHREAD_EXIT_NULL_CALLBACK] ...

and boot should continue instead of process exit -1073741819.
