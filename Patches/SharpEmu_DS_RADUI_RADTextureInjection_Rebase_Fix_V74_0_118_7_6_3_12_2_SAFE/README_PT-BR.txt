SharpEmu V74.0.118.7.6.3.12.2 SAFE - Demon's Souls RAD/UI Guest Texture Injection

WHY V3.11 FAILED
================
V3.11 still treated RAD and the guest as two Windows presentation surfaces.
For main_menu it literally clipped the RAD child to x=653..1920 and y=0..940,
leaving the guest window visible below. That cannot reproduce the PS5 render graph.
The runtime also entered the generic descriptorless DIRECT fallback for both
logo_intro_loop and main_menu, which can turn a UI Bink into a fullscreen owner.

SOURCE/EBOOT CONTRACT
=====================
The active HostMovieBridge already describes logo_intro_loop/main_menu/main_menu_ngp
as Binks sampled through guest Y/UV textures while the guest continuously renders UI.
The Demon's Souls binary evidence contains CCPLdrBinkSimpleMovie, frame_bufs Plane,
and 'BinkGPU Agc registerResource', matching a resource/AGC model rather than a
second desktop compositor. VideoOut SubmitFlip is the final SharpEmu display boundary.

V3.12 PIPELINE
==============
official RAD external decoder (2D source /!1)
 -> hidden BGRA capture
 -> BGRA -> Y/UV conversion (UV chroma by default)
 -> inject into the guest Bink Y/UV resources
 -> guest's original AGC/shaders render movie + PRESS ANY BUTTON/menu UI
 -> guest display buffer
 -> sceVideoOutSubmitFlip
 -> Vulkan swapchain

The external RAD child remains fully visible ONLY until the first injected guest frame
using both Y and UV reaches QueuePresent. Then the child is region-cloaked. There is
no left/bottom rectangular hole and no black-key/neighborhood-alpha compositor after
VideoOut.

The generic descriptorless direct fallback is suppressed for these external RAD UI
Binks. This is critical: a draw with zero texture descriptors is not permission to
replace the whole guest frame with a Bink frame.

STANDALONE DEFAULT
==================
Texture injection is enabled by default for Demon's Souls UI Binks. It can be disabled
only for A/B diagnosis with SHARPEMU_DS_RAD_UI_TEXTURE_INJECTION=0.

The existing native-rad path is preserved. If a legitimately licensed Bink SDK adapter
is later built/deployed, in-process Bink remains the cleaner long-term backend because
it eliminates radvideo64.exe/window/GDI capture entirely. V3.12 is the structural
fallback for the current machine where only RAD Video Tools is available.

OFW/SDK LIMIT
=============
The available OFW audit structurally verified 643 retail SELF/ELF modules, but the
dynamic-link payload is encrypted and there are no decoded raw ELF payloads from which
to recover exact OFW import NIDs. Therefore V3.12 does not invent private Sony APIs.
It follows runtime/EBOOT evidence and the existing libSceAgc/libSceVideoOut contracts.
Observed game SDK versions: Code 9000048, Data 1000050.

FILES MODIFIED
==============
src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs
src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs
src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs

Preserved untouched: V3.10 partial/shader, HostMovieBridge, VideoOutExports, AMPR, audio.


V3.12.2 - DIAGNOSTICO DO RUNTIME MAIS RECENTE
==============================================
A V3.11 ainda deixou o Presenter aguardando o caminho de composicao final:
  [V74.0.118.7.6.3.2][RAD_MAIN_MENU_YUV_READY_NO_CLOAK]
  action=wait-for-final-guest-composite

Isso confirma que apenas imitar a geometria do logo_intro_loop no child RAD nao
resolve a arquitetura. O resultado visual (fundo preto, apenas highlight,
quadro verde ampliado) e compativel com Y/UV do Bink assumindo ownership de
apresentacao ou entrando com ordem de crominancia incorreta.

A implementacao V3.12 desta revisao corrige estruturalmente:
- RAD externo = decoder/fonte de pixels, nao superficie final;
- /!1 forca o renderer 2D capturavel para TODOS os UI Binks;
- captura BGRA alimenta os recursos Y/UV reais do guest;
- ordem de crominancia padrao do capture RAD = UV;
- descriptorless fallback nao pode promover UI Bink para fullscreen host;
- a janela RAD fica visivel somente no bootstrap;
- cloak so ocorre depois de Y + UV consumidos e QueuePresent do guest;
- composicao final continua sendo guest AGC/VideoOut/Vulkan;
- logo_intro_loop, main_menu e main_menu_ngp usam a mesma arquitetura;
- nenhum recorte left=34/bottom=13 e usado na composicao normal.

Esta revisao .12.1 tambem reconstrui o manifest depois da validacao final dos
scripts; os payloads C# continuam sendo a implementacao estrutural V3.12.


V3.12.2 - REBASE EXATO DO ESTADO ATUAL
======================================
O ultimo console mostrou um estado misto, mas conhecido e reproduzivel:

  HostApi atual   39EF8601349B2086464C1A990AFD216B19D86882AA6FE1F2C42DDCB1D8BBB9FD
  RadExternal     3CDD89DC37B145F781239F4D0136ED8A95FF2BF8B33ABCC65395A2FDAFFE4CA5
  Presenter atual 086EB8CAD532C59C8BC0EA0EBFAF1739C37DFBDDFA5CC40C2EDCAF45167C54AB

Esses hashes correspondem exatamente ao prototipo V3.12 em HostApi/Presenter
e ao RadExternal anterior. A V3.12.1 recusou esse conjunto porque aceitava apenas
os tres arquivos completamente "before" ou os tres completamente "after".
Ela parou antes de escrever no source.

A V3.12.2 aceita EXATAMENTE esse trio atual e faz uma substituicao atomica para
os tres payloads finais V3.12.1 ja validados:

  HostApi final   A091C1C2C7E209C99ECB45BD5A0E4F32524A1B8F29967DD11A1D9C40668345E1
  RadExternal     5707A299CCE9BE9D4AF55A8D5E25C7BA7C08CA59FF8C7E9BA35EC74105A385DD
  Presenter final 4C8BCE7DE87A20AF6925404C5A45817B81383BDAA73D0A838B63AA8A8CB8CAE8

O objetivo estrutural permanece:
RAD oficial = decoder/fonte BGRA; o guest recebe Y/UV e mantem a composicao real
de UI; sceVideoOutSubmitFlip/Vulkan continua sendo o unico dono da tela final.

Nao faca rollback da V3.12.1 que falhou: ela nao alterou o source.
RUN_3 cria backup dos tres arquivos atuais e restaura automaticamente se a build falhar.
