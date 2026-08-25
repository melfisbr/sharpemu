# SharpEmu V76.1.7 — gaps restantes (shaders / Bink 60 / barriers)

Alinhado ao tree atual (V7605–V7616 + SoftFail + throttle).

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7617.zip -DestinationPath .\fixes-v7617 -Force
cd .\fixes-v7617
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## O que este pacote fecha

| Gap no src atual | Fix V76.1.7 |
|------------------|-------------|
| Bink default 30 fps | → **60** |
| Catch-up 8 / 6 ms | → **12 / 10 ms** |
| Vector opcode hard-fail | soft-fail |
| Image opcode hard-fail | soft-fail |
| LDS hard-fail / só 32-bit | 64-bit + soft-fail |
| Compares só F32/I32 | **F16 + I64/U64** |
| DPP sem wave 0x130 | expandido |
| SBarrier só compute | graphics memory/subgroup |
| Handoff só ps_studios_logo | attract/intro/logo |
| Sem frame pacer host | 60 Hz residual |

Requer `Gen5SpirvTranslator.SoftFailV7609.cs` (já no seu tree).
