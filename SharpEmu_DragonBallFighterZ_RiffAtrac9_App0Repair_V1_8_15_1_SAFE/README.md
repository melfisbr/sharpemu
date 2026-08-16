# DBFZ RIFF/ATRAC9 + App0 Repair V1.8.15.1 SAFE

Evidence from V1.8.14.2.1:
- process survived 360 seconds, no fatal/device lost;
- 16 NGS2 parse calls succeeded;
- input is RIFF/WAVE_FORMAT_EXTENSIBLE, not VAG/PCM;
- observed SubFormat GUID bytes are D242E147BA368D4D88FC61654F8C836C
  (GUID 47E142D2-36BA-4D8D-88FC-61654F8C836C), identifying ATRAC9;
- the caller's 0x240 output record already contained nonzero state/pointers;
- the old compatibility cleared that entire record;
- 44 mkdir permission denials remained;
- previous writable-app0 A/B eliminated those denials.

Repairs:
1. Remove the destructive 0x240 zero-fill.
2. Validate RIFF/WAVE_EXTENSIBLE ATRAC9 and preserve the caller descriptor.
3. Make app0 writable only for PPSA09790; other titles retain retail policy.

This package intentionally does not invent an ATRAC9 decode API call. The checkout
already builds SharpEmu.LibAtrac9; the next integration step will use its exact
current API after this non-destructive ABI correction is validated.

## V1.8.15.1 structural patcher correction

V1.8.15 still tried to locate the next fallback `SetReturn` after the marked
compatibility block. That assumption is invalid on the accumulated checkout.

V1.8.15.1 finds the marked `if` block itself and removes only that balanced C#
brace range. Strings, chars and comments are ignored by the scanner. All code
before and after the old block is preserved byte-for-byte by the patcher.
