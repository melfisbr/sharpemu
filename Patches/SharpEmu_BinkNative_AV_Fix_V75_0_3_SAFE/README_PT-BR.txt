SharpEmu Bink Native A/V V75.0.3 SAFE
=====================================

Objetivo
--------
Substituir a bridge V75.0.2 por um adaptador Windows x64 que usa o runtime Bink2
no mesmo processo do SharpEmu para:

  - abrir .bk2;
  - decodificar/copiar video para BGRA;
  - habilitar o sistema de som nativo do Bink antes de BinkOpen;
  - deixar o proprio runtime Bink decodificar/tocar audio embutido;
  - manter video e audio na mesma instancia/timeline Bink;
  - expor o clock ao MediaFramePlayback existente.

ABI SharpEmu
------------
ABI: 0x00010000
Capabilities: 0x0000000F
  bit 0 = video
  bit 1 = embedded audio
  bit 2 = clock
  bit 3 = BGRA

A DLL somente define InfoFlagEmbeddedAudioActive quando:
  1. o .bk2 declara uma ou mais faixas de audio; e
  2. BinkSetSoundSystem consegue inicializar um backend de audio.

Assim o SharpEmu nao aceita silenciosamente um filme com audio sem provedor.

Backends de audio tentados automaticamente
-------------------------------------------
  1. BinkOpenXAudio29
  2. BinkOpenXAudio28
  3. BinkOpenXAudio2
  4. BinkOpenXAudio27
  5. BinkOpenWaveOut
  6. BinkOpenDirectSound

Override opcional:
  SHARPEMU_BINK_AUDIO_BACKEND=xaudio29|xaudio28|xaudio2|xaudio27|waveout|directsound

Faixa de audio opcional:
  SHARPEMU_BINK_AUDIO_TRACK=0

Dependencia do codec
--------------------
SharpEmu.BinkNative.dll e uma camada nativa de interoperabilidade; ela NAO
redistribui codigo proprietario RAD/Bink. Para a rota RAD nativa, coloque um
bink2w64.dll Windows AMD64 compativel ao lado do adaptador, ou indique-o por:

  SHARPEMU_BINK_RUNTIME_DLL=C:\caminho\bink2w64.dll

O pacote valida arquitetura e exports antes do teste. Uma DLL I386/Win32 nao
pode ser carregada no processo x64 do SharpEmu.

Demon's Souls
-------------
No source atual, attract_movie.bk2 e tratado como video sem faixa Bink embutida
e o audio AT9 sidecar continua no BinkHostAudioBridge. Para um .bk2 com audio
embutido, esta V75.0.3 deixa audio e video sob a mesma instancia nativa Bink.

Execucao
--------
Execute a partir de:
  C:\Users\Edpo\Documents\GitHub\sharpemu\Patches

RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_INSTALL_NATIVE_AV.cmd
RUN_4_PROBE_RUNTIME.cmd "C:\caminho\bink2w64.dll"
RUN_5_DEMONS_NATIVE_AV_TEST.cmd

Se RUN_4 encontrar runtime automaticamente, o argumento pode ser omitido.

Rollback
--------
RUN_6_ROLLBACK.cmd

Os backups e resultados sao gravados em Patches.
