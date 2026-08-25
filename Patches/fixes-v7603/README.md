# SharpEmu V76.0.3 — Shader result cache + Bink catch-up + present cadence

Requires V76.0.2 already applied (or apply both in order).

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive -Path .\sharpemu-fixes-v7603.zip -DestinationPath .\fixes-v7603 -Force
cd .\fixes-v7603
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## O que entra

| Item | Efeito |
|------|--------|
| Cache de resultado VS/PS/CS | Evita retraduzir o mesmo shader no processo (grande ganho após o 1º frame) |
| Persistência SPIR-V em disco | Complementa o cache de processo |
| Bink catch-up | Max frames 8→12, budget 6→10 ms (melhor sustentar 60 fps após stall) |
| Diagnóstico de present | `SHARPEMU_TRACE_PRESENT_CADENCE=1` loga ema_fps |

## Env

- `SHARPEMU_SPIRV_RESULT_CACHE=0` desliga cache de resultado
- `SHARPEMU_TRACE_PRESENT_CADENCE=1` log de cadência
