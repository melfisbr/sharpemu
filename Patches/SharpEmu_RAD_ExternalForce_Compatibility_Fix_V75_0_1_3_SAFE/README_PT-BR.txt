SharpEmu V75.0.1.3 SAFE
RAD EXTERNAL FORCE + COMPATIBILITY PRESERVE

Problem fixed
=============
V75.0.1.2 restored complete pre-V75 HostMovieBridge.cs and
MediaFramePlayback.cs. That was too broad.

The restored old MediaFramePlayback no longer defined:
- MediaFramePixelLayout
- IMediaFramePixelLayoutSource

but the current NihavBink2Decoder and VulkanVideoPresenter already require
those accumulated V74 contracts. The build therefore failed with CS0246.

V75.0.1.3 strategy
==================
DO NOT restore old MediaFramePlayback.
DO NOT delete BinkNativeSdkAbiV7500.cs.
DO NOT delete RadBinkNativeSdkDecoderV7500.cs.

Instead:
1. Patch only HostMovieBridge ResolveMode / NativeRad case.
2. Every RAD spelling resolves to MovieMode.Rad (official external RAD).
3. Even a direct MovieMode.NativeRad is externalized defensively.
4. SHARPEMU_BINK_NATIVE_PREFER can no longer auto-select native RAD.
5. Remove deployed SharpEmu.BinkNative.dll from Debug/Release.
6. Preserve current MediaFramePlayback byte-for-byte.
7. Preserve current ABI/decoder sources as compile-only dead support.
8. Full Release win-x64 build validates the resulting tree.
9. Automatic rollback restores HostMovieBridge and adapter DLLs if build fails.

Expected current baseline
=========================
HostMovieBridge.cs:
D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B

MediaFramePlayback.cs:
C1403289699A4F51E83BC7F0CCF09ABF563A46C356D282AB1CFDF8432088CB37

BinkNativeSdkAbiV7500.cs:
CF93BEF4C1DAED11500A28A83F25C1A72407A84ED9371EF31C5E72399A8D9494

RadBinkNativeSdkDecoderV7500.cs:
E65A0D5896832F3955561983933E4E1C7558501DE143EFE11D3E647731A452C6

Expected runtime
================
Present:
[LOADER][INFO] Bink RAD bridge attached:

Absent:
[BINK-NATIVE][V75.0.0] adapter_loaded
[BINK-NATIVE][V75.0.0] auto_selected
[BINK-NATIVE][V75.0.0] bridge_attached
[BINK-NATIVE][V75.0.0] open_failed
[BINK-NATIVE][V75.0.0] attach_failed

This package does not attempt to solve the main-menu UI composition itself.
It first restores a stable, build-compatible official RAD ownership route,
which is the required baseline for the next RAD/UI integration correction.
