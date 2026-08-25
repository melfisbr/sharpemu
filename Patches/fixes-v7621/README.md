# SharpEmu V76.2.1 — F16 ALU, READLANE, MAD_I24, SUB_F64

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7621.zip -DestinationPath .\fixes-v7621 -Force
cd .\fixes-v7621
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Opcodes

| Opcode | Notas |
|--------|--------|
| `V_ADD/SUB/MUL/MAX/MIN/FMA_F16` | via EmitHalfToFloat/ToHalf |
| `V_PACK_B32_F16` | pack 2×f32→f16 |
| `V_MAD_I32_I24` | mul 24-bit signed + add |
| `V_SUB_F64` / `V_SUBREV_F64` | double |
| `V_READLANE_B32` | subgroup broadcast |

Encadeia **antes** do V76.2.0 na cadeia de fallbacks.
