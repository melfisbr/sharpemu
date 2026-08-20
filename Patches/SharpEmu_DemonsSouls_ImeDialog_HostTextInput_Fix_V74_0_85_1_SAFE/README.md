# SharpEmu Demon's Souls IME Dialog Host Text Input Fix V74.0.85.1 SAFE

This is the corrected package for the V74.0.85 PRECHECK regression.

V74.0.85 incorrectly required the raw identifiers `ParamMaxTextLengthOffset` and
`ParamInputTextBufferOffset` to occur exactly once. The current known-good baseline contains
each identifier twice: once in its constant declaration and once where it is used. Therefore
the old package stopped before APPLY even though the source was exactly the expected one.

V74.0.85.1 validates the exact declarations and pins the observed baseline SHA-256 before
installing the IME host text-entry implementation.

The runtime behavior remains:

`sceImeDialogInit -> RUNNING -> host text entry -> guest UTF-16 buffer commit -> FINISHED -> result -> term`

Run from `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` in order: validate, precheck,
apply/build, diagnostic, test.
