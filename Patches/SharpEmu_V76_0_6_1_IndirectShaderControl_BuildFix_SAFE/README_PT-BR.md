# SharpEmu V76.0.6.1 — Indirect Shader Control BuildFix SAFE

Base obrigatória: V76.0.5.1 aplicada e verificada.

Esta versão substitui a V76.0.6 que falhou na compilação do `Gen5ShaderScalarEvaluator.cs`. O rollback da V76.0.6 deve ter restaurado a V76.0.5.1 antes deste pacote.

Correções do BuildFix:

- elimina CS0165 inicializando `targetAddress` antes do short-circuit `&&`;
- elimina CS0136 renomeando o PC do alvo indireto para `indirectTargetPc`, sem colidir com o `targetPc` do S_BRANCH no escopo externo;
- mantém a semântica original de S_SETPC_B64/S_SWAPPC_B64 e S_ASHR_I64;
- mantém backup e rollback automático em qualquer falha após o primeiro write.

A etapa continua implementando:

- S_SETPC_B64 com endereço absoluto de SGPR;
- S_SWAPPC_B64 com captura do alvo antes da escrita do retorno;
- granularidade CFG por instrução apenas em shaders com indirect-PC;
- scalar evaluator seguindo alvos indiretos estaticamente resolvíveis;
- S_ASHR_I64 no evaluator.

Não toca RAD/Bink host decoder, IME, DCC, presenter, scheduler Vulkan ou detile.

IMPORTANTE: execute RUN_4 apenas se RUN_3 terminar com BUILD PASSED. Se RUN_3 falhar, o rollback remove os marcadores e RUN_4 naturalmente falhará.
