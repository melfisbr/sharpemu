# SharpEmu V76.2.4.6 — Split-Path Complete Guard SAFE

BuildFix do pacote `SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE`.

A V76.2.4.5 eliminou uma ocorrência textual suspeita, mas o runner continuou falhando porque outra chamada real de `Split-Path` recebeu argumento nulo em runtime. Este pacote usa o AST do PowerShell para localizar **todos os comandos Split-Path reais** dos scripts do pacote-alvo, troca apenas o command-name por um wrapper seguro, recalcula o `manifest.sha256` do pacote-alvo e reexecuta o runner original.

O wrapper:
- ignora argumentos posicionais `$null` espúrios;
- retorna `$null` quando não existe path utilizável;
- delega chamadas válidas para `Microsoft.PowerShell.Management\Split-Path`;
- não modifica o source C# do SharpEmu diretamente.

Se o runner alvo falhar, scripts e manifest do pacote-alvo são restaurados automaticamente.
