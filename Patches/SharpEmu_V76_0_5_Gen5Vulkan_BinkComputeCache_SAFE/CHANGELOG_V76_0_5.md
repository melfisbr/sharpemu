# V76.0.5

## Shader/ISA

- Implementado `DS_SWIZZLE_B32` usando `GroupNonUniformShuffle` e índice host 0..31.
- Implementados `S_BITCMP0_B64` e `S_BITCMP1_B64`.
- Corrigidos compares constantes `VCMPX` signed/unsigned true/false.
- Implementado `V_CVT_PK_U16_U32` saturado.
- Implementado `V_DOT2C_F32_F16` com leitura do `VDST` anterior como acumulador.
- `S_BARRIER` compute agora publica Workgroup/Uniform/Image memory sob AcquireRelease.

## Cache/pipeline

- Novo `VulkanShaderBinaryCacheV7605`.
- Hash cobre programa completo, estado escalar avaliado, shape de resources, opções de compilação e flags `SHARPEMU_*`.
- Cache persiste somente SPIR-V validado; metadata dinâmica de dispatch não é cacheada.
- Escrita em disco atômica e limite de 32 MiB por módulo.

## Compute / present

- Timing host opt-in por dispatch com shader address, groups/base/local/wave e resource counts.
- Cadência de present opt-in com EMA e buckets `>=60`, `30..60`, `<30` por frame time.
- Catch-up Bink legado default: 12 frames / 10 ms.
