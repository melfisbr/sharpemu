# SharpEmu Demon's Souls — V74.0.56.36.2 SAFE

Corrected/adaptive version of V56.36.

Fixes two package problems reported on the current checkout:

- `validate_package.ps1` itself failed to parse under Windows PowerShell 5.1.
- the exact `VulkanVideoPresenter.cs` `alias_guard` anchor had diverged.

The AGC G-buffer recovery is unchanged because V56.36 PRECHECK proved both AGC
anchors are present (`State=Ready Ready=2`).

Presenter handling is now structural:
- finds `Consider(GuestImageResource candidate, bool isActive)`;
- accepts an already-installed equivalent guard;
- otherwise inserts the DCC initialized-image guard after the method opening
  brace without depending on the old surrounding text.

The test still preserves V56.35 DCC fast-clear materialization and disables
V71/V72 waiter-drain experiments.

## V56.36.2 packaging repair

This revision fixes the PowerShell 5.1 parse error reported in V56.36.1.
The nested multi-line `Join-Path (Split-Path ...)` expression was replaced by
two explicit variables and named `-Path` / `-ChildPath` arguments.

`RUN_2`, `RUN_3` and `RUN_4` also execute package validation first, so a future
package parse failure cannot continue into misleading precheck/build output.
