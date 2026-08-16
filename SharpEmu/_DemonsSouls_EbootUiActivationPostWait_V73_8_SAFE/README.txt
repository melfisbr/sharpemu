SharpEmu Demon's Souls EBOOT UI Activation / Post-Wait V73.8 SAFE

V73.7.1 RESULT
version=73.7.1
exit_code=
classification=resource-io-clean-ui-render-path-reached
eboot_sha256=22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E
ampr_all_reads=9815
ampr_ui_reads=966
ampr_failures=0
kernel_script_io=3698
kernel_script_failures=0
read_disposed_or_io_errors=0
resource_milestones=5
ui_runtime_markers=5
runtime_unresolved=0
device_lost=0

The UI resource path is no longer speculative:
- uistartmenu.cgpr read successfully;
- uihud.cgpr read successfully;
- subscreen_overlay_backing.ctxr read successfully;
- 966 UI-related AMPR reads;
- zero AMPR failures;
- zero kernel script IO failures;
- zero disposed/io_error reads;
- resource dependency recording, cp11main, main loop and resource gathering all completed.

EBOOT NATIVE UI SURFACE
The audited main EBOOT contains:
- UIManager::HasOpenMenus
- UIManager::PrintSceneState
- uiShowHudScene
- UITransition_ShowHUDScene
- TransitionShowHUDScene::Transition_Validate
- CComponentUIBehaviorStartMenuInputHandler::Think
- CComponentUIBehaviorStartMenuInputHandler::HandleInputFocus
- ShowLegacyMenu
- Start Menu Closed

Therefore V73.8 stops changing filesystem/APR/AMPR.

WHAT V73.8 PROVES
1. It injects real guest-pad Options sample edges at:
   90,105,120,135,150 seconds.
   The existing PadExports logs press/release only when that sample path is
   actually executed, so this distinguishes host/movie Tab handling from
   scePad input delivered to the guest.

2. It enables only the bounded V73.4 label provenance channel plus scanout
   lineage. Full AGC/Vulkan/draw/resource IO traces remain disabled.

3. It correlates the new post-UI WAIT_REG_MEM generations with:
   PM4 producer ranges, WRITE_DATA application, real wait resumes,
   V73.0.14 producer-priority selection, guest frames and scanout.

No source is modified.

BASELINE V73.7.1 RUNTIME
- guest frame lines: 1
- WAIT_REG_MEM registrations: 11
- ordered fence max counter: 1024
- unresolved imports: 0
- device lost: 0

Expected result:
SharpEmu_V73_8_UI_ACTIVATION_POSTWAIT_RESULT_<timestamp>.zip

Send that ZIP back. It includes the exact current AGC, presenter, VideoOut,
Pad and movie/input sources so the following V73.9 can be a source-changing
fix at the proven failing stage instead of another blind UI workaround.
