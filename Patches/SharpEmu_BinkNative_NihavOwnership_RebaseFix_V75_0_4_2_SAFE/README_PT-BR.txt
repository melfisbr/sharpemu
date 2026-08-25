SharpEmu Bink Native FFmpeg-Core A/V + NIHAV Ownership Rebase V75.0.4.2 SAFE
============================================================================

Objetivo
--------
Corrigir os dois problemas observados na V75.0.4.1 sem sobrescrever alteracoes mais novas do source:
1) HostMovieBridge.cs com SHA divergente (incluindo branches RAD/NIHAV mais recentes);
2) RUN_4 perdendo a raiz do pacote por colisao case-insensitive entre $script:PackageRoot e $packageRoot.

Ownership normal
----------------
BK2 -> HostMovieBridge/NativeRad -> SharpEmu.BinkNative.dll -> sharpemu/ffmpeg-core Bink2 -> BGRA + audio/clock

- SHARPEMU_BINK_MODE=native-rad
- SHARPEMU_BINK_NATIVE_PREFER=1
- SHARPEMU_BINK_NATIVE_EXCLUSIVE=1
- SHARPEMU_BINK_NATIVE_FALLBACK=0
- radvideo64.exe nao e usado no caminho normal
- NihavBink2Decoder.TryOpen bloqueia uma segunda abertura enquanto o lease NativeRad esta ativo

Rebase estrutural V75.0.4.2
---------------------------
HostMovieBridge.cs e NihavBink2Decoder.cs NAO sao substituidos por arquivos completos.
O pacote aplica somente hunks delimitados e idempotentes em transforms\. Cada hunk precisa estar exatamente no estado anterior ou no estado novo. Qualquer forma desconhecida aborta antes da escrita.

Isto permite preservar mudancas mais novas (por exemplo RAD/NIHAV hybrid/UI/performance) enquanto adiciona o ownership NativeRad. O SHA B8D4BE04E67D9516CC7BAFDA76A8D03D4D3368EA64858FA4B3382BE6DBB931C4 deixa de ser rejeitado apenas por ser diferente; ele ainda precisa passar todos os testes estruturais do RUN_2.

NIHAV
-----
A logica funcional de ownership foi introduzida na V75.0.4.1 e permanece com o marcador:
SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1

Enquanto NativeRad possui um filme, NihavBink2Decoder.TryOpen retorna false e registra nihav_suppressed. O lease so sobe apos a abertura nativa bem-sucedida e e liberado em CloseActiveLocked. SHARPEMU_BINK_MODE=nihav/bink2 e SHARPEMU_BINK_NATIVE_EXCLUSIVE=0 continuam como overrides deliberados de diagnostico.

RUN_4 corrigido
---------------
PowerShell trata PackageRoot/packageRoot como o mesmo nome. A V75.0.4.1 fazia $packageRoot=$null dentro de setup_ffmpegcore.ps1 e acabava zerando a raiz usada por common.ps1. A V75.0.4.2 usa $script:PackageRootV75042 e $ffmpegPackageRoot, nomes que nao colidem.

Demon's Souls
-------------
attract_movie.bk2 permanece video-only na trilha observada; o AT9 sidecar existente continua SharpEmu-owned e usa o latch do primeiro frame visivel. Para Binks com audio embutido, o backend NativeRad mantem o ownership A/V.

Ordem
-----
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD_INSTALL_NATIVE_AV.cmd
RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd
RUN_5_DEMONS_NATIVE_AV_TEST.cmd

RUN_4 nao usa caminho placeholder nem bink2w64.dll. Se nao existir ffmpeg.exe Bink2-capable previamente implantado, o script usa Git/vcpkg e a toolchain C/C++ Windows para construir o runtime sharpemu/ffmpeg-core pinned.

SAFE
----
- Backup antes de qualquer alteracao de source.
- HostMovieBridge/Nihav: merge estrutural, nao replace wholesale.
- Demais arquivos: hashes original/V75.0.4/final sao verificados antes de replace.
- RUN_6_ROLLBACK restaura o backup.
- Logs e ZIPs de resultado ficam em C:\Users\Edpo\Documents\GitHub\sharpemu\Patches.

DLL
---
Mesmo binario nativo AMD64 V75.0.4 revisado.
ABI: 0x00010000
Capabilities: 0x0000000F
Exports: 9, incluindo se_bink_notify_presented
Backend binary name: ffmpeg-core-headless-av-v75.0.4
