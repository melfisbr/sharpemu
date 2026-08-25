# SharpEmu V76.0.10

Aplique **depois** do V76.0.9 (soft-fail / Bink 60 / DPP / compares).

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7610.zip -DestinationPath .\fixes-v7610 -Force
cd .\fixes-v7610
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

O script detecta automaticamente `src\SharpEmu.Libs` vs `SharpEmu.Libs` na raiz.

## Conteúdo

| Item | Efeito |
|------|--------|
| Scalar scheduling NOPs | SDelayAlu, SSleep, SSetvskip, wait-alu, etc. |
| Soft-fail buffer opcodes | Não mata translate em MUBUF/MTBUF desconhecido |
| Soft-fail scalar default | Opcode scalar raro → destinos zero |
| Submit throttle | Limita backlog de frames (~2) para sustentar 60 Hz |
| Shader compile budget log | Avisa traduções > 40 ms |
| Bink wall-clock prefer | Sugere sessão wall-clock a 60 fps |

## Env

- `SHARPEMU_SUBMIT_THROTTLE=0` — desliga throttle
- `SHARPEMU_SUBMIT_THROTTLE_FRAMES=2` — profundidade
- `SHARPEMU_SHADER_TRANSLATE_BUDGET_MS=40`
- `SHARPEMU_BINK_WALLCLOCK_SESSION=0` — desliga preferência wall-clock
