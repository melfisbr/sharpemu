# SharpEmu V76.2.4.5 — Bink Guest YUV Integer Sampler / Split-Path Null BuildFix SAFE

Correção **somente dos scripts do pacote V76.2.4.1**. Não altera diretamente o source do SharpEmu.

Falha tratada:

`Split-Path : Não é possível localizar um parâmetro posicional que aceite o argumento '$null'.`

O V76.2.4.5:

1. localiza `SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE` em `Patches`;
2. faz backup de `scripts\patch_target.ps1` e `manifest.sha256` (se existir);
3. substitui a inicialização de `$Patches` por uma derivação determinística via `System.IO.Directory`, sem `Split-Path`;
4. remove apenas um argumento terminal `$null`/`'$null'` de chamadas `Split-Path`, caso exista;
5. atualiza o hash de `scripts/patch_target.ps1` no manifest do pacote-alvo;
6. valida a sintaxe PowerShell do script corrigido;
7. reexecuta `RUN_2_PATCH_AND_REVALIDATE_V76_2_4.cmd`;
8. restaura os scripts/manifest do pacote-alvo se o runner falhar.

O source V76.2.4 já reportado como `Applied` não é revertido por este BuildFix.
