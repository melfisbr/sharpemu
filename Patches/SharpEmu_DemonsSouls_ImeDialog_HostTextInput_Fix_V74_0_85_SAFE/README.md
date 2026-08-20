# SharpEmu Demon's Souls IME Dialog Host Text Input Fix V74.0.85 SAFE

This package adds an interactive host text-entry panel to the existing `libSceImeDialog` HLE path.

The old implementation immediately autofilled `Sharp` and marked the dialog finished. V74.0.85 preserves the existing ABI offsets, but implements the expected RUNNING -> user input -> FINISHED lifecycle.

The Windows panel is started asynchronously and does not block the guest HLE call. Text is committed to guest memory only from a later guest poll (`sceImeDialogGetStatus` / `sceImeDialogGetResult`).

Run from `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` in order: validate, precheck, apply/build, diagnostic, test.
