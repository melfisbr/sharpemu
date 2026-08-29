SharpEmu V76.3.21.4 - Normal Run AGC Publish Fairness (DEV SAFE)

Objetivo:
Corrigir a diferenca de timing observada entre o RUN_4 pesado da V21.3.1.1.2 e a execucao normal. O diagnostico pesado chegou ao PS Studios; o modo normal drenou a GPU e parou antes do mesmo marco.

Mudanca unica de runtime:
- preserva Sync512 autoritativo da V21.3.1.1.2;
- nao altera Vulkan, WAIT_REG_MEM, WRITE_DATA, RELEASE_MEM ou ordem dos command buffers;
- conta PM4 builder ops reais (WRITE_DATA / RELEASE_MEM) e submits reais DCB/ACB;
- se o worker construir >=512 desses pacotes por >=4ms sem um submit concluido, executa Thread.Yield() somente a cada 128 builder ops;
- A/B: SHARPEMU_V763214_DISABLE=1 desliga completamente o comportamento.

O RUN_4 e deliberadamente LOW-OVERHEAD: os probes de geometry/thread snapshots ficam OFF para nao mascarar a race observada.
