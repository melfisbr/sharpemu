SharpEmu V75.0.1 SAFE
Bink2 runtime-loaded in-process RAD adapter

OBJETIVO
========
Eliminar radvideo64.exe / HWND / GDI capture para os Binks de UI que nao
possuem audio Bink embutido, especialmente logo_intro_loop.bk2 e main_menu.bk2.

O SharpEmu atual ja contem o backend gerenciado V75.0.0:
  BinkNativeSdkAbiV7500
  RadBinkNativeSdkDecoderV7500
  MovieMode.NativeRad
  MediaFramePlayback

O que faltava para operar sem o SDK completo era SharpEmu.BinkNative.dll.

V75.0.1 inclui um adapter C++ proprio do SharpEmu que NAO inclui codigo,
headers, .lib ou DLL proprietarios da RAD. Em runtime ele carrega um
bink2w64.dll x64 que o usuario forneca legitimamente e resolve somente:

  BinkOpen
  BinkClose
  BinkWait
  BinkDoFrame
  BinkCopyToBuffer
  BinkNextFrame
  BinkGetError (opcional)

A metadata do .bk2 (resolucao/fps/frame count/tracks) e lida do proprio header
KB2 pelo adapter, portanto ele nao depende do layout privado da struct HBINK.

AUDIO
=====
O adapter V75.0.1 NAO anuncia suporte a audio Bink.

Isso e intencional:
- logo_intro_loop/main_menu observados possuem 0 tracks e podem rodar native-rad;
- filmes com tracks Bink embutidos sao rejeitados pelo backend gerenciado e
  caem automaticamente para external RAD, preservando audio.

INTEGRACAO DA UI
================
Quando logo_intro_loop/main_menu abrem por NativeRad:
- nao existe radvideo64.exe para esses filmes;
- nao existe child HWND;
- nao existe SetParent/ShowWindow/region cloak;
- nao existe GDI capture;
- nao existe RAD_MAIN_MENU_CAPTURE_IMPORT;
- o frame Bink entra em MediaFramePlayback dentro do SharpEmu;
- guest UI e Bink permanecem no mesmo pipeline de render/Vulkan.

Isso remove a classe de bugs observada nas V118.7/V3.12, em que duas superficies
Windows e/ou uma captura GDI precisavam ser sincronizadas com o guest.

SOBRE github.com/marcussacana/Bink2
====================================
O pacote desse repositorio NAO e redistribuido nem incorporado aqui.

Ele e util como referencia de compatibilidade da familia Bink2, mas o README
do proprio repositorio descreve um encoder e DLLs modificadas para arquivos
gerados por ele; nao e uma implementacao open-source do decoder.

A V75.0.1 exige um bink2w64.dll x64 compatível. RUN_0B rejeita PE x86.

COMO FORNECER O RUNTIME
=======================
Opcao A:
  $env:SHARPEMU_BINK_RUNTIME_DLL = 'C:\caminho\bink2w64.dll'

Opcao B:
  coloque o arquivo em:
  <pacote>\ThirdParty\BinkRuntime\bink2w64.dll

Opcao C:
  se RAD Video Tools tiver bink2w64.dll sob Program Files\RADVideo, RUN_0B
  tenta encontra-lo automaticamente.

Nenhum bink2w64.dll e copiado para o ZIP.

ORDEM
=====
RUN_0
RUN_0B
RUN_1
RUN_2
RUN_3
RUN_4
RUN_5

RUN_6 remove apenas SharpEmu.BinkNative.dll implantado. Nenhum source do repo
e modificado por este pacote.

SURFACE
=======
Default:
  SHARPEMU_BINK_RUNTIME_SURFACE=5

Se um runtime compatível usar outro layout de 32-bit, pode-se A/B testar
3/4/5/6/12 sem recompilar o adapter.
