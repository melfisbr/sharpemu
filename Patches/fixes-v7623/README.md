# SharpEmu V76.2.3 — Bink não decodifica / ~1–2 FPS

## Diagnóstico (log)

| Sinal | Significado |
|-------|-------------|
| `[BINK-GUEST] ... guest-bink-active` | Decode só no GPU guest |
| `PERF fps=1,8` | Host engasgado |
| `SEMANTIC_WAIT waited_ms=120–620` | Fila graphics bloqueada |
| `SLOW_WAIT_PRODUCER 1,4–2,0s` | Compute espera write_data |
| Sem linhas RAD/host decoder | Host bloqueado por policy V76 |

**Causa no source:** `BinkGuestOwnedRuntimeV7600.Enabled` é true salvo `SHARPEMU_BINK_ALLOW_HOST_DECODER=1`. Isso faz `RadBinkExternalPlayback` e `BinkHostPlaybackAssist` retornarem cedo — **nenhum decoder host**. O path guest GPU está correto em teoria, mas no runtime atual não sustenta vídeo em tempo real.

## Correção

1. **Hybrid host decode ON por default** (`BinkDecodePolicyV7623`)
2. Initialize guest não força `BINK_MODE=guest` se host permitido
3. YUV producer aceita `ContentGeneration > 0` (evita frame preto)
4. Hold do primeiro frame 180ms → 16ms

## Aplicar

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7623-bink.zip -DestinationPath .\fixes-v7623 -Force
cd .\fixes-v7623
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Env

| Variável | Efeito |
|----------|--------|
| (default) | host decoder híbrido ON |
| `SHARPEMU_BINK_FORCE_GUEST=1` | volta ao guest GPU puro |
| `SHARPEMU_BINK_HYBRID_HOST=0` | desliga hybrid (só ALLOW_HOST clássico) |

Requer RAD/Nihav host tools se o path externo for usado (`SHARPEMU_RADVIDEO64` etc.).
