SharpEmu V75.0.4.7 - FFmpeg-core Bink2 A/V in-process / Nihav OFF
=================================================================

OBJETIVO
- Usar ffmpeg-core Bink2-capable como decoder principal do MovieMode.NativeRad.
- Decodificar video Bink2 pela API C do FFmpeg via FFmpeg.AutoGen, sem ffmpeg.exe.
- Decodificar audio Bink embutido para PCM pelo mesmo FfmpegVideoDecoder.
- Manter Nihav suprimido enquanto NativeRad e o owner exclusivo estiverem ativos.
- Preservar as demais melhorias do fork local.

PRE-REQUISITO
Este pacote e incremental sobre a V75.0.4.3, cujo RUN_3 ja passou no seu fork.

POLITICA DO FORK LOCAL
- Nao executa git clone/fetch/pull/checkout/reset/clean/rebase/switch.
- Nao aplica source vindo do GitHub ao seu fork.
- O RUN_3 compila src\SharpEmu.CLI\SharpEmu.CLI.csproj do SEU fork.
- O proprio SharpEmu.CLI.csproj local ja fixa FfmpegRuntimeTag=3b502d4 e possui
  FetchFfmpegRuntime + ffmpeg-windows-x64.zip.
- Se as DLLs ainda nao estiverem em plugins, o RUN_4 apenas repete o build do
  CLI local para que ESSE target ja existente no seu fork forneca o runtime.

ARQUITETURA
BK2 -> FfmpegVideoDecoder (interop C#) -> DLLs nativas FFmpeg x64
    -> video BGRA -> MediaFramePlayback/Vulkan
    -> audio PCM stereo -> IHostAudioStream

DLLS NATIVAS PRINCIPAIS
- avcodec-61.dll
- avformat-61.dll
- avutil-59.dll
- swscale-8.dll
- swresample-5.dll

A SharpEmu.BinkNative.dll V75.0.4 permanece apenas como adapter legado para A/B.
Ela NAO e o codec principal desta versao. O decode Bink2 real passa pelas DLLs
nativas ffmpeg-core carregadas in-process.

SINCRONISMO A/V
FfmpegVideoDecoder agora implementa IMediaPresentationAware e IMediaFrameBufferPolicy.
Audio PCM produzido durante o prime/predecode fica em preroll limitado e so e
liberado em NotifyPresentationStarted(), no primeiro frame visivel.

Para attract_movie.bk2, sem audio Bink embutido no fluxo observado, o AT9 sidecar
continua preparado por BinkHostAudioBridge e e liberado na mesma fronteira do
primeiro frame visivel.

NIHAV
- Nao e fallback normal do NativeRad.
- O ownership/suppression instalado na V75.0.4.3 e preservado.
- main_menu.bk2 e main_menu_ngp.bk2 reabrem pelo mesmo FFmpeg in-process.

ADAPTER LEGADO
So pode ser usado manualmente com:
  SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK=1

SEQUENCIA
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD.cmd
RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd
RUN_5_DEMONS_FFMPEG_NATIVE_AV_TEST.cmd

ROLLBACK DO SOURCE
RUN_6_ROLLBACK_SOURCE.cmd

SINAIS DE SUCESSO
[BINK-FFMPEG][V75.0.4.5] runtime_initialized
[BINK-FFMPEG][V75.0.4.5] bridge_attached
[BINK-FFMPEG][V75.0.4.5] first_visible_frame

NAO DEVE APARECER DURANTE NATIVE-RAD
Bink2 NIHAV bridge attached
bink2.nihav_ready
fallback_external_rad

CORRECOES V75.0.4.5
- Corrige ParserError do common.ps1 em Windows PowerShell 5.1 (remove escapes C-style \" em strings PowerShell).
- Remove atribuicoes a $host, que colidem com a variavel automatica read-only $Host.
- RUN_1 e standalone: valida o manifesto e usa o parser real do PowerShell antes de carregar common.ps1.
- RUN_1 rejeita automaticamente novas ocorrencias de $Host assignment e escapes C-style.
- Nao faz git clone/fetch/checkout/reset/clean.
- O runtime FFmpeg continua sendo obtido pelo target FetchFfmpegRuntime ja existente no SharpEmu.CLI.csproj do fork local.


CORRECOES V75.0.4.6
- RUN_4 nao espera mais que `dotnet build` execute FetchFfmpegRuntime.
- RUN_4 chama diretamente o target LOCAL `FetchFfmpegRuntime` do SharpEmu.CLI.csproj.
- O target continua usando FfmpegRuntimeTag=3b502d4 e ffmpeg-windows-x64.zip definidos pelo proprio fork.
- Nenhum comando Git e executado e nenhum source do fork e substituido.
- Depois do target, RUN_4 localiza o `extracted\bin`, valida AMD64 e copia todas as DLLs para plugins de Release e Debug.
- O source C# FFmpeg/ownership permanece o V75.0.4.5 ja compilado; esta versao corrige apenas o provisionamento do runtime.


CORRECOES V75.0.4.7
- Corrige o falso positivo do RUN_1 da V75.0.4.6: o validador nao acusa mais sua propria string de detector de downloader.
- A politica de comandos usa AST real do PowerShell e inspeciona apenas CommandAst executaveis.
- Mantem o runtime FFmpeg-core 3b502d4 ja provisionado pelo target local FetchFfmpegRuntime.
- Nao altera novamente o C# FFmpeg/ownership se a V75.0.4.5 ja estiver aplicada.
