# SharpEmu — import token peer correlation v4

## Por que esta revisão existe

O teste anterior retornou:

- `libraries=0`
- `modules=0`
- símbolo `dbOlWdppb4o#N#O`

Portanto o arquivo carregado não expôs os registros dinâmicos necessários para
transformar diretamente `N` e `O` em nomes.

Esta revisão usa outro método seguro: correlaciona o import desconhecido com
todos os outros imports do mesmo arquivo que possuem o mesmo sufixo `#N#O`.
Para os NIDs irmãos que já existem no Aerolib, o log mostra seus nomes.

Isso permite identificar a família/biblioteca do NID sem inventar uma
assinatura e sem depender de `DT_SCE_IMPORT_LIB`.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Import-Token-Peer-Correlation-v4\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=import_peer_correlation.txt
```

```powershell
Select-String `
    -Path .\import_peer_correlation.txt `
    -SimpleMatch "nid=dbOlWdppb4o" |
    Select-Object -First 1
```

Procure no final da linha:

- `token_peer_nids=...`
- `known_token_peers=...`
- `peer_names='NID=nome;NID=nome;...'`
