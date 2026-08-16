SharpEmu Demon's Souls EBOOT UI Resource I/O V73.7 SAFE

AUDITED INPUTS
EBOOT SHA-256:
  22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E
source snapshot:
  src(20260814-134806).zip
  SHA-256 2F3D0AD28E28DEDC8F8E977BFA0BC35AACBCB080B4D716D696344DCC2AE4B81

WHAT THE EBOOT PROVES
The title imports the complete resource I/O chain:
- sceKernelAprResolveFilepathsToIds
- sceKernelAprResolveFilepathsToIdsAndFileSizes
- sceKernelAprResolveFilepathsWithPrefixToIdsAndFileSizes
- sceKernelAprGetFileStat
- sceAmprAprCommandBufferReadFile
- sceKernelOpen / Read / Pread / Stat / Fstat / Getdents / Lseek
- libc fopen / fread / fseek / ftell / fclose

All of those functions have implementations in the supplied SharpEmu source.

The static wrapper at 0x1DC161F validates the current AMPR ReadFile register
mapping exactly. The APR caller at 0x815AD5 validates the current pointer-array,
count, ids, sizes and error-index layout. V73.7 therefore DOES NOT rewrite the
APR/AMPR ABI.

UI/resource references in the EBOOT include Core.Res.FileLoader,
StartMenuInputHandler, UIManager::HasOpenMenus, UITransition_ShowHUDScene,
uiShowHudScene and numerous *_ui.cgpr resource paths. This confirms the UI is
loaded through the title's normal resource pipeline rather than a missing
special "PS5 UI" syscall.

CONCRETE SOURCE CORRECTNESS BUG
KernelPreadAtV59 and lseek already acquire the FileStream monitor while the fd
table is locked. KernelCloseCore removes the fd and locks the same stream before
Dispose(). KernelReadUnderscore did NOT hold that monitor after lookup.

That leaves this valid race:
  FileLoader read: lookup stream -> releases _fdGate
  another guest thread: close(fd) -> removes + disposes stream
  FileLoader: stream.Position / stream.Read on disposed stream

V73.7 makes _read/read/sceKernelRead use the same fd/stream synchronization
contract as pread/lseek. This is generic correctness and directly relevant to
the EBOOT-imported async resource I/O chain. Bink completion-shim behavior is
preserved.

FOCUSED TRACE IMPROVEMENT
AmprExports gains:
  SHARPEMU_LOG_AMPR_READS_FILTER
with semicolon-separated path tokens and a bounded trace count.
The V73.7 diagnostic uses:
  scripts;workspaces;coredata;misc;ui

It also enables kernel SHARPEMU_LOG_IO with filter "scripts". Full AGC/Vulkan
tracing remains disabled.

WHAT IS ALREADY RULED OUT
- unresolved import/NID gap: runtime unresolved=0
- Gen5 import metadata: already 53/49 on the main EBOOT
- basic startup path resolution: resource dependency and cp11main CGPR load
- getdents as the demonstrated Demon’s resource blocker: the later title-scoped
  run completed GatherResourceFileInfo with dirent_calls=0
- basic VideoOut availability: a later representative run reached one real guest
  frame without device loss

RESULT
RUN_DEMONS_UI_RESOURCE_IO_V73_7.cmd produces:
  SharpEmu_V73_7_EBOOT_UI_RESOURCE_IO_RESULT_<timestamp>.zip

The result classifies whether a real script/UI AMPR or kernel read failure is
still occurring after the read-lifetime fix. No file-open success, short read
or missing optional asset is automatically faked as success.
