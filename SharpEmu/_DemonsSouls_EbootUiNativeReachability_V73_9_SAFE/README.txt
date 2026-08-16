SharpEmu Demon's Souls EBOOT UI Native Reachability V73.9 SAFE

V73.8 PROVED
- Options reached the guest pad path: 2 press edges / 1 release edge.
- watched wait targets: 8.
- PM4 producer overlaps: 13.
- WRITE_DATA applied: 13.
- wait-resume trace events: 95.
- runtime unresolved imports: 0.
- deviceLost: 0.

DIAGNOSTIC CORRECTION
The INFO line "Vulkan VideoOut presented guest frame" is intentionally one-shot.
It does not count every guest frame. V73.9 enables SHARPEMU_LOG_VIDEOOUT_FPS=1
and uses ReportPresentedFrame's real per-present counter.

EXACT EBOOT UI FUNCTION RANGES
  HasOpenMenus: 0xDC2500-0xDC2580  bool UIManager::HasOpenMenus() const
  PrintSceneState: 0xDC4DE0-0xDC5750  void UIManager::PrintSceneState()
  ShowHudSceneRegion: 0xDCF210-0xDD0C80  uiShowHudScene
  TransitionShowHUDValidate: 0xDDAD30-0xDDAEB0  TransitionShowHUDScene::Transition_Validate
  ShowLegacyMenuA: 0x1488C20-0x1488C30  ShowLegacyMenu xref A
  ShowLegacyMenuB: 0x14893F0-0x1489410  ShowLegacyMenu xref B
  StartMenuThink: 0x148ED10-0x148F350  CComponentUIBehaviorStartMenuInputHandler::Think
  StartMenuHandleInputFocus: 0x148F350-0x148F8C0  CComponentUIBehaviorStartMenuInputHandler::HandleInputFocus

The ranges come from the uploaded EBOOT's PT_GNU_EH_FRAME boundaries plus
RIP-relative xrefs to the corresponding native UI strings.

V73.9 adds a dormant sampler classification to
DirectExecutionBackend.GuestSampler.cs. It changes no guest state and no UI
logic. With SHARPEMU_TRACE_DEMONS_UI_METHODS=1 it emits first-hit and cumulative
sample counts for the exact functions above.

Diagnostic:
- guest RIP sampling: 1 ms
- report interval: 5 s
- real VideoOut FPS counting enabled
- auto Options: 90/105/120/135/150 s
- scanout lineage enabled
- heavy AGC/resource tracing disabled

Keep the emulator open until at least 160 seconds from launch.

Source baseline:
  DirectExecutionBackend.GuestSampler.cs
  9FEB4664DDA918AD46A8049161B6812A162EC3D07B7DD4632921282E03FEA1F3

Result:
  SharpEmu_V73_9_UI_NATIVE_REACHABILITY_RESULT_<timestamp>.zip
