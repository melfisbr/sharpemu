SharpEmu V74.0.82.1 - Resolver Classifier Fix

Runtime optimization payload remains V74.0.82 (NonBlocking Ordered Visibility + DCC Metadata Index).
This package revision fixes the SAFE precheck classifier: the old detector counted the resolver method definition plus a normal call/reference as two methods. V74.0.82.1 counts anchored C# definitions separately from references and requires exactly one definition.

Base requerida: V74.0.81.2 aplicada.

Objetivos derivados do runtime V81.2:
- ordered_action_fence_wait chegou ao contador 8192.
- DCC_TYPED_ALIAS_REJECT chegou ao contador 16384.
- V80 DCC provenance recovery acertou apenas poucos casos.
- Vulkan DeviceLost = 0; os boundaries V81.2 devem ser preservados.

Mudancas:
1) SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY passa a default ON.
   A semantica continua exata: a acao ordenada nao executa cedo; a fila fica bloqueada
   pela timeline e o renderer atende outras filas/present ate a fence real aposentar.
   Env =0 restaura o probe legado.
2) DCC MetadataAddress index:
   TryResolveGuestImageMetadataAliasV7405632 deixa de varrer todos _guestImages e
   _guestImageVariants a cada lookup. O bucket contem apenas candidatos com a mesma
   MetadataAddress; Consider() continua validando Initialized, dimensoes, tile, formato
   e ContentGeneration.
3) Invalida o indice quando MetadataAddress de existing/retained muda.
4) Preserva V74.0.80 provenance recovery e os boundaries Vulkan da V81.2.

Execute RUN_1 -> RUN_2 -> RUN_3 -> RUN_4.
Logs/summary/result ZIP sao gravados diretamente em Patches.
