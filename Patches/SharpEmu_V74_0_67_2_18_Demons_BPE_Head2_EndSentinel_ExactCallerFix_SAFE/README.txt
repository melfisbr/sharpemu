SharpEmu V74.0.67.2.18
Demon's Souls BPE Head2 End-Sentinel Exact Caller Fix SAFE

LATEST CRASH
============
The supplied runtime ends with:
  Code 0xC0000005
  BPE JobWorkerThread CPU11
  last_import=tcVi5SivF7Q
  helper read AV target=0xA
  RAX=2
  RCX=2
  RDI==R14

The faulting helper is the same linked-list traversal previously handled by
V2.11/V2.12:
  mov rcx,[rcx+8]
  test rcx,rcx
  jne ...
  ret

NEW CONTAINER VARIANT
=====================
The captured container has:
  [RDI+0x00] = 2
  [RDI+0x08] = 0
  [RDI+0x10] = canonical payload/end sentinel

The return address shows the primary caller:
  mov r14,rax
  cmp rax,[rbp-0xC70]
  je ...
  mov eax,[r14+0x20]

RBP-0xC70 points to the same canonical payload stored at [RDI+0x10].

Therefore the head=2 low value is another end/empty traversal sentinel variant,
and the caller contract remains the same one proven by V2.11:
return the canonical payload/end-sentinel pointer, not null.

V2.18 EXACT GATES
=================
Recovery runs only when ALL of these are true:
- read AV target exactly 0xA;
- BPE JobWorkerThread;
- last import exactly tcVi5SivF7Q;
- RAX=2 and RCX=2;
- RDI==R14;
- exact traversal helper bytes;
- container head=2;
- adjacent qword=0;
- payload is canonical;
- exact primary caller opcode shape;
- caller's [rbp-0xC70] equals that same payload.

No absolute guest RIP, caller address, container address, payload address or
resource address is embedded.

RECOVERY
========
  RAX = canonical payload
  RCX = 0
  RIP = faulting RIP + 4

The guest executes its own test/jne/ret and then its own equality comparison.

The old V2.11 target=0x9 recovery and V2.12 secondary caller recovery remain
untouched.

V2.17
=====
V2.18 is cumulative:
- if all V2.17 source markers are already present, they are preserved;
- if none are present, V2.17 is applied first;
- a partial V2.17 source state is refused.

DLSS/provider code is unchanged.
