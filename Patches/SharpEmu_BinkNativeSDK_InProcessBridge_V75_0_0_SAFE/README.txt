SharpEmu Bink Native SDK In-Process Bridge V75.0.0 SAFE

WHAT THIS PACKAGE IMPLEMENTS
============================
This is the first complete SharpEmu-side implementation of a native/in-process
Bink backend.

It removes radvideo64.exe from the playback path WHEN a licensed Bink SDK is
available and SharpEmu.BinkNative.dll has been built.

Architecture:

  HostMovieBridge
      |
      +-- MovieMode.NativeRad
      |
      +-- RadBinkNativeSdkDecoderV7500
              |
              +-- SharpEmu-owned stable ABI
              |
              +-- SharpEmu.BinkNative.dll
                      |
                      +-- licensed bink.h + matching Windows x64 Bink library

The package contains no proprietary RAD/Bink binaries, headers, libraries, or
SDK content.

WHY A STABLE SHARPEMU ABI
=========================
SharpEmu does not marshal the version-sensitive HBINK structure.

The native shim is compiled against the exact bink.h supplied with the licensed
SDK. The managed emulator sees only SharpEmu's own small ABI:

  se_bink_abi_version
  se_bink_build_capabilities
  se_bink_open_utf8
  se_bink_decode_bgra
  se_bink_get_clock_us
  se_bink_request_skip
  se_bink_close
  se_bink_last_error_utf8

NATIVE PLAYBACK MODE
====================
Explicit:
  SHARPEMU_BINK_MODE=native-rad

Force old external player:
  SHARPEMU_BINK_MODE=external-rad

Current SharpEmu default "rad":
- if SharpEmu.BinkNative.dll is present and ABI-valid, ResolveMode automatically
  chooses native-rad;
- otherwise existing external RAD playback remains unchanged.

Disable automatic native preference:
  SHARPEMU_BINK_NATIVE_PREFER=0

Disable external fallback:
  SHARPEMU_BINK_NATIVE_FALLBACK=0

AUDIO OWNERSHIP
===============
Movies with embedded Bink audio:
- native mode is accepted only when the adapter reports that the SDK audio
  provider is active;
- otherwise native open is rejected and external RAD fallback is used;
- this prevents silent PS Studios playback.

Demon's Souls attract_movie:
- observed Bink header has no embedded audio track;
- existing AT9 deterministic sidecar remains SharpEmu-owned;
- MediaFramePlayback uses the WaveOut cursor as the presentation clock when it
  is available.

PERFORMANCE POLICY
==================
V75.0.0 is correctness-first:
- dedicated decoder thread;
- three BGRA buffers (rather than global five);
- no radvideo64.exe process;
- no child HWND / SetParent / ShowWindow lifecycle in native mode;
- no cross-process playback polling;
- native BinkWait performs pacing on the decoder thread.

This initial adapter still uses BinkCopyToBuffer into BGRA. It is NOT yet the
future zero-copy BinkTextures/GPU path. The stable ABI is deliberately designed
so that a later GPU texture provider can be added without changing
HostMovieBridge again.

LICENSED SDK BUILD
==================
The managed integration builds without the Bink SDK.

To produce the operational native DLL, provide a licensed Windows x64 Bink SDK:

  set SHARPEMU_BINK_SDK_ROOT=C:\path\to\BinkSDK

Then execute:
  RUN_5_BUILD_NATIVE_ADAPTER.cmd

The build script searches recursively for:
- bink.h
- an x64 Bink .lib
- Visual Studio x64 C++ Build Tools

and deploys SharpEmu.BinkNative.dll under the SharpEmu output plugins\bink2
directory.

If the SDK is not present, RUN_3 does NOT break the emulator. It installs the
managed native backend and preserves external RAD as the operational fallback.

EXPECTED RUNTIME
================
When native DLL is built and available:

  [BINK-NATIVE][V75.0.0] adapter_loaded ...
  [BINK-NATIVE][V75.0.0] auto_selected requested=rad resolved=native-rad ...
  [BINK-NATIVE][V75.0.0] open_ok ...
  [BINK-NATIVE][V75.0.0] playback_buffers ... count=3
  [BINK-NATIVE][V75.0.0] bridge_attached ... decoder=in-process-sdk
  [BINK-NATIVE][PERF][V75.0.0] ...

There should be NO radvideo64.exe process for a movie successfully attached by
native-rad.

FILES MODIFIED IN REPOSITORY
============================
src\SharpEmu.Libs\Media\HostMovieBridge.cs
src\SharpEmu.Libs\Media\MediaFramePlayback.cs

FILES ADDED
===========
src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs
src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs

The native adapter source remains inside the patch package and is compiled only
against a user-provided licensed SDK.
