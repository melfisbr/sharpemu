SharpEmu V74.0.67.2.12
DLSS + Demon's Souls BPE Secondary Caller Sentinel SAFE

RESULT OF THE LATEST RUNTIME
============================
The V2.11 RAX=payload repair worked for the original BPE caller.

Immediately afterward, the same linked-list helper faulted again at target 0x9
through a second caller not covered by the original guard.

Second caller evidence:
- BPE JobWorkerThread;
- LastImportNid GuchCTefuZw;
- RDI == R13;
- R15 == the canonical payload/end sentinel;
- same container shape head=1, adjacent=0;
- return-address bytes decode to:
    mov r13,rax
    cmp rax,r15
    je  end path
    mov eax,[r13+0x20]

V2.12 adds this second exact caller without making the recovery generic.

Required secondary gates:
- exact NID GuchCTefuZw;
- RDI == R13;
- R15 == payload;
- exact helper signature;
- exact container shape;
- readable return address;
- exact post-call instruction bytes.

The original tcVi5SivF7Q / RDI==R14 path remains unchanged.

Both variants return payload in RAX and clear RCX.

No absolute guest address is hardcoded.

DLSS
====
The runtime segment still shows selected=off/provider=0/dlss_dispatches=0.
It begins well after startup, so the one-time V2.10.2 PROVIDER_INIT diagnostic
is not present in the supplied tail. V2.10.2 instrumentation is preserved;
a full/earlier runtime log is needed to see its exact NGX last_error.

DLSS is proven only by:
  selected=dlss
  state=active
  dlss_dispatches>0
