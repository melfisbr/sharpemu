SharpEmu Demon's Souls Gen5 Import Metadata V73.1.1 SAFE

CORRECTION OVER V73.1
V73.1 failed before applying the SelfLoader integration because its line regex
did not account for the carriage-return byte in Windows CRLF source lines.
Rollback restored both SelfLoader.cs and Ps5SceDynamicImportMetadata.cs.

Confirmed restored SelfLoader SHA-256:
AAF46BE2F59940DB7CF806F437D503E03E08B018F6D0F2D2A52F34310E53684D

V73.1.1 changes only the patching mechanism:
- CRLF-safe case-label anchors ending in \r?$
- insertion helper removes any consumed CR before restoring the original newline
- exact baseline SHA-256 guard before source mutation
- same Gen5 metadata semantics and same fail-closed behavior as V73.1


INPUT RESULT
SharpEmu_V73_0_1_EBOOT_ABI_AUDIT_20260813_212837.zip

V73.0.1 result:
version=V73.0.1
powershell51_generic_list_fix=True
current_hle_exports=
29799
eboot_import_symbols=
1174
implemented_hle=
691
no_hle_export=
483
duplicate_hle_nids=
0
selfloader_sha256=
AAF46BE2F59940DB7CF806F437D503E03E08B018F6D0F2D2A52F34310E53684D

Additional name correlation:
- NO_HLE_EXPORT total: 483
- names resolved from the PS5 name catalog: 478
- unmapped names: 5
- No blind HLE stubs are generated.

PROVEN STRUCTURAL GAP
The current SelfLoader source snapshot recognizes legacy SCE import identity tags:
  DtSceNeededModule = 0x6100000F
  DtSceImportLib    = 0x61000015

The audited Demon's Souls Gen5 PT_DYNAMIC also contains:
  0x61000045 = Gen5 module identity
  0x61000049 = Gen5 import-library identity

The existing TryDecodeSceMetadataName path already understands the value layout
(high 16-bit ID, metadata/version field, low 32-bit string-table offset). V73.1.1
therefore extends the existing parser with the two observed Gen5 tag IDs rather
than replacing NID resolution or relocation semantics.

SOURCE CHANGES
1. SelfLoader.cs:
   - adds DtSceNeededModuleGen5 = 0x61000045
   - adds DtSceImportLibGen5 = 0x61000049
   - CollectNeededModuleNames accepts both legacy and Gen5 module tags
   - ParseSceImportMetadata accepts both legacy and Gen5 module/library tags

2. Ps5SceDynamicImportMetadata.cs:
   - preserves/installs the V73 decoder helper for Gen5 tag and symbol-token
     decoding; no title-specific NIDs are hard-coded.

NOT CHANGED
- relocation algorithms
- import-stub fallback
- native PRX resolution
- imported-data rebinding
- TLS semantics
- AGC command semantics
- GPU waits/producers
- Bink/audio paths

WHY 483 NO_HLE_EXPORT ITEMS ARE NOT AUTOMATICALLY IMPLEMENTED
The static list includes native PRX symbols and native data/RTTI objects. For
example, libc entries can be satisfied by the loaded libc.prx rather than a C#
SysAbiExport. The post-build diagnostic therefore records only imports that are
actually executed and reported unresolved at runtime.

EXPECTED VALIDATION
On Demon's Souls main EBOOT, the first:
  [LOADER] SCE import metadata:
line should become:
  libraries=53 modules=49

If the runtime reports different values, the diagnostic records the real values
and does not fake success.

DIAGNOSTIC OUTPUT
SharpEmu_V73_1_1_METADATA_IMPORT_TRACE_<timestamp>.zip
contains:
- stdout/stderr
- actual metadata counts
- runtime unresolved import counts
- static EBOOT/HLE/name correlation
- exact V73.1.1 SelfLoader source windows

Close the emulator after reaching the normal post-video transition/stall so the
diagnostic script can finish and create the result ZIP.
