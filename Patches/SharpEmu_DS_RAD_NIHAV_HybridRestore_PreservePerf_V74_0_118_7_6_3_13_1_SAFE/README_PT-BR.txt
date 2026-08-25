SharpEmu V74.0.118.7.6.3.13.1 SAFE
Demon's Souls PPSA01341
RAD -> NIHAV historical hybrid restore, preserving later performance fixes

GOAL
====
Restore the proven media ownership split observed around V74.0.88.6.2
without rolling the repository back:

- ps_studios / attract / logo_intro one-shot movies:
  official external RAD
- logo_intro_loop.bk2:
  internal NIHAV + guest compositor
- main_menu.bk2 / main_menu_ngp.bk2:
  internal NIHAV + guest compositor

WHY
===
V118.3 changed SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE into an
"enabled unless exactly 0" default. That displaced the older
V74.0.84.1 internal NIHAV path for persistent UI Binks.

V3.13 changes only that ownership default:
the RAD-interactive UI route now requires explicit value "1".

PRESERVED PERFORMANCE WORK
==========================
This package DOES NOT MODIFY and hashes before/after:
- DirectExecutionBackend.NativeWorker.cs
  - V74.0.3.4 no-managed-inline safety
  - V73.20.4.1 dedicated native executors
  - V74.0.10 renderer/resource native lane
- VulkanVideoPresenter.cs
  - V74.0.56.16 adaptive unified compute
  - V74.0.68 deferred idle backoff
  - V74.0.105 direct-YUV presenter path
- AgcExports.cs
  - V74.0.71 dedicated wait drain
  - V74.0.72 gate-owner wait drain
- NihavBink2Decoder.cs
  - V74.0.100.1 title-loop reservoir
  - V74.0.105 direct YUV
  - V74.0.109 chroma repair
  - V74.0.110 reference color
- MediaFramePlayback.cs
  - V74.0.109 realtime playback reservoir

TOUCHED SOURCE
==============
src\SharpEmu.Libs\Media\HostMovieBridge.cs

KNOWN OBSERVED BASELINE
=======================
HostMovieBridge.cs SHA256:
D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B

The SAFE precheck also accepts structurally compatible hash drift,
provided the exact old/new ownership hunk and all required historical
and performance markers are present.

EXPECTED RUNTIME
================
logo_intro.bk2:
  Bink RAD bridge attached

logo_intro_loop.bk2:
  [V74.0.84.1][UI_BINK_INTERNAL]
  [V74.0.118.7.6.3.13][RAD_NIHAV_HYBRID_ROUTE]
  Bink2 NIHAV bridge attached

main_menu.bk2:
  [V74.0.84.1][UI_BINK_INTERNAL]
  [V74.0.118.7.6.3.13][RAD_NIHAV_HYBRID_ROUTE]
  Bink2 NIHAV bridge attached
  [V74.0.81][TITLE_LOOP_PRESS_COMPOSITE]

NOT EXPECTED FOR UI BINKS
=========================
Bink RAD bridge attached: logo_intro_loop.bk2
Bink RAD bridge attached: main_menu.bk2
[V74.0.118.3][UI_BINK_RAD_INTERACTIVE_ROUTE]

ROLLBACK
========
RUN_3 backs up only HostMovieBridge.cs.
Build failure restores it automatically.
RUN_6 manually restores the last V3.13 backup.


V74.0.118.7.6.3.13.1 - PACKAGE/PARSER FIX
==========================================
A V3.13 anterior NAO alterou o source.

O log fornecido mostrou que common.ps1 falhou no parser antes do precheck,
principalmente em Get-OldHunk/Get-NewHunk. Como RUN_3 nem conseguiu carregar
common.ps1, nenhum backup/aplicacao/build da V3.13 aconteceu.

Esta V3.13.1 preserva a implementacao C# V3.13 sem mudar o objetivo:
- RAD oficial continua dono dos filmes one-shot/fullscreen;
- logo_intro_loop/main_menu/main_menu_ngp usam NIHAV interno + compositor guest;
- os arquivos de performance guardados continuam byte-for-byte inalterados.

Correcoes de empacotamento:
- Get-OldHunk/Get-NewHunk reescritos sem a expressao PowerShell ambigua;
- Normalize-Lf no HostMovieBridge reescrito com variavel intermediaria;
- RUN_0 faz parser preflight de common.ps1 antes de dizer PASSED;
- RUN_1 valida manifest + parseia TODOS os .ps1 antes de carregar common.ps1;
- scripts usam ErrorActionPreference=Stop antes do dot-source;
- wrappers usam -NonInteractive e propagam ERRORLEVEL;
- transform old/new possui selftest;
- baseline exato conhecido:
  before=D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B
  after =55FF1D3ED163F5AE2295F83278A4B8281ABBBAF4878BA2ED26C6D4E60BC02E6F

Marcadores C# permanecem V74.0.118.7.6.3.13 porque a implementacao de media
nao mudou; V3.13.1 e a revisao SAFE do pacote.

NAO faca rollback da V3.13 que falhou no parser.
