# SharpEmu V74.0.86 — Resident Texture Retention + Live Diagnostic SAFE

Base cumulativa requerida: V74.0.81.2 + V74.0.82/82.1 + V74.0.84 + V74.0.85.

Objetivo desta revisão: atacar a retenção/cópia repetida de texturas grandes observada no Demon’s Souls depois que a V84 eliminou o CAPACITY_YIELD e a V85 elevou o pico para ~2.5 FPS.

Mudanças:

1. Aumenta o default do cache Vulkan standalone de 768 MiB para 3072 MiB. O override `SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB` continua válido; usar 768 restaura o comportamento anterior.
2. Aumenta o default do bridge de snapshot grande de 2 s para 10 s. `SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS=2000` restaura o default anterior.
3. Quando o presenter já confirma a identidade da textura em cache, remove imediatamente snapshots CPU grandes do cache bridge (incluindo arrays 320 MiB). `SHARPEMU_RESIDENT_CPU_BRIDGE_RELEASE=0` desliga somente esta otimização.
4. Mantém os boundaries Vulkan V81.2, non-blocking visibility/DCC index V82, adaptive compute V84 e PM4/RELEASE queue V85.
5. RUN_4 passa a gravar o runtime log AO VIVO com Tee-Object. Mesmo se o processo for fechado/crashar, o .log já existe em `Patches`.

Não aumenta o hard ceiling de submissions e não remove fences Vulkan.

## Ordem

RUN_1_VALIDATE_PACKAGE.cmd → RUN_2_PRECHECK.cmd → RUN_3_APPLY_BUILD.cmd → RUN_4_TEST_DIAGNOSTIC.cmd

Todos os logs/resultados são gravados em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`.
