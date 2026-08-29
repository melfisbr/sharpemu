SharpEmu V76.3.21.4.1.1 - Rollback Yield Guard Fix / Normal Run Recovery (DEV SAFE)

Objetivo:
Reverter integralmente a mudanca comportamental V76.3.21.4 que introduziu Thread.Yield()
no hot path de construcao de PM4 e antecipou o stall do boot.

Evidencia do teste V21.4:
- main loop foi atingido;
- Async AGC chegou somente a 512;
- graphics submission chegou a 700;
- direct scanout chegou a 24;
- GPU drenou sem DeviceLost/AccessViolation/Fatal;
- o diagnostico encerrou a janela por timeout, nao por crash do guest.

Mudanca de runtime:
- REMOVE o bloco V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN/END;
- REMOVE NoteAgcBuilderV763214 / NoteAgcDriverSubmitV763214;
- REMOVE completamente System.Threading.Thread.Yield() introduzido pela V21.4;
- preserva V21.3.1.1.2 Sync512, V21.3, V21.2, Async AGC, dual queue, hazards,
  WAIT_REG_MEM, WRITE_DATA, RELEASE_MEM, Bink natural request e caches;
- nao adiciona nova heuristica de scheduling.

A/B de seguranca:
O RUN_4 tambem define SHARPEMU_V763214_DISABLE=1. Assim, mesmo se houver qualquer
residuo acidental da V21.4, o comportamento fica desativado durante o diagnostico.

Diagnostico:
- low-overhead;
- usa os contadores existentes e confiaveis [AGC_ASYNC_CP];
- NAO fecha o SharpEmu ao atingir o limite de coleta;
- se ainda estiver rodando apos a coleta, gera snapshots dos logs e deixa o processo aberto.

CORRECAO V21.4.1.1:
O AgcExports.cs anterior a V21.4 ja possuia chamadas Thread.Yield() legitimas.
A V21.4.1 falhava porque exigia zero ocorrencias apos o rollback.

Agora o RUN_3 contabiliza:
- yield_pre: total antes do rollback;
- yield_v214_block: total dentro do bloco V21.4;
- yield_post: total apos o rollback.

Contrato:
yield_post == yield_pre - yield_v214_block

Isso preserva Yield pre-existente e remove somente o que pertence a V21.4.
