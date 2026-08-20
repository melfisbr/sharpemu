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


V75.0.0.1 PACKAGE REPAIR — PowerShell 5.1 PRECHECK
==================================================
V75.0.0 RUN_1 correctly detected a parser failure before repository mutation.

Malformed V75.0.0 expression:

  if (Test-Path ... -or
      Test-Path ...) {

PowerShell 5.1 parses the first Test-Path as a command invocation and does not
accept -or there as a boolean operator.

V75.0.0.1 uses:

  if ((Test-Path ...) -or
      (Test-Path ...)) {

The validator now also rejects the original unparenthesized Test-Path/-or/
Test-Path pattern before any PRECHECK/APPLY work.

Functional implementation is unchanged:
- BinkNativeSdkAbiV7500.cs
- RadBinkNativeSdkDecoderV7500.cs
- SharpEmu.BinkNative.cpp
- native-rad HostMovieBridge mode
- MediaFramePlayback native clock/buffer policy
- external RAD fallback

Runtime/source markers intentionally remain V75.0.0.

Repository state after failed V75.0.0:
RUN_1 failed while parsing package scripts. RUN_2 and RUN_3 could not execute
precheck.ps1, so no SharpEmu source file was modified. No rollback is needed.


V75.0.0.2 PACKAGE REPAIR — MediaFramePlayback structural locators
=================================================================
V75.0.0.1 fixed the PowerShell parser and RUN_1 then reached the real
full-source transform regression.

The fixture/current source declares:

  internal interface IMediaFrameDecoder : IDisposable
  {

but the V75.0.0.1 locator required:

  internal interface IMediaFrameDecoder : IDisposable {

on one physical line.

V75.0.0.2 uses a multiline structural locator and accepts either form.

The same package contained the same latent issue for:

  private double CurrentPlaybackSecondsLocked()
  {

That locator has been fixed proactively in V75.0.0.2 as well, so validation
does not simply advance to the next brace-format false negative.

The full archived MediaFramePlayback fixture already uses both multiline
forms, therefore RUN_1 now regression-tests the exact formatting that failed.

No functional C# or C++ native-Bink design changed:
- stable SharpEmu native ABI remains V75.0.0;
- MovieMode.NativeRad remains unchanged;
- 3-buffer playback policy remains unchanged;
- native playback clock remains unchanged;
- external RAD fallback remains unchanged;
- SharpEmu.BinkNative.cpp remains unchanged.

The failed V75.0.0.1 runs stopped inside RUN_1 package regression, so no
repository rollback is required.


V75.0.0.3 PACKAGE REPAIR — Structural MediaFramePlayback body
=============================================================
V75.0.0.2 reached the full-source regression and successfully patched
HostMovieBridge, then failed while locating the existing
_followGuestAudioClock assignment.

The assignment exists. The false negative came from comparing the complete
multiline C# block as an ordinal here-string, making CRLF/LF representation a
part of the patch contract.

V75.0.0.3 removes this class of failure from the remaining MediaFramePlayback
transforms.

Now structurally located:
- _followGuestAudioClock assignment;
- BufferCount allocation for-loop;
- Nihav first-frame prime condition;
- PlaybackProgress elapsed-clock ternary;
- CurrentPlaybackSecondsLocked startup guard.

The V75.0.0.2 multiline declaration locators remain in place for:
- IMediaFrameDecoder;
- CurrentPlaybackSecondsLocked() declaration.

No functional native-Bink behavior changed. Runtime markers remain V75.0.0.
The previous failed runs remained inside RUN_1 package regression and did not
modify the repository, so no rollback is required.


V75.0.0.4 PACKAGE REPAIR — PowerShell reserved $Host collision
==============================================================
V75.0.0.3 RUN_1 passed the complete package validation and full-source
transform regression.

RUN_2 then failed before PRECHECK could evaluate repository state:

  Cannot overwrite variable Host because it is read-only or constant.

PowerShell variable names are case-insensitive, so:

  $host

is the same variable as the automatic read-only:

  $Host

V75.0.0.4 renames that local path variable to:

  $hostMovieSourcePath

in:
- precheck.ps1
- apply_build.ps1
- diagnostic.ps1
- rollback.ps1

The validator now also rejects assignments to common automatic/read-only
PowerShell variables before any repository operation.

No functional backend source changed:
- HostMovieBridge patch is unchanged;
- MediaFramePlayback patch is unchanged;
- BinkNativeSdkAbiV7500.cs is unchanged;
- RadBinkNativeSdkDecoderV7500.cs is unchanged;
- SharpEmu.BinkNative.cpp is unchanged.

Recovery state:
- RUN_1 only patched temporary fixtures;
- RUN_2 failed before applying source changes;
- RUN_3 invoked the same PRECHECK and stopped at the same point;
- no V75.0.0.x repository rollback is required.


V75.0.0.5 PACKAGE REPAIR — PowerShell static .NET invocation
=============================================================
V75.0.0.4 passed RUN_1 completely and RUN_2 verified the repository/source
targets before failing at:

  Environment.GetEnvironmentVariable('SHARPEMU_BINK_SDK_ROOT')

That is valid C# syntax but invalid executable PowerShell syntax.

Correct PowerShell syntax:

  [Environment]::GetEnvironmentVariable('SHARPEMU_BINK_SDK_ROOT')

V75.0.0.5 fixes the executable call in:
- precheck.ps1
- build_native_adapter.ps1

Important: patch_host_movie_bridge_v7500.ps1 also contains the text
Environment.GetEnvironmentVariable(...), but there it is C# source being
inserted into HostMovieBridge.cs. That text is intentionally NOT changed.

To distinguish those cases safely, RUN_1 now examines the PowerShell AST and
rejects only executable CommandAst nodes named:

  Environment.GetEnvironmentVariable

It does not raw-search here-string contents.

No functional native backend code changed. RUN_3 previously stopped inside
PRECHECK, before backup/apply, so no rollback is required.


V75.0.0.6 PACKAGE REPAIR — accumulated HostMovieBridge
======================================================
V75.0.0.5 passed RUN_1 and RUN_2. RUN_3 reached the real SharpEmu checkout,
installed the managed native-Bink sources, patched MediaFramePlayback, and
then failed with:

  Host audio mode gate not found.

The SAFE catch restored the V75 targets and rebuilt the restored GUI
successfully. No manual rollback is required.

Root cause:
the old patcher expected the entire block:

  if (mode != MovieMode.Rad)
  {
      BinkHostAudioBridgeV7241.TryStart(hostPath);
  }

The accumulated HostMovieBridge has additional lifecycle/audio ownership
policy, so that full block is no longer a stable contract.

V75.0.0.6 does NOT rewrite the accumulated outer audio condition.

It structurally finds AttachMovieLocked, then finds exactly one generic:

  BinkHostAudioBridgeV7241.TryStart(hostPath);

inside that method and changes only that statement to:

  if (mode != MovieMode.NativeRad)
  {
      BinkHostAudioBridgeV7241.TryStart(hostPath);
  }

Therefore every existing outer condition remains intact. NativeRad alone is
excluded because embedded Bink audio is owned by SharpEmu.BinkNative.dll.
The Demon's Souls attract AT9 sidecar is still explicitly started inside
AttachRadNativeMovieLocked after native movie open.

V75.0.0.6 also proactively removes three other accumulated-source hazards:
- MovieMode.Rad switch case is located only inside AttachMovieLocked;
- AttachRadMovieLocked uses a multiline structural method locator;
- ResolveMode is no longer replaced as a full accumulated branch. V75 policy
  is prepended to ResolveMode and all existing logic is left untouched;
- MovieMode.NativeRad is inserted within the structurally located enum body.

RUN_1 tests both:
- the archived HostMovieBridge fixture;
- an accumulated fixture whose audio gate has an extra title condition and
  intentionally cannot match the old V75.0.0.5 regex.

The managed ABI, decoder, native C++ adapter, MediaFramePlayback functional
policy and external RAD fallback remain unchanged.
