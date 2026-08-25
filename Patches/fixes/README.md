# SharpEmu V76.0.2 — Shaders / Compute / Bink-Vulkan / 60 FPS

Pacote de correções para melhorar:

1. **Processamento de shaders** (opcodes F16/I64, DPP16, cache SPIR-V em disco)
2. **Instruções de kernel (compute)** (atomics LDS/buffer extras)
3. **Execução de Bink via Vulkan** (handoff em mais filmes, pacing 60 fps)
4. **Sustentar 60 fps** (frame pacer host + default Bink 60 + MAILBOX)

## Conteúdo

```
new/
  SharpEmu.ShaderCompiler.Vulkan/
    SpirvShaderDiskCache.cs          # cache de SPIR-V em disco
    Gen5SpirvTranslator.FixesV7602.cs # F16/I64 compares, DPP, LDS, atomics
  SharpEmu.Libs/VideoOut/
    HostFramePacerV7602.cs           # pacing host a 60 Hz
    VulkanVideoPresenter.FixesV7602.cs
  SharpEmu.Libs/Media/
    BinkVulkanPacingV7602.cs         # defaults 60 fps + lista de handoff
APPLY.sh                             # aplica arquivos novos + patches cirúrgicos
README.md
docs/CHANGELOG-V76.0.2.md
```

## Como aplicar

```bash
# A partir da raiz do código-fonte do SharpEmu:
./APPLY.sh /caminho/para/fonte/SharpEmu
```

Depois reconstrua:

```bash
dotnet build SharpEmu.ShaderCompiler.Vulkan
dotnet build SharpEmu.Libs
# (ou a solution completa)
```

## Variáveis de ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `SHARPEMU_BINK_TARGET_FPS` | **60** (antes 30) | FPS alvo dos filmes Bink |
| `SHARPEMU_HOST_FRAME_PACER` | on (`0` desliga) | Pacing host antes do present |
| `SHARPEMU_HOST_TARGET_FPS` | 60 | FPS do pacer host |
| `SHARPEMU_SPIRV_DISK_CACHE` | on (`0` desliga) | Cache de módulos SPIR-V |
| `SHARPEMU_SPIRV_CACHE_DIR` | `user/spirv_cache` | Diretório do cache |
| `SHARPEMU_POST_STUDIOS_FRESH_FRAME_BARRIER` | on | Handoff preto pós-logo/attract |

## O que cada correção faz

### Shaders
- Expande compares **F16** e **I64/U64** (antes caíam em `unsupported float/integer compare`).
- Expande **DPP16** (wave_shl/shr/ror 0x130–0x13F e faixa 0x1F0).
- **Cache SPIR-V em disco** entre sessões → menos stutter no 2º boot.

### Kernel / compute
- Aliases extras de atomics de buffer (`Xchg`, `CmpSwap`, …).
- Atomics **LDS 64-bit** (Add/Sub/Min/Max/And/Or/Xor/Cmpst U64/I64).

### Bink + Vulkan
- Default de Bink **30 → 60** fps.
- Handoff barrier também para `attract*.bk2`, `intro.bk2`, `opening.bk2`, logos, etc.

### 60 FPS
- `HostFramePacerV7602` dorme o residual até o próximo tick de 60 Hz antes do `QueuePresent`.
- Evita over-submit que colapsa MAILBOX/FIFO para 30/20 Hz sob carga.

## Limitações / próximo passo

- Opcodes de **image/storage image** e vários **VOP3P** ainda podem falhar em títulos além de Demon's Souls — o translator base continua a reportar `unsupported …`.
- O `VulkanGuestGpuBackend` ainda é fino; o presenter monolítico continua estático (refatoração para instância é follow-up separado).
- O cache SPIR-V está instrumentado; a integração completa no caminho `TryCompile*Shader` (lookup antes de traduzir) pode ser reforçada no próximo ciclo gravando/lendo o blob após `TryCompile` bem-sucedido.

## Verificação rápida

Após aplicar e rodar:

```
[BINK-VULKAN][V76.0.2_BINK_VULKAN_60FPS] default_target_fps=60 ...
[VULKAN][V76.0.2] host_frame_pacer + bink_handoff_expand + spirv_disk_cache ready
[FRAME-PACER][V76.0.2] enabled=1 target_fps=60.0 ...
[SPIRV-CACHE] enabled=1 hits=... misses=... stores=...
```
