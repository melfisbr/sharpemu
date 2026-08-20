# SharpEmu V74.0.86.1 — Resident Texture Retention + Semantic Cache-Hit Fix SAFE

Base cumulativa requerida: V74.0.81.2 + V74.0.82/82.1 + V74.0.84 + V74.0.85.

Esta revisão corrige exclusivamente a falha do instalador V74.0.86 `texture cache-hit body anchor missing`. O source do usuário não é alterado pela V86 quando essa falha ocorre.

Mudanças runtime preservadas da V86:

1. Cache Vulkan standalone default de 3072 MiB (`SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB=768` restaura o comportamento anterior).
2. Janela do snapshot grande default de 10 s (`SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS=2000` restaura o comportamento anterior).
3. Em cache-hit de textura >= 8 MiB, remove o snapshot CPU producer-side por endereço depois que o presenter confirmou conteúdo residente. `SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE=0` desliga somente esta parte.
4. Mantém boundaries Vulkan V81.2 e as otimizações V82/V84/V85.
5. RUN_4 grava o runtime log ao vivo em `Patches` com Tee-Object.

## Correção V86.1

O instalador não procura mais a sequência textual `{` + `NoteSampledAddress(...)`. Ele localiza a chamada `GuestGpu.Current.IsTextureContentCached(...)`, encontra o `if` C# que semanticamente contém essa chamada por parênteses balanceados, valida que o corpo contém `NoteSampledAddress` e `new GuestDrawTexture`, e insere a liberação imediatamente após a abertura do corpo.

Nenhum SHA rígido é exigido. O arquivo só é escrito depois de todos os contratos pós-transform serem validados. Falha de build restaura automaticamente o backup.

## Ordem

RUN_1_VALIDATE_PACKAGE.cmd → RUN_2_PRECHECK.cmd → RUN_3_APPLY_BUILD.cmd → RUN_4_TEST_DIAGNOSTIC.cmd

Logs, summary e ZIP de resultado ficam em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`.
