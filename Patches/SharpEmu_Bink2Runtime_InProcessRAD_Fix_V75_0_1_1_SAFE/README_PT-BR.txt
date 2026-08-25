SharpEmu V75.0.1.1 SAFE
Bink2 Runtime In-Process RAD adapter - non-fatal runtime discovery fix

What the V75.0.1 log proved
===========================
RUN_0B correctly found no compatible bink2w64.dll.
The package then had a packaging/workflow bug:
RUN_3 called the probe, the probe returned without creating a state file,
and build_adapter.ps1 immediately tried to read that missing file.

Important architectural point
=============================
SharpEmu.BinkNative.dll does NOT link against RAD at build time.
It uses LoadLibrary/GetProcAddress at runtime.
Therefore the adapter can be compiled and deployed even when bink2w64.dll
is not currently available.

V75.0.1.1 fixes this:
- automatic probe NOT_FOUND is non-fatal and writes state;
- RUN_3 always builds/deploys SharpEmu.BinkNative.dll;
- if a compatible user-supplied bink2w64.dll is found, it is copied next to
  the adapter in Debug/Release plugins\bink2 and native RAD becomes ready;
- if it is not found, external RAD fallback stays enabled and RUN_3 still passes;
- runtime candidate discovery also checks:
    * explicit argument
    * SHARPEMU_BINK_RUNTIME_DLL
    * package/repo ThirdParty\BinkRuntime
    * deployed plugins\bink2 directories
    * directory of SHARPEMU_RADVIDEO64
    * Program Files\RADVideo
    * PATH / SearchPath
    * adapter/process/current directories in the native DLL itself
- RUN_4 no longer crashes simply because runtime_dll is absent;
- analyzer distinguishes native-ready from external-fallback mode.

No proprietary RAD/Bink binary is included.
A real in-process RAD decoder still requires a legitimate compatible
bink2w64.dll x64 exposing:
BinkOpen, BinkClose, BinkWait, BinkDoFrame, BinkCopyToBuffer, BinkNextFrame.

If no such DLL exists on the machine, V75.0.1.1 can prepare the adapter but
cannot manufacture the proprietary decoder. SharpEmu will continue using its
existing external RAD fallback.

SourceMutation=NONE
ExternalRADFallback=PRESERVED
