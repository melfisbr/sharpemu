SharpEmu Demon's Souls EBOOT UI Resource IO V73.7.1 SAFE

WHY V73.7 WAS REFUSED
The repository's KernelMemoryCompatExports.cs no longer matched the older
src(20260814-134806) snapshot. The user's precheck reported:
  61D151DF2DDD8E9B1E7AF9451F1BDE3A7D109DB0B92F37F04D5BB60B4AD74103

That hash exactly matches the V73.0.13.1 ResourceDirent/TitleIsolation payload.
V73.7.1 is rebuilt from that exact current file, so the title-isolation/dirent
changes are preserved.

FUNCTIONAL FIX
KernelReadUnderscore (_read/read/sceKernelRead) now acquires the FileStream
monitor while _fdGate is still held. KernelCloseCore removes the fd under the
same gate and disposes the stream under that monitor. This closes the
lookup->close->disposed-read race for asynchronous resource readers.

AMPR CHANGE FROM V73.7
AmprExports.cs is no longer modified at all. The existing
SHARPEMU_LOG_AMPR_READS=1 trace is enabled and the diagnostic filters
scripts/workspaces/coredata/misc/ui paths after capture. This removes the second
full-file baseline dependency.

SECOND V73.7 SCRIPT BUG FIXED
The previous diagnostic had a mistyped EBOOT SHA. The exact uploaded/main
Demon's Souls EBOOT SHA-256 is:
  22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E

CURRENT KERNEL BASELINE
  61D151DF2DDD8E9B1E7AF9451F1BDE3A7D109DB0B92F37F04D5BB60B4AD74103

SAFETY
- V73.0.13.1 title isolation is preserved.
- Only KernelMemoryCompatExports.cs is replaced.
- Exact current SHA guard is checked before install.
- Automatic rollback on build failure.
- APR/AMPR ABI semantics are not changed.
- AmprExports.cs is not modified.
