# SharpEmu V76.0.11 — Parallel Shader Compile + SPIR-V Prewarm SAFE

Requer V76.0.10.2 validada. Mantem a geracao de cache `V76.0.10-r1`, pois o SPIR-V emitido nao muda nesta etapa.

Implementa:
- prewarm oportunista, em background, dos SPIR-V persistidos mais recentes;
- limite padrao de 256 entradas e 64 MiB (`SHARPEMU_SPIRV_PREWARM_MAX`, `SHARPEMU_SPIRV_PREWARM_MB`);
- compilacao paralela do par VS+PS apenas no backend Vulkan quando o draw ainda nao esta no graphics shader cache;
- fallback sequencial preservado e opt-out `SHARPEMU_VK_PARALLEL_STAGE_COMPILE=0`;
- nenhum placeholder shader e nenhuma alteracao de semantica do translator;
- pipeline cache Vulkan persistente existente no presenter e preservado sem duplicacao.

O pacote cria backup antes da primeira mutacao e restaura o baseline em qualquer falha de apply/build.
