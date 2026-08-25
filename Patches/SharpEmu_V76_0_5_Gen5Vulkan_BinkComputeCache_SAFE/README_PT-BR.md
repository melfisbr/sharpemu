# SharpEmu V76.0.5 — Gen5/Vulkan + Bink Compute Cache SAFE

Baseline deste pacote: `src(20260824-141742).zip` enviado em 24/08/2026.

## Escopo

- fecha lowerings Gen5/Vulkan concretamente ausentes no baseline:
  - `DS_SWIZZLE_B32` (QUAD_PERM + BITMASK_PERM no domínio wave32 host);
  - `S_BITCMP0_B64` / `S_BITCMP1_B64`;
  - `V_CMPX_F_I32`, `V_CMPX_F_U32`, `V_CMPX_T_I32`, `V_CMPX_T_U32`;
  - `V_CVT_PK_U16_U32` com saturação em `0xFFFF`;
  - `V_DOT2C_F32_F16` acumulando no `VDST` anterior.
- fortalece `S_BARRIER` de compute para LDS + uniform/storage buffer + image memory.
- adiciona cache de SPIR-V final por SHA-256, em memória e disco, com validação estrutural antes de reutilizar.
- deduplica misses simultâneos de tradução por chave sem retornar shader placeholder.
- adiciona profiling opt-in por compute dispatch no presenter.
- adiciona telemetria opt-in de cadência de present e buckets de frame time.
- ajusta defaults de catch-up Bink legado de 8/6 ms para 12/10 ms.

## O que este pacote NÃO faz

- não habilita o soft-fail da V76.0.4 que zera destinos de opcode não suportado;
- não implementa `S_SETPC_B64` / `S_SWAPPC_B64` por aproximação; eles exigem suporte correto a controle de fluxo indireto;
- não transforma a interface síncrona `TryCompile*` em placeholder assíncrono. Em vez disso, elimina recompilações repetidas e misses concorrentes com cache seguro;
- não toca IME, DCC, resident bridge, DLSS/FSR, RAD ownership ou host decoder Bink.

## Variáveis de diagnóstico V76.0.5

- `SHARPEMU_SPIRV_RESULT_CACHE=0` desliga cache de resultado.
- `SHARPEMU_SPIRV_DISK_CACHE=0` mantém apenas cache em memória.
- `SHARPEMU_SPIRV_CACHE_DIR=<pasta>` define a pasta do cache.
- `SHARPEMU_TRACE_SPIRV_CACHE=1` mostra hits.
- `SHARPEMU_TRACE_COMPUTE_DISPATCH_TIMING=1` habilita timing host por dispatch.
- `SHARPEMU_TRACE_COMPUTE_DISPATCH_THRESHOLD_MS=5` define limiar do log.
- `SHARPEMU_TRACE_PRESENT_CADENCE=1` mostra `dt_ms`/EMA de FPS.
- `SHARPEMU_TRACE_FRAME_STATS=1` mostra buckets a cada 300 presents.

## Segurança do pacote

`RUN_2_PRECHECK.cmd` aceita somente o baseline exato enviado ou arquivos que já sejam exatamente o payload V76.0.5. Hash desconhecido aborta. `RUN_3_APPLY_BUILD.cmd` faz backup dos arquivos substituídos em `Patches`, aplica, valida hashes e compila `SharpEmu.CLI` Release/win-x64. Se a build falhar, restaura automaticamente o estado anterior e remove helpers novos adicionados pelo pacote.
