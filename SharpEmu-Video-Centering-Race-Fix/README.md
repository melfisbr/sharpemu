# SharpEmu — correção de centralização do vídeo

## Causa

O vídeo só ficava centralizado quando `SHARPEMU_LOG_AGC=1` porque o log
reduzia a velocidade do produtor gráfico e escondia uma condição de corrida.

O snapshot do flip era publicado para o thread de apresentação imediatamente
após `vkQueueSubmit`, antes de a cópia GPU do render target final terminar.

## Correção

- aguarda especificamente o fence/timeline do snapshot de flip;
- só depois marca o snapshot como inicializado;
- só depois publica a apresentação;
- não depende mais de `SHARPEMU_LOG_AGC=1`;
- não altera a matemática de `--scaling=fit`.

## Aplicação

Extraia na raiz do repositório e execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\SharpEmu-Video-Centering-Race-Fix\apply_and_validate.ps1 `
    -RepositoryRoot $PWD
```

## Teste

Remova a variável de diagnóstico:

```powershell
Remove-Item Env:\SHARPEMU_LOG_AGC -ErrorAction SilentlyContinue
```

Execute:

```powershell
.\artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe `
    "F:\JOGOSPS5\PPSA25646-app\eboot.bin" `
    --scaling=fit `
    --log-level=debug `
    --log-file=gpu_centering_fixed.txt
```
