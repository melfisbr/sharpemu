# SharpEmu V76.0.4 — Soft-fail shaders + barriers + frame stats

Aplique **depois** de V76.0.2 e V76.0.3.

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive -Path .\sharpemu-fixes-v7604.zip -DestinationPath .\fixes-v7604 -Force
cd .\fixes-v7604
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Mudanças

| Item | Efeito |
|------|--------|
| **Soft-fail** (default on) | Opcode vector/image/LDS não suportado zera destinos e continua — evita shader inteiro falhar |
| **SBarrier** | Compute: workgroup; graphics: memory + subgroup barrier |
| **Frame stats** | `SHARPEMU_TRACE_FRAME_STATS=1` → % frames a 60/30 fps |

## Env

- `SHARPEMU_SHADER_SOFT_FAIL=0` — volta a falhar hard em opcode desconhecido
- `SHARPEMU_TRACE_SHADER_SOFT_FAIL=1` — loga cada op soft-failed (uma vez)
- `SHARPEMU_TRACE_FRAME_STATS=1` — histograma de frame time
