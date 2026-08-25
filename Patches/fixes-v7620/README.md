# SharpEmu V76.2.0 — F64, V_PERM, DOT4, shifts 64-bit

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7620.zip -DestinationPath .\fixes-v7620 -Force
cd .\fixes-v7620
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Implementações

| Opcode | Descrição |
|--------|-----------|
| `V_ADD/MUL/FMA/RCP/SQRT_F64` | aritmética double em par VGPR |
| `V_CVT_F32_F64` / `V_CVT_F64_F32` | conversões |
| `V_PERM_B32` | permutação de bytes |
| `V_DOT4_I32_I8` | dot product 4x int8 |
| `V_LSHLREV/LSHRREV/ASHRREV_*B64` | shifts 64-bit |

Encadeia **antes** do V76.1.9 no default do translator.
