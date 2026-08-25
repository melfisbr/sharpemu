SharpEmu V75.0.4.8 - FFmpeg-core exclusivo para Binks + Binks da UI
==========================================================================

OBJETIVO
- Tornar FFmpeg-core in-process o owner normal de TODOS os arquivos .bk2 quando SHARPEMU_BINK_MODE=native-rad.
- Cobrir filmes fullscreen e Binks usados pela UI: logo_intro_loop.bk2, main_menu.bk2, main_menu_ngp.bk2 e demais BK2 naturais do guest.
- Impedir que a politica antiga V75.0.1.3 RAD_EXTERNAL_FORCE converta native-rad para RAD externo.
- Impedir fallback automatico para NIHAV ou RAD se o FFmpeg falhar.
- Preservar as demais melhorias do fork local.

ESTADO BASE ESPERADO
- V75.0.4.5: FfmpegRuntime/FfmpegVideoDecoder in-process ja compilados.
- V75.0.4.6/7: runtime ffmpeg-core 3b502d4 provisionado em plugins.
- V75.0.4.3: ownership/suppression do NIHAV instalado.

O QUE V75.0.4.8 MUDA
1. ResolveMode recebe um guard antes de qualquer RAD_EXTERNAL_FORCE historico.
2. AttachMovieLocked recebe uma rota exclusiva antes de qualquer rewrite RAD/NIHAV da UI.
3. AttachRadMovieLocked bloqueia RAD externo enquanto native-rad for o owner solicitado.
4. AttachNihavMovieLocked bloqueia NIHAV enquanto native-rad for o owner solicitado.
5. TryRestartDemonSoulsUiBinkLoop continua reabrindo pelo TryOpenPreferredNativeRadDecoderV75045, portanto pelo FFmpeg.
6. Falha do FFmpeg em native-rad termina a tentativa do filme; nao cai silenciosamente para outro decoder.

ARQUITETURA NORMAL
BK2 -> ResolveMode NativeRad
    -> AttachMovieLocked exclusive guard
    -> AttachRadNativeMovieLocked
    -> TryOpenPreferredNativeRadDecoderV75045
    -> FfmpegVideoDecoder
    -> avformat/avcodec/swscale/swresample in-process
    -> video BGRA -> MediaFramePlayback/Vulkan
    -> audio PCM -> IHostAudioStream

UI BK2
- O mesmo FfmpegVideoDecoder alimenta a composicao guest existente.
- Nao existe RAD child window no caminho native-rad.
- Nao existe NIHAV fallback no caminho native-rad.

ATRACT MOVIE
- attract_movie.bk2 continua com video pelo FFmpeg.
- O audio AT9 sidecar existente e preservado e liberado no first-visible-frame.

RUNTIME
Principais DLLs:
- avcodec-61.dll
- avformat-61.dll
- avutil-59.dll
- swscale-8.dll
- swresample-5.dll

RUN_4
- Primeiro reutiliza as DLLs AMD64 ja instaladas em Release/plugins.
- So invoca o target local FetchFfmpegRuntime se alguma DLL obrigatoria estiver ausente.
- Nao executa git clone/fetch/checkout/reset/clean e nao substitui source do fork.

SEQUENCIA
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd
RUN_5_DEMONS_FFMPEG_EXCLUSIVE_UI_TEST.cmd

COMPATIBILIDADE
RUN_5_DEMONS_FFMPEG_NATIVE_AV_TEST.cmd e mantido como alias para o novo RUN_5.

SINAIS DE SUCESSO
[BINK-FFMPEG][V75.0.4.5] runtime_initialized
[BINK-FFMPEG][V75.0.4.5] bridge_attached
[BINK-FFMPEG][V75.0.4.8] route_locked ... backend=ffmpeg-core-inprocess ui_and_fullscreen=True
[BINK-FFMPEG][V75.0.4.5] first_visible_frame

NAO DEVE EXECUTAR
[V75.0.1.3][RAD_EXTERNAL_FORCE_CASE]
bink2.rad_required_started
radvideo64.exe
Bink2 NIHAV bridge attached
bink2.nihav_ready

OBSERVACAO
O source historico do RAD/NIHAV e preservado para diagnostico explicito. A V75.0.4.8 bloqueia esses caminhos apenas quando o owner solicitado e native-rad.
