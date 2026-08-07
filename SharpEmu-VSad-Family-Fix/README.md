# SharpEmu VSAD family fix

## O que o log provou

A correção anterior permitiu que o pipeline avançasse até o ShaderCompiler.
Agora o bloqueio é explícito:

`VSadU32: unsupported vector opcode VSadU32`

## Arquivos

Substitua:

- `src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs`
- `src\SharpEmu.ShaderCompiler.Metal\Gen5MslTranslator.Alu.cs`

## Instruções implementadas

- `VSadU8`
- `VSadHiU8`
- `VSadU16`
- `VSadU32`

A semântica segue a documentação AMD:

- `VSadU32`: `abs_unsigned(src0 - src1) + src2`
- `VSadU16`: soma das diferenças absolutas dos dois words + src2
- `VSadU8`: soma das diferenças absolutas dos quatro bytes + src2
- `VSadHiU8`: resultado de `VSadU8(src0, src1, 0) << 16`, somado a src2

As operações usam aritmética uint de 32 bits, portanto overflow é modular.

## Aplicação

Na raiz do repositório:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\SharpEmu-VSad-Family-Fix\apply_and_validate.ps1 -RepositoryRoot $PWD
```

## Teste do jogo

```powershell
.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
  "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
  --log-level=debug `
  --log-file=gpu_after_vsad_fix.txt
```

Depois:

```powershell
Select-String .\gpu_after_vsad_fix.txt -Pattern `
"COMPAT\]\[SHADER|unsupported vector opcode|shader|SPIR-V|Draw Calls|agc.dcb.draw"
```
