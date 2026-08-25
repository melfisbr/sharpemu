SharpEmu V75.0.1.2 SAFE
RAD EXTERNAL RESTORE / PRE-V75 NATIVE ROLLBACK

OBJETIVO
========
Voltar exatamente ao fluxo RAD externo que existia antes da introducao do
backend V75 NativeRad, sem desfazer os patches V74 de UI/audio/Vulkan que ja
estavam presentes antes desse experimento.

CAUSA CONFIRMADA NO V75.0.1.1
==============================
O adapter SharpEmu.BinkNative.dll foi carregado e o modo solicitado "rad" foi
reescrito para "native-rad". Entretanto nao havia um runtime Bink2 x64
compativel. Os opens falharam e o fallback RAD externo nao ocorreu.

Isso deixou ps_studios_logo, attract_movie, logo_intro e main_menu sem o RAD
externo que funcionava antes.

ESTRATEGIA DE RESTORE
=====================
1. Procura todos os backups:
   .sharpemu-hotfix-backup\BinkNativeSdkV75_0_0_*

2. NAO escolhe simplesmente o backup mais novo.
   Seleciona o backup mais novo que NAO contenha:
   SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0
   SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0

   Portanto o restore aponta para o estado realmente anterior ao V75 NativeRad.

3. Restaura:
   src\SharpEmu.Libs\Media\HostMovieBridge.cs
   src\SharpEmu.Libs\Media\MediaFramePlayback.cs

4. Para:
   BinkNativeSdkAbiV7500.cs
   RadBinkNativeSdkDecoderV7500.cs

   restaura a copia preexistente se o backup tiver uma; caso contrario remove,
   exatamente como o rollback original V75.0.0 fazia.

5. Remove SharpEmu.BinkNative.dll dos outputs Debug/Release.

6. Se V75.0.1.x tiver registrado um runtime DLL copiado, remove somente a copia
   cujo SHA ainda coincidir com o state. DLLs alheias nao sao apagadas.

7. Faz build Release win-x64.

8. O RUN_4 testa explicitamente:
   SHARPEMU_BINK_MODE=rad
   SHARPEMU_BINK_NATIVE_PREFER=0
   SHARPEMU_RADVIDEO64=C:\Program Files (x86)\RADVideo\radvideo64.exe

SEGURANCA
=========
Antes do restore, RUN_3 cria outro backup com o estado V75 atual:
.sharpemu-hotfix-backup\V75_0_1_2_RAD_EXTERNAL_RESTORE_UNDO_<timestamp>

Se a build falhar, o estado V75 e restaurado automaticamente.

RUN_6 desfaz manualmente esta correcao, caso necessario.

SUCESSO ESPERADO
================
O analyzer deve terminar com:

classification=external-rad-pre-v75-route-restored

e mostrar attaches do RAD para:
- ps_studios_logo.bk2
- attract_movie.bk2
- logo_intro.bk2
- logo_intro_loop.bk2 (quando solicitado pelo guest)
- main_menu.bk2

Nao deve existir:
[BINK-NATIVE][V75.0.0] auto_selected
[BINK-NATIVE][V75.0.0] open_failed
[BINK-NATIVE][V75.0.0] attach_failed
bink2.rad_required_missing
