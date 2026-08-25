V75.0.4.10 PS STUDIOS GUEST-LIVE / FFMPEG EXCLUSIVE
======================================================
Diagnostico V75.0.4.9:
- FFmpeg abriu e concluiu ps_studios_logo.bk2 normalmente.
- RAD externo e NIHAV permaneceram fora da rota.
- o fresh-frame handoff foi armado, mas nenhum novo trabalho GPU guest apareceu.
- o antigo HostMovieExecutionGate ainda tratava ps_studios_logo como one-shot hard-gated e estacionava BPE workers / throttle GPU.

Correcao V75.0.4.10:
- quando SHARPEMU_BINK_MODE=native-rad, ps_studios_logo.bk2 entra no mesmo TITLE_TIMELINE_PASSTHROUGH guest-live usado por attract/logo/menu.
- FFmpeg continua visual owner exclusivo.
- lifecycle do decoder, active decoder count, completion shim e audio permanecem intactos.
- HostMovieExecutionGate.Begin/End nao sao usados nesse filme na rota FFmpeg.
- CPU park e GPU throttle ficam desligados durante PS Studios.
- V75.0.4.9 fresh-frame handoff continua preservado.
- modo RAD explicito continua com o comportamento historico.
- nenhuma operacao Git e usada.

Sinais esperados:
[V74.0.77][TITLE_TIMELINE_PASSTHROUGH] action=start file='ps_studios_logo.bk2' hle_gate=False cpu_park=False gpu_throttle=False guest_input=True
[BINK-FFMPEG][V75.0.4.5] bridge_attached ... decoder=ffmpeg-core-inprocess
[BINK-FFMPEG][V75.0.4.8] route_locked ... external_rad=False nihav=False
[V31.7.22][POST_STUDIOS_FRESH_FRAME] released ...

Nao deve aparecer entre natural_guest_movie_observed ps_studios e Bink2 bridge completed:
guest_worker_event_park
bink2.host_cpu_affinity_limit

V75.0.4.9 BUILD RECOVERY
=============================
Esta revisao preserva integralmente o C# V75.0.4.8 ja aplicado e corrige somente o fluxo SAFE de backup/build.
Corrige StrictMode quando o stage contem exatamente um arquivo: @(Get-ChildItem ...).Count.
Pode ser executada sobre source ja transformado; o apply e idempotente e ainda executa o build.

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


V75.0.4.9 POST-STUDIOS FRESH-FRAME HANDOFF
-------------------------------------------
O runtime V75.0.4.8.1 confirmou FFmpeg in-process no ps_studios_logo.bk2, mas o cover V1.1.4 ficou com guest_flips_hidden=True ate expirar por timeout de 45 segundos. Esse cover era liberado historicamente pelo ShowWindow do attract no RAD externo, evento que nao existe na rota FFmpeg.

Esta revisao:
- mantem FFmpeg como owner exclusivo dos Binks fullscreen e da UI;
- nao arma o cover V1.1.4 para ps_studios_logo quando native-rad/FFmpeg esta ativo;
- ao completar/fechar PS Studios, chama SubmitHostMovieHandoffBlackV11;
- esse handoff arma V31.7.22 POST_STUDIOS_FRESH_FRAME e libera no primeiro frame guest realmente novo;
- preserva o cover V1.1.4 no modo RAD explicito;
- nao toca Vulkan queues, shaders, DCC, IME ou performance.
