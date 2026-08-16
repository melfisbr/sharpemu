# Demon’s Souls / SharpEmu — Full eboot + src audit V74.0.1

## Scope

Audited the full available `src` snapshot (500 C# files), overlaid with the
latest cumulative V73.20.4.1 sources, plus the real Demon’s Souls eboot
SHA-256 `22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E`.

## Eboot loader facts

- SELF segments: 12
- embedded ELF offset: `0x1A0`
- ELF type: `0xFE10` (SCE DynExec), x86-64
- entry: `0x70`
- SCE libraries: 53/53, rejected 0
- SCE modules: 49/49, rejected 0
- dynamic symbols: 1175
- relocations: 173,377
- relocation-referenced unique NIDs: 1173

The V73.20.4.1 runtime independently confirms the same 1173 NIDs / 173377
descriptors and successfully builds all 1385/1385 runtime import stubs.

## Import/API conclusion

A static direct `[SysAbiExport]` scan finds 691/1173 eboot NIDs.
The other 482 are **not proven unresolved functions**:
runtime reports imported-data `unresolved=0`, 1385/1385 import stubs and 176 LLE
redirects. V74.0.1 therefore does not manufacture placeholder API exports.

The eboot NID `14bOACANTBo` is `scePthreadOnce`; it has a real implementation in
`KernelPthreadCompatExports.cs`. Its V73.20.4.1 failure is execution-side:
the callback reaches `RunGuestEntryStubDedicated` without a scheduled guest handle,
is rejected, and `scePthreadOnce` correctly returns TRY_AGAIN.

## P0 execution findings and V74.0.1 corrections

1. **Top-level guest entry still uses the last normal `CallNativeEntry(ptr)`** from a
   CLR-created thread. All pthread guest paths had already been moved off that
   topology, yet the CLR still FailFasts at the first compute event. V74.0.1 adds
   `RunTopLevelGuestEntryStub()` using a raw `NativeGuestExecutor`.

2. **Handle-less HLE callbacks have no native lane.** V74.0.1 adds
   `RunTransientGuestEntryStub()` and routes the missing-handle callback case through
   it. This directly targets the observed `scePthreadOnce -> TRY_AGAIN` failure.

3. **The 4K DCC UI/movie source has no proven producer identity.** V74.0.1 adds a
   semantics-neutral `TraceDemonTextureProducerContract()` for 3840x2160 metadata
   descriptors. It reports exact-known/writer/residency and metadata/shape candidates.
   It never invents a DCC alias or writer.

## Texture/render contract verified in the eboot

The eboot contains:
- `UIBehaviorBinkMovieTextureDataSource`
- `CCPLdrUIBehaviorBinkMovieTextureDataSource::ApplyProperties`
- `kRTT_UI_Offscreen_0`, `_1`, `_Fonts`
- `DisplayBuffer`
- `UIManager::ShowHUDSceneImpl`, `IsSceneFullyLoaded`,
  `AdvanceMenuStackSceneTransitions`
- `Agc::Toolkit::cs_dcc_retile_32bpp_c`, `cs_dcc_retile_64bpp_c`,
  `cs_dcc_cleartopixel_c`
- `GetDccCompressionCompatibilityBits`
- VideoOut open/register/submit/wait/unregister/close functions.

The source already has AGC render-target provenance, compute writers, DCC alias
resolution, zero-DCC copy suppression, VideoOut presentation, graphics Bink Y/UV
substitution and V73.20 compute Bink Y/UV substitution.

## P1 issues retained for evidence, not guessed fixes

- The presenter texture cache is count-limited (2048 entries), not globally byte
  budgeted. This can matter for the earlier multi-GB RAM pressure, but V74.0.1 does
  not change eviction semantics before the P0 FailFast is removed.
- Shader compiler contains explicit unsupported opcode/format branches. The latest
  run did not reach an actual unsupported-shader error before the CLR abort, so
  V74.0.1 does not invent RDNA2 opcode semantics without a runtime hit.
- The historical critical sampled texture `0x45D550000` (3840x2160,
  metadata `0x486AF8000`) still has no proven address-to-Bink/UI-name identity.
  The new contract trace is designed to resolve that after execution survives.

## Expected next proof

V74.0.1 should first eliminate:
- `missing_guest_thread_handle` for `scePthreadOnce`;
- `0x80131506` at the first GPU event.

Then the same diagnostic continues into natural Bink/UI and 4K texture producer
evidence. That determines whether the next remaining P0 is Y/UV binding, a DCC
producer mapping, or a concrete shader opcode.
