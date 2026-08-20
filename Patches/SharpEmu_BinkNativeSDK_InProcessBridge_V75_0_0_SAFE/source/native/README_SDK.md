SharpEmu.BinkNative.dll — SDK adapter source

This folder contains SharpEmu's own ABI shim. It does NOT contain or redistribute
RAD/Bink proprietary code, headers, import libraries, or DLLs.

Required to build the operational adapter:
- a legitimately licensed Windows x64 Bink SDK
- bink.h
- the matching x64 Bink import/static library
- Visual Studio C++ Build Tools

Supported SharpEmu ABI exports:
  se_bink_abi_version
  se_bink_build_capabilities
  se_bink_open_utf8
  se_bink_decode_bgra
  se_bink_get_clock_us
  se_bink_request_skip
  se_bink_close
  se_bink_last_error_utf8

The source deliberately uses bink.h at compile time. This lets the compiler
validate the exact Bink SDK function prototypes/constants rather than SharpEmu
hard-coding a version-specific Bink structure layout.

Audio:
- if bink.h exposes BinkSoundUseXAudio2, the build script defines
  SHARPEMU_BINK_HAVE_XAUDIO2 and the adapter asks Bink to own embedded Bink audio;
- if the SDK does not expose that provider, movies with embedded Bink tracks are
  rejected by the managed native backend and safely fall back to external RAD;
- attract_movie.bk2 has no embedded Bink audio in the observed Demon's Souls
  files, so SharpEmu keeps its deterministic AT9 sidecar for that movie.

Performance:
- decoder runs on MediaFramePlayback's dedicated host decoder thread;
- native mode uses three BGRA buffers rather than five;
- no radvideo64.exe process/window/SetParent/ShowWindow lifecycle is involved;
- V75.0.0 is a correctness-first software-copy backend. It intentionally leaves
  a future BinkTextures/GPU zero-copy path behind the same stable ABI.

Build:
  set SHARPEMU_BINK_SDK_ROOT=C:\path\to\licensed\BinkSDK
  RUN_5_BUILD_NATIVE_ADAPTER.cmd

The build script searches the SDK recursively for bink.h and a likely x64
Bink .lib, invokes the installed Visual Studio x64 toolchain, and deploys:
  artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll
