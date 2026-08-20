SharpEmu V74.0.67.2.11
DLSS + Demon's Souls BPE End-Sentinel Return Fix SAFE

WHAT THE LATEST RUNTIME PROVED
==============================
DLSS was NOT active in that run:
  selected=off
  provider=0
  caps=0x0
  dlss_dispatches=0
  reason=precomposite_provider_init_failed

The scene source itself was already correct:
  input=2560x1440
  output=3840x2160
  color=1
  depth=1
  motion=1

The log contains no V74.0.67.2.10.2 runtime marker, so that run does not prove
or disprove the V2.10.2 lazy LastError/provider-init correction.

WHY THE EMULATOR CRASHED AFTER THE THIRD MENU
==============================================
The previous BPE low-sentinel recovery DID trigger successfully:

  rip=0x8007B6873
  target=0x9
  payload=<canonical pointer>
  old recovery -> RAX=0

The recovered guest helper returned to this caller sequence:

  call 0x8007B6860
  mov  r14, rax
  cmp  rax, [rbp-0xC70]
  je   end_path
  mov  eax, [r14+0x20]

The crash dump proves:
  RAX=0
  R14=0
  AV target=0x20

and the caller's [rbp-0xC70] value equals the canonical payload pointer already
captured by the BPE recovery.

Therefore returning null was semantically wrong. The empty/end-list helper must
return the guest's end-sentinel pointer, not null.

V74.0.67.2.11 FIX
==================
Inside the already evidence-gated V74.0.67.2.4.1 recovery:

OLD:
  RAX = 0
  RCX = 0
  resume test/jne/ret

NEW:
  RAX = payload
  RCX = 0
  resume test/jne/ret

The caller then receives the actual end sentinel, its own CMP should take the
existing equality branch, and the null R14+0x20 dereference is avoided without
skipping the caller or hardcoding a runtime resource address.

All original BPE evidence gates are preserved:
- read AV target 0x9;
- exact BPE worker name;
- last import tcVi5SivF7Q;
- exact linked-list instruction signature;
- head=1 / adjacent=0;
- canonical payload pointer.

DLSS
====
This package is cumulative with V74.0.67.2.10.2:
- preserves V74.0.67.1 provider loader;
- lazy sharpemu_vk_upscaler_get_last_error;
- native initialize result telemetry;
- failed-output-size retry;
- V2.9 source identity;
- V2.5 depth;
- V2.6 motion;
- V2.8 strict Vulkan/NGX negotiation.

DLSS success still requires:
  selected=dlss
  state=active
  dlss_dispatches>0
