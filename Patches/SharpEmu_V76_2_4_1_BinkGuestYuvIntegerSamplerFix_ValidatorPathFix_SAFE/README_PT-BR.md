# SharpEmu V76.2.4.1 — BinkGuestYuvIntegerSamplerFix ValidatorPathFix SAFE

Correção **somente do instalador/validador** do pacote existente:

`SharpEmu_V76_2_4_BinkGuestYuvIntegerSamplerFix_SAFE`

## Erro corrigido

`Test-Path : Caracteres inválidos no caminho` em `scripts\validate.ps1` ao resolver `manifest.sha256`.

O fix remove a dependência do resultado de `Get-PackageRoot` para o caminho do manifest no validator e usa diretamente o diretório físico de `validate.ps1` via `$PSScriptRoot`.

## Segurança

- Não altera `src`.
- Não aplica o payload funcional V76.2.4.
- Faz backup de `scripts\validate.ps1` e `manifest.sha256` antes da alteração.
- Atualiza no manifest apenas o SHA-256 do `scripts\validate.ps1` modificado.
- Roda novamente o `RUN_1_VALIDATE_PACKAGE.cmd` original ao final.

Depois que este overlay terminar com `ORIGINAL V76.2.4 RUN_1 PASSED`, continue com os RUN_2/RUN_3/RUN_4 do pacote V76.2.4 original.
