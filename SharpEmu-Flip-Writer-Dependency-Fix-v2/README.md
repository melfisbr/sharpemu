# SharpEmu — Flip writer dependency fix v2

O log após a primeira correção mostrou:

`vk.flip_wait_order version=1 completed after its flip work sequence but no captured snapshot exists.`

Isso prova que o wait já não ultrapassa mais a sequência do flip, mas o
próprio flip terminou sem capturar a imagem.

A causa restante é outra dependência ausente: o flip pode estar em uma fila
lógica diferente do draw que escreveu o framebuffer. Sem dependência explícita,
`ExecuteOrderedGuestFlip` pode executar antes de o render target existir ou
estar inicializado.

Esta revisão:

- mantém `FlipWait -> Flip`;
- adiciona `Flip -> último writer do endereço`;
- usa `_guestImageWorkSequences[address]`;
- preserva a ordem entre filas graphics/compute;
- amplia o diagnóstico de `vk.flip_capture_failed`.

Aplicação:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Flip-Writer-Dependency-Fix-v2\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

Teste:

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=gpu_flip_writer_fixed.txt
```

Verifique:

```powershell
Select-String .\gpu_flip_writer_fixed.txt -Pattern `
"vk.flip_capture_failed|vk.flip_wait_order|presented guest frame"
```
