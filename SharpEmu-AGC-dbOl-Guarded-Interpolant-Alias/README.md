# SharpEmu — guarded AGC alias for dbOlWdppb4o

## Resultado da revisão

A correlação por token comprovou que `dbOlWdppb4o#N#O` pertence à mesma
biblioteca AGC de 209 imports; 197 deles são nomes `sceAgc*` conhecidos.

A inspeção dos argumentos mostrou este formato estável:

- RDI: bloco de saída na pilha;
- RSI: objeto de shader de exportação/geometria;
- RDX: objeto de pixel shader ou zero.

Esse formato coincide com o helper já existente
`CreateInterpolantMapping`. Os endereços também aparecem próximos dos shaders
ES/PS usados nos draws que compõem o frame.

O nome privado exato ainda não foi recuperado. Por isso esta correção não
renomeia o NID como API pública: registra um alias sintético e só delega quando
os tipos dos dois objetos de shader são compatíveis.

## Segurança da correção

O alias só executa quando:

- RDI e RSI são diferentes de zero;
- o objeto RSI tem tipo GS/export-stage;
- RDX é zero ou possui tipo Pixel Shader.

Caso o formato não corresponda, retorna `NOT_FOUND` e não escreve o bloco de
mapeamento.

É possível desativar o alias:

```powershell
$env:SHARPEMU_DISABLE_AGC_DBOL_INTERPOLANT_ALIAS = "1"
```

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-AGC-dbOl-Guarded-Interpolant-Alias\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste principal

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
Remove-Item Env:\SHARPEMU_DISABLE_AGC_DBOL_INTERPOLANT_ALIAS `
    -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=agc_dbol_alias.txt
```

Verifique se o NID deixou de aparecer como unresolved:

```powershell
Select-String .\agc_dbol_alias.txt -SimpleMatch "dbOlWdppb4o"
```

Para confirmar a decisão do guard, execute uma vez com AGC trace:

```powershell
$env:SHARPEMU_LOG_AGC = "1"

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=agc_dbol_guard.txt

Select-String .\agc_dbol_guard.txt -SimpleMatch "agc.unknown_dbol" |
    Select-Object -First 20
```
