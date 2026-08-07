# SharpEmu — correção de ordenação Flip/Wait

O log do caso descentralizado registrou:

`vk.flip_wait_order version=1 executed before its flip capture; continuing.`

A causa era a ausência de uma dependência explícita entre
`VulkanOrderedGuestFlipWait` e a sequência exata do `VulkanOrderedGuestFlip`.
Como os dois podem chegar por filas lógicas diferentes, o escalonador podia
executar o wait antes da captura do snapshot.

A correção:

- registra `version -> work sequence` quando o flip é enfileirado;
- faz `GetGuestWorkDependencyLocked` retornar essa sequência para o wait;
- impede o wait de ser retirado da fila antes do flip concluir;
- funciona entre filas lógicas diferentes;
- remove a dependência depois do wait;
- limpa o estado no reset e no encerramento;
- mantém aviso apenas para falha real de captura;
- não altera scaling, viewport nem aplica deslocamento artificial.

Aplicação:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Flip-Ordering-Centering-Fix\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

Teste:

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=gpu_flip_order_fixed.txt
```
