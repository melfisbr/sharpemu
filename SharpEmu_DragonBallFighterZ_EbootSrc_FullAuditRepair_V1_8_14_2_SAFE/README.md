# Dragon Ball FighterZ — EBOOT/SRC Full Audit + Repair V1.8.14.2 SAFE

Target:
- Title: DRAGON BALL FighterZ
- Title ID: PPSA09790
- EBOOT SHA256: 106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018
- EBOOT unique imported NIDs: 2,766
- Relocation references: 14,652

## What RUN_2 audits
It verifies the exact EBOOT hash, reads the retained 2,766-row EBOOT inventory,
parses every current `src/**/*.cs` `[SysAbiExport] Nid = "..."`, and writes a
fresh current-checkout comparison CSV. It does not assume the old src(10)
snapshot is still the checkout.

## Repairs applied
1. DBFZ-only Unreal Saved-tree compatibility:
   `/app0/red/saved` becomes writable only when the current title is PPSA09790.
   Other app0 paths and other titles stay read-only.

2. DBFZ-only `sceNgs2ParseWaveformData` compatibility:
   the V1.8.13 probe showed consecutive output pointers with a 0x240-byte stride.
   For PPSA09790 only, the 0x240-byte output record is initialized and success is
   returned. Other titles preserve INVALID_ARGUMENT until their ABI is proven.

## Deliberately not fabricated
- `n3kSX62fgNo` (Pad): one observed call, exact identity/ABI not proven.
- `FzQS6DREDfk` (SharePlay): one observed call, exact identity/ABI not proven.
- APR (`gEpBkcwxUjw`) is preserved. Historical semantic tracing demonstrates a
  real successful implementation that writes IDs/sizes; nine current misses do
  not justify replacing the function.

All changed files are backed up under `.sharpemu-hotfix-backup`. A patch or build
failure restores both source files automatically.

## V1.8.14.2 cumulative-source correction

V1.8.14 assumed one exact textual spelling of the final V1.8.13 NGS2 error
return. Cumulative checkouts can legitimately differ there. V1.8.14.2 instead
anchors on `Ngs2ParseWaveformDataV1813`, selects the method's last `SetReturn`
fallback structurally, inserts the PPSA09790-only compatibility immediately
before it, and preserves the pre-existing fallback verbatim.
