# SharpEmu V74.0.86.4 — Resident Texture Retention + Semicolon Anchor + Live Diagnostic SAFE

Base cumulativa requerida: V74.0.81.2 + V74.0.82/82.1 + V74.0.84 + V74.0.85.

Esta revisão corrige exclusivamente a mecânica de instalação das tentativas V74.0.86/.86.1/.86.2/.86.3. O ponto runtime continua sendo `VulkanVideoPresenter.MarkTextureContentCached(identity, texture)`, mas a inserção não depende mais de CRLF/LF, `NoteSampledAddress`, `TryCreateGuestDrawTexture` ou de um EOL após o registro do cache.

## Inserção V86.4

O instalador localiza exatamente uma instrução:

`_cachedTextureIdentities.TryAdd(identity, 0);`

Depois usa o `;` da própria instrução como boundary estrutural e insere:

`AgcExports.ReleaseResidentCpuBridgeSnapshotsV740864(identity.Address);`

O helper remove apenas referências dos caches CPU `_v7405LargeTextureSnapshotCache` e `_v74064LargeArraySnapshotCache` para o endereço já marcado como residente. Não remove VkImage, não antecipa WRITE_DATA/RELEASE_MEM e não altera os boundaries Vulkan V81.2.

## Otimizações

- cache Vulkan standalone default: 3072 MiB (`SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB=768` para A/B);
- large snapshot TTL default: 10 s (`SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS=2000` para A/B);
- bridge retirement default ON (`SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE=0` desliga);
- V85 aggressive PM4/payload/release queue, V84 adaptive compute e V82 non-blocking visibility preservados;
- RUN_4 cria o `.log` antes de abrir o SharpEmu e usa `Tee-Object`, mantendo gravação incremental em `Patches`.

Sem SHA rígido. Os sources só são escritos depois dos contratos pós-transform. Falha de build restaura automaticamente o backup.

## Ordem

RUN_1_VALIDATE_PACKAGE.cmd → RUN_2_PRECHECK.cmd → RUN_3_APPLY_BUILD.cmd → RUN_4_TEST_DIAGNOSTIC.cmd
