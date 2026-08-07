# SharpEmu — import provenance and unresolved-log sampling

## Resultado da revisão

`dbOlWdppb4o` não é criado a partir de uma chamada indireta durante a execução.
O stub é criado pelo `SelfLoader` a partir de um símbolo global/weak indefinido
presente na tabela dinâmica ELF.

O problema de diagnóstico era:

1. `ExtractNid` removia tudo após `#`, descartando os tokens de biblioteca e
   módulo do símbolo original;
2. o dispatcher imprimia uma linha completa em toda chamada não resolvida;
3. um NID quente gerou 21.384 linhas e passou a alterar desempenho e timing;
4. sem o símbolo ELF completo não era possível saber a qual biblioteca o NID
   desconhecido pertence.

## Correções

- preserva o símbolo ELF completo por NID;
- mostra `symbol`, `library_token` e `module_token` na primeira chamada;
- limita o log a quatro primeiras chamadas e potências de dois;
- permite log completo com `SHARPEMU_LOG_UNRESOLVED_IMPORTS=all`;
- limpa os metadados a cada nova sessão;
- mantém o retorno atual `ORBIS_GEN2_ERROR_NOT_FOUND`;
- preserva a correção anterior que remove unlocks pthread do caminho leaf.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Import-Provenance-And-Sampling-Fix\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
Remove-Item Env:\SHARPEMU_LOG_UNRESOLVED_IMPORTS -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=import_provenance.txt
```

Extraia a linha:

```powershell
Select-String .\import_provenance.txt -SimpleMatch "nid=dbOlWdppb4o" |
    Select-Object -First 4
```

A linha agora deve conter algo como:

```text
symbol='dbOlWdppb4o#...#...' library_token='...' module_token='...'
```

Esses tokens permitem localizar a biblioteca e implementar a função correta,
sem inventar um stub baseado apenas nos registradores.
