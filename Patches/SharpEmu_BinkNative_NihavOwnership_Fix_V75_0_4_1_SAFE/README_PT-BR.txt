SharpEmu Bink Native FFmpeg-Core A/V + NIHAV Ownership V75.0.4.1 SAFE
=====================================================================

Objetivo
--------
Fazer a DLL nativa AMD64 ser a proprietaria normal e exclusiva da reproducao Bink: video, audio embutido, clock, first-visible-frame, loop, skip/close e handoff. O NIHAV permanece no source apenas como fallback/debug explicito e nao pode abrir o mesmo BK2 em paralelo quando NativeRad esta ativo.

Revisao adicional solicitada
----------------------------
A V75.0.4 desviava os principais caminhos para NativeRad, mas nao alterava NihavBink2Decoder.cs diretamente. A V75.0.4.1 corrige isso no proprio NihavBink2Decoder.TryOpen e no roteamento HostMovieBridge.

Ownership normal
----------------
BK2 -> SharpEmu.BinkNative.dll -> sharpemu/ffmpeg-core Bink2 -> BGRA + audio PCM + clock

- SHARPEMU_BINK_MODE=native-rad
- SHARPEMU_BINK_NATIVE_PREFER=1
- SHARPEMU_BINK_NATIVE_EXCLUSIVE=1
- SHARPEMU_BINK_NATIVE_FALLBACK=0
- radvideo64.exe nao e usado no caminho normal
- Nihav nao abre durante ownership NativeRad

Excecoes deliberadas
--------------------
SHARPEMU_BINK_MODE=nihav (ou bink2) permite diagnostico Nihav explicito.
SHARPEMU_BINK_NATIVE_EXCLUSIVE=0 desativa a trava de ownership.

Demon's Souls
-------------
`attract_movie.bk2` permanece video-only na trilha observada; o AT9 sidecar existente continua SharpEmu-owned, mas e liberado pelo mesmo latch do primeiro frame visivel. Isso evita duplicar audio no Nihav.

Ordem
-----
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD_INSTALL_NATIVE_AV.cmd
RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd
RUN_5_DEMONS_NATIVE_AV_TEST.cmd

RUN_4 nao usa caminho placeholder e nao precisa de bink2w64.dll. Se o ffmpeg-core Bink2-capable ainda nao estiver instalado, precisa de Git e toolchain C/C++ Windows para construir o runtime pinned.

Baseline SAFE
-------------
Aceita o source exato de src(20260823-213917).zip, os arquivos intermediarios V75.0.4, ou os hashes finais V75.0.4.1. Qualquer outra divergencia aborta antes de escrever source.

DLL
---
A DLL e o mesmo binario nativo AMD64 V75.0.4 ja revisado; V75.0.4.1 e uma revisao de ownership C#/NIHAV.
ABI: 0x00010000
Capabilities: 0x0000000F
Optional export: se_bink_notify_presented
Backend binary name: ffmpeg-core-headless-av-v75.0.4
