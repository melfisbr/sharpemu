SharpEmu V74.0.22 SAFE — Demon's Souls guest-owned boot / no-auto-kill repair

WHY V74.0.21 CLOSED
V74.0.21 did not crash. Its diagnostic runner deliberately stopped the process 20 seconds after the ABI proof. The uploaded result reported STOP_REASON=abi-proof-plus-observation, CLASSIFICATION=entry-abi-proof-captured, UNHANDLED_EXCEPTIONS=0, and wall time 26.88 s.

WHAT V74.0.21 PROVED
- EBOOT entry 0x0000000800000070 reached the guest.
- EntryParams 0x118 / argv[33] / entry address marker was observed.
- sceKernelGetProcParam returned 0x00000008027A7E80 repeatedly.
- _init_env was routed through the real LLE libc implementation.
- The game reached Finished Initialization around 8.07 s, main loop around 17.66 s, and Vulkan produced a first 3840x2160 frame.
- No unhandled/fatal guest exception was captured before the runner terminated it.

WHY HOST AUTO BOOT STAYS OFF
A prior guest-media run showed the host canonical direct boot completing ps_studios_logo -> logo_intro -> logo_intro_loop, then the guest naturally requested ps_studios_logo again after handoff. That proves host-forcing the intro chain can duplicate the guest's own boot state. V74.0.22 therefore leaves SHARPEMU_BINK_AUTO_BOOT=0 and observes the natural guest sequence instead.

WHAT V74.0.22 CHANGES
- No source file is modified. RUN_3 is build verification only.
- Preserves V74.0.21 EntryParams + LLE _init_env corrections.
- Host auto/direct boot OFF.
- Natural startup completion shim ON, so a natural guest Bink request can complete back into guest state.
- RUN_4 has no deadline and no Stop-Process call. It remains active until you close SharpEmu or the runtime exits naturally.
- Result ZIP is generated after the process has ended.
- Stable runtime profile retained: native memcpy, TBB=2, resource lane=8, render scale 1.0, standalone texture cache 768 MB, DCC history off.

RUN ORDER
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_DEMONS_GUEST_OWNED_BOOT.cmd

IMPORTANT
Do not apply V74.0.20 before this test. V74.0.22 is intentionally measuring the guest-owned sequence after the corrected EBOOT entry ABI. Leave the emulator open. If it remains black for several minutes, close the SharpEmu window yourself; RUN_4 will then package the complete evidence.
