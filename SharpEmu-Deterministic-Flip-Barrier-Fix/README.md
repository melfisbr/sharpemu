# SharpEmu — deterministic flip barrier fix

## Revisão do pipeline

A revisão do pacote completo confirmou que o presenter possui filas lógicas
independentes para graphics e compute. O escalonador preserva FIFO dentro de
cada fila, mas prioriza marcadores de sincronização prontos entre filas.

Isso permite que um `VulkanOrderedGuestFlip` capture o framebuffer quando
trabalhos anteriores de composição, provenientes de outras filas, ainda não
terminaram. `SHARPEMU_LOG_AGC=1` escondia o problema ao reduzir a velocidade
dos produtores.

## Alterações

- todo flip passa a depender de todas as sequências globais anteriores;
- `FlipWait` continua dependente do flip correspondente;
- conclusão da captura é armazenada separadamente da vida útil do VkImage;
- aposentar/destruir o snapshot não apaga a prova de que a captura aconteceu;
- o histórico é removido quando o wait correspondente é processado;
- nenhum deslocamento, crop ou ajuste artificial de viewport foi aplicado.

## Aplicação

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Deterministic-Flip-Barrier-Fix\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue

.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=gpu_deterministic_flip.txt
```

```powershell
Select-String .\gpu_deterministic_flip.txt -Pattern `
"vk.flip_wait_order|vk.flip_capture_failed|presented guest frame"
```
