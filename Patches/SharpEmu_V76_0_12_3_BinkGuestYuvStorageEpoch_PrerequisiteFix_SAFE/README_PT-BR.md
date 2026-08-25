# SharpEmu V76.0.12.3 — Bink guest-owned YUV/storage epoch PrerequisiteFix

BuildFix/prerequisite fix cumulativo sobre a V76.0.11.1.

A tentativa V76.0.12.2 foi bloqueada antes do apply porque o gate exigia o hash integral `09b7...` de `VulkanShaderBinaryCacheV7605.cs`, enquanto o source validado apresentava `4c40...`. Como a V76.0.11.1 usa aplicação adaptativa/carry-forward, essa exigência era rígida demais.

A V76.0.12.3 valida a funcionalidade instalada em vez do arquivo inteiro: geração de cache V76.0.10-r1, prewarm V76.0.11, persistência fora do caminho crítico e compilação VS+PS paralela. O payload Bink/YUV continua o mesmo da V76.0.12.2, incluindo namespace `SharpEmu.Libs.Gpu` para `GuestDrawTexture`.

O pacote faz backup antes da primeira escrita e rollback em qualquer falha posterior. Logs e ZIPs de resultado são gravados em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`.
