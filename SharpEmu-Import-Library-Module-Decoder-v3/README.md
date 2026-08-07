# SharpEmu — import library/module decoder v3

## Erro corrigido na v2

A v2 reconhecia os tags dinâmicos corretos, mas interpretava o campo `d_val`
incorretamente:

- tratava os 32 bits inferiores como offset da string;
- invertia major/minor do módulo;
- tratava o campo de versão como 16 bits.

No formato SCE:

- bits 0..11: índice da string na tabela dinâmica;
- bits 32..35: versão major;
- bits 40..43: versão minor do módulo;
- bits 48..63: ID da biblioteca ou módulo.

Por isso a v2 não encontrava os nomes e continuava mostrando somente
`library_token='N' module_token='O'`.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Import-Library-Module-Decoder-v3\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=import_decoded_v3.txt
```

```powershell
Select-String `
    -Path .\import_decoded_v3.txt `
    -Pattern "SCE import metadata|nid=dbOlWdppb4o" |
    Select-Object -First 8
```

O log deve mostrar contagens de bibliotecas/módulos maiores que zero e a linha
do NID deve conter `library='...' module='...'`. Caso o arquivo realmente não
possua um mapeamento para um dos tokens, aparecerá explicitamente
`'<unmapped>'`.
