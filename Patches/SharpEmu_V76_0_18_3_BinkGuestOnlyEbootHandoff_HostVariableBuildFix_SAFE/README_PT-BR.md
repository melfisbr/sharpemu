# SharpEmu V76.0.18.3 — Bink Guest-Only Eboot Handoff Host Variable BuildFix

BuildFix/PrerequisiteFix sobre a V76.0.18 funcional. Não muda a lógica de runtime: `.bk2` permanece hard guest-only, FFmpeg/NihAV/RAD host ficam bloqueados para Bink2 e o fechamento guest segue diretamente para o fluxo do eboot sem black-frame/host wait.

Este `.2` corrige apenas o precheck para o baseline real `src(20260825-003946).zip`, incluindo o helper YUV V76.0.12 evoluído (SHA-256 `58b1ad...`). Todos os helpers V76 anteriores são validados por contratos semânticos fortes.


## BuildFix V76.0.18.3

Este pacote preserva byte a byte o payload/patchdata funcional da V76.0.18.2.
A única correção de execução é no verificador PowerShell: `$host` foi renomeado
para `$hostText`, pois PowerShell trata `$host` e a variável automática somente
leitura `$Host` como o mesmo identificador. O RUN_1 agora também bloqueia uma
futura reintrodução dessa atribuição.
