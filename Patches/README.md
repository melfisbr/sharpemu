# SharpEmu V76.0.2 — Shaders / Compute / Bink-Vulkan / 60 FPS

## Windows (PowerShell)

```powershell
# 1) Extrair o zip em qualquer pasta, ex.: C:\Temp\fixes
Expand-Archive sharpemu-fixes-60fps.zip -DestinationPath C:\Temp\fixes -Force

# 2) Aplicar no repositório
cd C:\Temp\fixes
powershell -ExecutionPolicy Bypass -File .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"

# 3) Build da solution (na raiz do repo)
cd C:\Users\Edpo\Documents\GitHub\sharpemu
dotnet build
```

Requer **Python 3** no PATH (`python` ou `py -3`).

## Linux / macOS / Git Bash / WSL

```bash
unzip sharpemu-fixes-60fps.zip -d /tmp/fixes
/tmp/fixes/APPLY.sh "/c/Users/Edpo/Documents/GitHub/sharpemu"   # Git Bash
# ou
/tmp/fixes/APPLY.sh /home/.../sharpemu                          # WSL/Linux

cd /caminho/para/sharpemu
dotnet build
```

## O que o build faz

`dotnet build` na raiz compila a solution inteira (incluindo `SharpEmu.Libs` e `SharpEmu.ShaderCompiler.Vulkan`), se existir um `.sln`.

Se preferir projetos isolados:

```powershell
dotnet build SharpEmu.ShaderCompiler.Vulkan\SharpEmu.ShaderCompiler.Vulkan.csproj
dotnet build SharpEmu.Libs\SharpEmu.Libs.csproj
```

(ajuste os caminhos se a estrutura do repo for diferente)

## Variáveis de ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `SHARPEMU_BINK_TARGET_FPS` | **60** | FPS alvo Bink |
| `SHARPEMU_HOST_FRAME_PACER` | on (`0` desliga) | Pacing host |
| `SHARPEMU_HOST_TARGET_FPS` | 60 | FPS do pacer |
| `SHARPEMU_SPIRV_DISK_CACHE` | on (`0` desliga) | Cache SPIR-V |
| `SHARPEMU_SPIRV_CACHE_DIR` | `user/spirv_cache` | Pasta do cache |

## Conteúdo

- `APPLY.ps1` — Windows
- `APPLY.sh` — Linux/macOS/Git Bash
- `new/` — arquivos novos
- patches cirúrgicos aplicados pelos scripts
