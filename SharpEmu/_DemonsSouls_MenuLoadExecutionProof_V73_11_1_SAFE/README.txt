SharpEmu Demon's Souls Menu Load / Execution Proof V73.11.1 SAFE

This revision changes NO repository source.

WHY V73.11 WAS INCONCLUSIVE
The uploaded V73.11 result ended before the menu stage:
- entry_samples=117
- boot_milestones=0
- auto_options_press=0
- only first three frames of ps_studios_logo.bk2 were reached
- no direct_boot_completed
- no Starting main loop

Therefore its zero UI counters do not disprove menu loading.

ALREADY PROVEN BY V73.7.1
[LOADER][TRACE] apr_resolve path='/app0/ui/scripts/_cmn/uistartmenu.cgpr' host='F:\JOGOSPS5\PPSA01341\ui\scripts\_cmn\uistartmenu.cgpr' index=460 count=1024 id=0xB54A744D size=1550288
[LOADER][TRACE] ampr.read_file: cmd=0x0000000608CB9490 id=0xB54A744D dst=0x00000004EC800000 size=0x000000000017A7D0 offset=0x0000000000000000 read=0x000000000017A7D0 result=0x00000000 path='F:\JOGOSPS5\PPSA01341\ui\scripts\_cmn\uistartmenu.cgpr' ret=0x0000000801DC1624

V73.7.1 also proved:
- cp11main.cgpr started
- main loop started
- ResourcePool::GatherResourceFileInfo completed
- AMPR failures=0
- kernel script IO failures=0
- disposed/io_error=0

WHAT V73.11.1 DOES
- hard ceiling 420 seconds;
- polls the live stderr for the exact successful full uistartmenu read;
- once observed, keeps the emulator alive another 45 seconds;
- enables script/APR/AMPR IO evidence;
- keeps V73.9 UI native RIP reachability at a lower-impact 8 ms interval;
- injects Options at 180/210/240/270/300/330 seconds;
- heavy AGC/Vulkan resource tracing remains off.

CLASSIFICATIONS
- menu-file-not-resolved
- menu-resolved-but-read-not-observed
- menu-read-observed-but-not-complete-success
- menu-read-complete-ui-native-code-not-yet-observed
- menu-read-complete-ui-manager-native-code-reached
- menu-read-complete-startmenu-native-code-reached

Current cumulative source hashes:
DirectExecutionBackend.cs:
  290981258FEFF096B3BB734B2F1E1877195F323444DDAEE58D7CF92830763F4D
DirectExecutionBackend.GuestSampler.cs:
  E0637FA5E749DADBFA61C6FA54B86F39358511A3E191052BDB915F4A76D7E88D

Result:
SharpEmu_V73_11_1_MENU_LOAD_EXECUTION_RESULT_<timestamp>.zip
