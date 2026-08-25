# SharpEmu V76.1.9 MAX — implementações reais + defaults 60 fps

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7619.zip -DestinationPath .\fixes-v7619 -Force
cd .\fixes-v7619
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Implementações novas (não só soft-fail)

| Opcode / feature | Implementação |
|------------------|---------------|
| `V_LANEID_B32` | índice da lane guest |
| `V_MBCNT_LO/HI_U32_B32` | prefix popcount do EXEC |
| `V_ALIGNBIT_B32` | align de bits 64→32 |
| `V_ALIGNBYTE_B32` | align de bytes |
| `V_FFBH_U32` / `V_FFBH_I32` | find first bit high |
| `V_LDEXP_F32` | ldexp via GLSL.std.450 |
| `V_FREXP_EXP_I32_F32` | expoente IEEE |
| `S_CMP_*` / `S_CMPK_*` **I64/U64** | compares scalar 64-bit |

## Defaults (idempotente se já 60)

- Bink target / AV clock → **60**
- Catch-up → **12 frames / 10 ms**

Requer SoftFailV7609. Aplique depois de 7617/7618 se possível.
