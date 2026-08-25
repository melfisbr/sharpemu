# SharpEmu V76.1.8 — dependências restantes (soft-fail + Bink AV 60)

Aplique **depois** do V76.1.7. Requer `SoftFailV7609`.

## Windows

```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Expand-Archive .\sharpemu-fixes-v7618.zip -DestinationPath .\fixes-v7618 -Force
cd .\fixes-v7618
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

## Conteúdo

| Dependência restante | Fix |
|----------------------|-----|
| Global memory atomic desconhecido | soft-fail |
| Storage image opcode | soft-fail |
| Scalar compare / imm / 64-bit / saveexec | soft-fail |
| DPP16 control ainda rejeitado | soft-fail |
| BinkGuestAvClock target 30 | → **60** |

## Ainda de longo prazo (não neste pacote)

- Implementação real de cada image/VOP3P restante (não só soft-fail)
- Presenter Vulkan como instância
- Modelo completo async-compute PS5 no host
