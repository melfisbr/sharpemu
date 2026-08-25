# SharpEmu V76.2.2 — otimização de filas de processamento

Não reordena a FIFO do guest. Controla **backlog no host**, equilíbrio graphics/compute e profundidade adaptativa.

## Aplicar

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7622.zip -DestinationPath .\fixes-v7622 -Force
cd .\fixes-v7622
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## O que faz

| Mecanismo | Efeito |
|-----------|--------|
| **Max in-flight adaptativo** | Limita submits host (default 3); aperta se frame time sobe |
| **Burst por lane** | Graphics/compute cedem após N submits (default 4) |
| **Throttle spin+sleep** | Menos latência que `Sleep(1)` fixo |
| **EMA de frame time** | Ajusta profundidade conforme 60 Hz |
| **Hooks present/submit** | Integra no presenter |

## Env

| Variável | Default | Função |
|----------|---------|--------|
| `SHARPEMU_QUEUE_OPTIMIZER` | on | `0` desliga |
| `SHARPEMU_QUEUE_MAX_INFLIGHT` | 3 | teto de submits em voo |
| `SHARPEMU_QUEUE_LANE_BURST` | 4 | burst por lane |
| `SHARPEMU_HOST_TARGET_FPS` | 60 | alvo do EMA |
| `SHARPEMU_TRACE_QUEUE_OPTIMIZER` | off | log a cada 300 frames |

A FIFO guest e o hazard tracker V7615 continuam válidos; este pacote só limita pressão no host.
