# V76.0.10.2

- Corrige falso `Anchor invalida ... vulkan-sopp-clause-depctr occurrences=0`.
- Precheck SOPP agora retorna `Applied` ou `ReadySemanticInsert`.
- Vulkan: insercao por token unico `"SWaitcnt" or`, com validacao de `SNop`, `SInstPrefetch` e `STtraceData`.
- Metal: insercao por token unico `case "SWaitcnt":`, com validacao de contexto.
- Payload `VulkanShaderBinaryCacheV7605.cs` permanece byte-identico ao V76.0.10.1.
- Rollback mantido.
