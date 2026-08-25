# SharpEmu V76.0.7 — Typed Buffer / MIMG Coverage SAFE

Baseline obrigatório: **V76.0.6.1 com BUILD + SOURCE VERIFY concluídos**.

O pacote altera exatamente quatro arquivos do shader compiler e exige os hashes exatos da V76.0.6.1. Se houver divergência, o PRECHECK/APPLY recusam a operação. Antes do primeiro write é gerado backup ZIP em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`. Qualquer falha de build restaura os quatro arquivos anteriores.

Esta etapa corrige a base de MTBUF GFX10: opcode de 4 bits, D16 packed, FORMAT da instrução e typed-load conversion. Também amplia os SAMPLE MIMG que podem ser expressos corretamente pelo lowering atual.

**Importante:** typed stores são apenas decodificados nesta versão e falham explicitamente no translator. A V76.0.8 implementará a conversão/packing de stores. Os SAMPLE `*_Cl` dependentes de MinLod também não são mascarados.

Execute `RUN_4_VERIFY_SOURCE.cmd` somente se `RUN_3_APPLY_BUILD.cmd` terminar em `BUILD PASSED`.
