# SharpEmu V74.0.81.2 - Semantic Boundary Repair SAFE

Correção do instalador e da regressão Vulkan DeviceLost observada após V74.0.81.

Esta revisão é aplicada por cima de V74.0.81. Ela NÃO depende do texto exato do bloco
que fez V74.0.81.1 abortar. O transform fica limitado ao corpo de
ExecuteComputeDispatchCore e restaura semanticamente dois boundaries obrigatórios:

1. FlushBatchedGuestCommands() logo após a abertura de ExecuteComputeDispatchCore.
2. FlushBatchedGuestCommands() logo após CreateComputeDispatchResources(work).

Os blocos V74.0.81 antigos são preservados. Isso reduz o risco de apagar helpers ou
correções acumuladas; eles deixam de remover os boundaries porque a V81.2 insere os
fences independentemente deles.

Também reduz o burst padrão 8 -> 2, preserva a separação queued/in-flight da V81 e
preserva DCC provenance recovery V74.0.80 quando presente.

O RUN_4 grava os caminhos de RuntimeLog/Summary/ResultZip antes de iniciar o jogo e
usa contadores compatíveis com Windows PowerShell 5.1.

Emergency A/B:
  $env:SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST="1"

Execute na ordem RUN_1 -> RUN_2 -> RUN_3 -> RUN_4.
