# SharpEmu V74.0.86.3 — Resident Texture Retention + Presenter Mark Bridge Release SAFE

Base cumulativa requerida: V74.0.81.2 + V74.0.82/82.1 + V74.0.84 + V74.0.85.

Esta revisão corrige as falhas de instalador V74.0.86/.86.1/.86.2 sem depender mais do layout de `TryCreateGuestDrawTexture`, `IsTextureContentCached`, `NoteSampledAddress` ou do construtor de `GuestDrawTexture`.

## Mudança estrutural V86.3

O ponto de liberação agora é `VulkanVideoPresenter.MarkTextureContentCached(identity, texture)`. Depois de `_cachedTextureIdentities.TryAdd(identity, 0)`, o presenter chama:

`AgcExports.ReleaseResidentCpuBridgeSnapshotsV740863(identity.Address)`

O helper remove apenas referências dos caches CPU `_v7405LargeTextureSnapshotCache` e `_v74064LargeArraySnapshotCache` para aquele endereço. Ele não altera o `GuestDrawTexture` já em uso, não remove o VkImage, não antecipa WRITE_DATA/RELEASE_MEM e não modifica ordem/fences Vulkan.

## Otimizações preservadas

1. Cache Vulkan standalone default de 3072 MiB (`SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB=768` restaura o comportamento anterior).
2. Large texture snapshot TTL default de 10 s (`SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS=2000` restaura o comportamento anterior).
3. CPU bridge retirement default ON (`SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE=0` desliga somente esta parte).
4. V85 aggressive PM4/payload/release queue, V84 adaptive compute, V82 non-blocking visibility e boundaries Vulkan V81.2 são preservados.
5. RUN_4 cria o runtime log antes de iniciar o emulador e usa `Tee-Object`, mantendo log incremental em `Patches`.

Nenhum SHA rígido é usado. A escrita do source só ocorre depois dos contratos pós-transform. Build failure restaura automaticamente o backup.

## Ordem

RUN_1_VALIDATE_PACKAGE.cmd → RUN_2_PRECHECK.cmd → RUN_3_APPLY_BUILD.cmd → RUN_4_TEST_DIAGNOSTIC.cmd

Logs, summary e ZIP ficam em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`.
