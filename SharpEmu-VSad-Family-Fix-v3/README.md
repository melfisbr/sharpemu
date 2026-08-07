# SharpEmu — VSAD Family Fix v3

Esta versão corrige o pacote v2, que por engano foi criado sem a pasta
`src` e, portanto, não continha os dois arquivos C# que o script tentava
copiar.

## Conteúdo confirmado

- `src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs`
- `src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.Alu.cs`
- `apply_and_validate.ps1`
- `VALIDATION.md`

## Instruções implementadas

- `VSadU8`
- `VSadHiU8`
- `VSadU16`
- `VSadU32`

## Aplicação

Extraia esta pasta na raiz do SharpEmu e execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-VSad-Family-Fix-v3\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

O script:

1. verifica a presença dos arquivos dentro do pacote;
2. cria backup dos arquivos atuais;
3. aplica a correção;
4. confirma `case "VSadU32":` no fonte;
5. encerra processos SharpEmu antigos;
6. limpa e reconstrói o CLI para `win-x64`;
7. confirma as DLLs dentro da pasta runtime;
8. executa os testes do ShaderCompiler disponíveis.
