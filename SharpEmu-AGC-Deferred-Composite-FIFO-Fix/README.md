# SharpEmu — AGC deferred composite FIFO fix

## Investigação

A comparação visual mostrou que o caso sem `SHARPEMU_LOG_AGC=1` não estava
descentralizado: o framebuffer estava incompleto. Apenas uma camada, como
`SERIES`, chegava ao frame final.

A revisão de `AgcExports.cs` encontrou uma perda determinística de draws:

- `SubmittedDcbState` guardava somente um `PendingTargetlessDraw`;
- ao começar o draw seguinte, o draw pendente anterior era devolvido ao pool;
- um novo draw targetless sobrescrevia o anterior;
- no pacote `RFlip`, somente o último draw era composto no display buffer.

Isso é incompatível com telas compostas por múltiplos passes targetless.
O log AGC apenas desacelerava a execução e mascarava a perda em alguns frames.

## Correção

- substitui o slot único por uma FIFO;
- preserva todos os draws targetless na ordem do DCB;
- no `RFlip`, envia todos ao display target na ordem original;
- libera corretamente os recursos caso o target não seja resolvido;
- não altera scaling, viewport, swapchain nem ShaderCompiler.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-AGC-Deferred-Composite-FIFO-Fix\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=gpu_composite_fifo.txt
```
