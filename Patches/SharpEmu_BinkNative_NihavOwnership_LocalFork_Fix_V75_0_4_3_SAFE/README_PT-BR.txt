SharpEmu Bink Native + Nihav Ownership V75.0.4.3 LOCAL-FORK SAFE
================================================================

OBJETIVO
- Preservar o fork local em C:\Users\Edpo\Documents\GitHub\sharpemu.
- NUNCA executar git clone, git fetch, git checkout, git reset, git clean ou download de source.
- Aplicar somente ownership NativeRad/Nihav por transformacoes estruturais/semanticas.
- Manter a DLL SharpEmu.BinkNative.dll AMD64 e o caminho A/V NativeRad.
- RAD externo/radvideo64 permanece desabilitado por padrao.

CORRECOES SOBRE V75.0.4.2
1. h06 do HostMovieBridge deixa de exigir uma forma textual antiga. Se o fork local
   removeu/reescreveu o fallback RAD, o pacote aceita a forma mais nova desde que
   nao exista fallback externo implicito do tipo SHARPEMU_BINK_NATIVE_FALLBACK != 0.
2. Hunks reformatados podem ser reconhecidos por pos-condicao semantica para nao
   sobrescrever melhorias locais do fork.
3. RUN_4 e LOCAL-ONLY. Ele apenas procura um ffmpeg.exe AMD64 JA EXISTENTE no fork,
   artifacts, tools, third_party, external, vendor, deps/dependencies, Patches,
   SHARPEMU_FFMPEG_CORE_EXE ou PATH.
4. RUN_4 valida o runtime com um frame real de ps_studios_logo.bk2 quando disponivel.
5. RUN_4 nao possui URLs nem comandos de Git que alterem/baixem repositorios.
6. O Nihav continua alterado diretamente: TryOpen recusa o decoder enquanto o lease
   exclusivo NativeRad estiver ativo, evitando video/audio duplicado.

IMPORTANTE SOBRE O RUNTIME
A DLL nativa V75.0.4 usa um ffmpeg.exe Bink2-capable como backend headless. Esta
versao NAO baixa nem compila uma copia online. Se nenhum runtime local compativel
existir, RUN_4 aborta sem alterar seu fork. Voce pode passar um runtime local:

  RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd "D:\meu-runtime\ffmpeg.exe"

ou definir SHARPEMU_FFMPEG_CORE_EXE para um ffmpeg.exe local.

ORDEM
RUN_1_VALIDATE_PACKAGE.cmd
RUN_2_PRECHECK.cmd
RUN_3_APPLY_BUILD_INSTALL_NATIVE_AV.cmd
RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd
RUN_5_DEMONS_NATIVE_AV_TEST.cmd

ROLLBACK
RUN_6_ROLLBACK.cmd

POLITICA SAFE
- Backup antes de qualquer source write.
- Build falhando nao deve ser confundido com runtime setup.
- Hash drift do HostMovieBridge e aceito apenas quando cada ownership hunk e
  reconhecido exatamente ou sua pos-condicao semantica ja existe.
- Codigo local nao relacionado aos hunks nao e substituido.
