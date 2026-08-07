# SharpEmu — import library/module decoder v2

## Resultado da investigação

O símbolo:

`dbOlWdppb4o#N#O`

usa o formato PS4/PS5:

`NID#library-id#module-id`

`N` e `O` não são nomes; são IDs codificados com o alfabeto SCE:

`ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-`

Portanto:

- `N` = ID 13;
- `O` = ID 14.

Os nomes reais ficam nos registros dinâmicos:

- `DT_SCE_IMPORT_LIB`;
- `DT_SCE_NEEDED_MODULE`.

O SharpEmu não interpretava esses registros, então o diagnóstico mostrava apenas
os tokens.

## Correção

- interpreta `DT_SCE_IMPORT_LIB` e `DT_SCE_EXPORT_LIB`;
- interpreta `DT_SCE_NEEDED_MODULE` e `DT_SCE_MODULE_INFO`;
- decodifica os IDs com o mesmo algoritmo usado pelo linker;
- associa cada símbolo ao nome real da biblioteca e do módulo;
- preserva o sampling de imports não resolvidos;
- preserva as correções anteriores do import dispatcher.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Import-Library-Module-Decoder-v2\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=import_decoded.txt
```

```powershell
Select-String `
    -Path .\import_decoded.txt `
    -SimpleMatch "nid=dbOlWdppb4o" |
    Select-Object -First 1
```

A linha deve mostrar:

`library='nome real' module='nome real'`

Com esses nomes será possível localizar e implementar a função correta sem
inventar uma assinatura.
