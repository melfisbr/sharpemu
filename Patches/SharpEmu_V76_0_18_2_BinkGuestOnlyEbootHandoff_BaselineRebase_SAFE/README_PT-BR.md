# SharpEmu V76.0.18.2 — Bink Guest-Only Eboot Handoff Baseline Rebase

BuildFix/PrerequisiteFix sobre a V76.0.18 funcional. Não muda a lógica de runtime: `.bk2` permanece hard guest-only, FFmpeg/NihAV/RAD host ficam bloqueados para Bink2 e o fechamento guest segue diretamente para o fluxo do eboot sem black-frame/host wait.

Este `.2` corrige apenas o precheck para o baseline real `src(20260825-003946).zip`, incluindo o helper YUV V76.0.12 evoluído (SHA-256 `58b1ad...`). Todos os helpers V76 anteriores são validados por contratos semânticos fortes.
