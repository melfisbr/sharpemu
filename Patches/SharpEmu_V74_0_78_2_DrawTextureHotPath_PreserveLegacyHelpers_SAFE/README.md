# SharpEmu V74.0.78.2 — Draw Texture Hot Path / Preserve Legacy Helpers SAFE

This revision fixes the V74.0.78.1 build failure while retaining the performance target.

## Why V74.0.78.1 failed
V74.0.78.1 bounded `IsTextureContentCached` using the next `MarkTextureContentCached` signature and replaced that whole region. In the accumulated checkout, helper methods used by earlier sampler-alias work lived inside that region. The replacement therefore deleted `NormalizeSamplerIdentityV74075` and `IsTextureContentCachedIgnoringSamplerV74074` while leaving their call sites intact.

## V74.0.78.2 correction
- Never replaces the region between cache lifecycle methods.
- Renames only the existing `IsTextureContentCached` signature to `IsTextureContentCachedBaselineV740782`.
- Inserts a new O(1), sampler-neutral wrapper in front of it.
- The accumulated baseline method remains authoritative for sparse guest-content probing and stale invalidation.
- Existing V74.0.75 / V74.0.74 helper definitions and call sites are counted before/after patching and must remain unchanged.
- Adds an O(1) content-only index synchronized by `MarkTextureContentCached`, `UnmarkTextureContentCached`, and `ClearCachedTextureIdentities`.
- Replaces physical texture buffers that are immediately overwritten by guest reads with `GC.AllocateUninitializedArray<byte>`.
- Producer wake/drain is appended to the existing signal method only when equivalent accumulated logic is not already present; the method is not replaced.
- No rigid SHA gate. Backup + automatic rollback on build failure.

Expected runtime marker:
`[V74.0.78.2][PRE_SNAPSHOT_SAMPLER_ALIAS] ... source_copy=skipped`

Run in order:
1. `RUN_1_VALIDATE_PACKAGE.cmd`
2. `RUN_2_PRECHECK.cmd`
3. `RUN_3_APPLY_BUILD.cmd`
4. `RUN_4_TEST_DIAGNOSTIC.cmd`
