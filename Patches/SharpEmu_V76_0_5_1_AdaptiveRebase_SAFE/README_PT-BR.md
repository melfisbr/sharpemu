# SharpEmu V76.0.5.1 — Gen5/Vulkan Adaptive Rebase SAFE

Este pacote corrige a recusa da V76.0.5 no source local observado em 24/08/2026 11:51 -03:00.

## O que mudou em relação à V76.0.5

- `VulkanGuestGpuBackend.cs` ainda é substituído integralmente, mas somente quando o hash é o baseline exato já confirmado.
- `VulkanVideoPresenter.cs`, `Gen5SpirvTranslator.cs` e `Gen5SpirvTranslator.Alu.cs` **não são substituídos**. São editados cirurgicamente por âncoras.
- O precheck reconhece os hashes divergentes mostrados no log do usuário e continua bloqueando qualquer outro estado não conhecido.
- Há backup antes do primeiro write e rollback automático em falha de patch, validação ou build.
- Se `Gen5SpirvTranslator.SoftFailV7604.cs` existir dentro de `src`, o soft-fail deixa de ser default-on e passa a exigir `SHARPEMU_SHADER_SOFT_FAIL=1`.
- Se o helper de cache V76.0.3 existir sem a classe `SpirvShaderDiskCache`, as duas referências quebradas são neutralizadas; o cache V76.0.5 passa a ser o caminho efetivo.

## Correções funcionais

- `DS_SWIZZLE_B32`.
- `S_BITCMP0_B64` / `S_BITCMP1_B64`.
- `VCMPX_F/T_I32` e `VCMPX_F/T_U32` constantes.
- `V_CVT_PK_U16_U32` com saturação.
- `V_DOT2C_F32_F16` acumulando o `VDST` anterior.
- `S_BARRIER` compute com AcquireRelease + Uniform + Workgroup + Image memory.
- cache SPIR-V em memória/disco por fingerprint completo.
- validação estrutural antes de reutilizar cache persistido.
- telemetria de compute/present opt-in.
- Bink catch-up 12 frames / 10 ms quando as âncoras ainda correspondem.

## Segurança

Não execute RUN_3 se RUN_2 falhar. RUN_3 também repete a validação e recusará source divergente.
