# V76.0.18.4 Presenter Scope BuildFix

- Functional V76.0.18 hard guest-only Bink2 routing is unchanged.
- Functional V76.0.18 eboot close handoff is unchanged.
- Fixes the Debug build failure CS0103 in `VulkanVideoPresenter.BinkGuestHandoffV7618.cs`.
- The failed helper was declared on the static `VulkanVideoPresenter` facade but attempted to clear seven fields that belong to the nested `Presenter` instance.
- Those seven accesses are removed. In hard guest-only mode `.bk2` host attach/pump is blocked before those per-instance host frame fields can own the movie, so clearing them from the guest close handoff is neither valid nor required.
- `RUN_1` now rejects those Presenter-instance member names if they reappear in the static V7618 helper.
- Keeps V76.0.18.3 fix that prohibits assigning to PowerShell automatic `$Host` through case-insensitive `$host`.
- Debug and Release builds remain mandatory; rollback remains automatic on failure.
