SharpEmu Demon's Souls EBOOT Script Package Reachability V73.12 SAFE

V73.11.1 PROVED
- uistartmenu.cgpr resolved successfully.
- ID: 0xB54A744D.
- Size: 1,550,288 bytes / 0x17A7D0.
- Full 0x17A7D0 bytes copied to guest memory.
- AMPR result = 0.
- 21 UI .cgpr reads, 0 failures.
- cp11main.cgpr started.
- main loop started.
- ResourcePool::GatherResourceFileInfo completed.
- unresolved imports = 0.
- deviceLost = 0.

V73.11.1 also reached real guest rendering:
- 48 VideoOut FPS windows;
- 11 windows with submitted_fps > 0;
- 12 draw-bearing windows;
- 2,132 draws in those windows.

WHAT WAS NOT YET PROVEN
A successful AMPR read proves data delivery, not that the native ScriptPackage
pipeline instantiated/activated uistartmenu. V73.11.1's UI probe also had a
diagnostic blind spot: entry-thread sampling was still gated by
SHARPEMU_TRACE_DEMONS_ENTRY_WAIT.

V73.12 fixes that diagnostic blind spot and adds exact EBOOT-derived ranges for:
- StartScriptRoot
- ScriptPackage primary execution
- CPOLdrScriptPackageCommon::ApplyProperties
- LoadScriptPackageHelper::CreateGameObjects
- FinalizeGameObjectsJob
- AutoLoad/ManualLoad ApplyProperties
- LoadScript region
- StartMenu loader source region
- UIManager::IsSceneFullyLoaded
- UIManager::ShowHUDSceneImpl
- UIManager::AdvanceMenuStackSceneTransitions

The ranges come from PT_GNU_EH_FRAME boundaries plus RIP-relative xrefs to
strings in the exact EBOOT SHA:
22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

NO GAME SEMANTICS ARE CHANGED.
The patch only extends the dormant sampler. Entry-main is now sampled whenever
the UI or ScriptPackage probes are enabled, without enabling ENTRY_WAIT.

Current GuestSampler baseline:
E0637FA5E749DADBFA61C6FA54B86F39358511A3E191052BDB915F4A76D7E88D

Diagnostic:
- 2 ms RIP sampling
- 5 s reports
- waits for successful uistartmenu full read
- then observes 90 additional seconds
- hard ceiling 480 s
- resource/AMPR script traces enabled
- heavy AGC/Vulkan resource traces disabled

Result:
SharpEmu_V73_12_SCRIPT_PACKAGE_REACHABILITY_RESULT_<timestamp>.zip
