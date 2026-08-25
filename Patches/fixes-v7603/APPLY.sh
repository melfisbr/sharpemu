#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "[APPLY V76.0.3] root=$ROOT"
copy_new() {
  mkdir -p "$(dirname "$ROOT/$1")"
  cp -f "$SCRIPT_DIR/new/$1" "$ROOT/$1"
  echo "  + $1"
}
copy_new "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.CacheV7603.cs"
copy_new "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.CacheV7603.cs"
copy_new "SharpEmu.Libs/Media/BinkCatchupV7603.cs"
copy_new "SharpEmu.Libs/VideoOut/VulkanPresentDiagnosticsV7603.cs"
# Reuse python block from APPLY.ps1 logic via external one-liner file
python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    if not p.exists():
        print(f"  ! missing {path}"); return
    t = p.read_text(encoding="utf-8")
    if new.strip() in t and old not in t:
        print(f"  = already {label}"); return
    if old not in t:
        print(f"  ! not found {label}"); return
    p.write_text(t.replace(old, new, 1), encoding="utf-8")
    print(f"  * {label}")

patch("SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
"        var translatedV74030 = Gen5SpirvTranslator.TryCompileVertexShader(\n                state,\n                evaluation,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                requiredVertexOutputCount,\n                storageBufferOffsetAlignment);",
"        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompileVertexCached(\n                state,\n                evaluation,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                requiredVertexOutputCount,\n                storageBufferOffsetAlignment);",
"vs-cache")
patch("SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
"        var translatedV74030 = Gen5SpirvTranslator.TryCompilePixelShader(\n                state,\n                evaluation,\n                outputs,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                pixelInputEnable,\n                pixelInputAddress,\n                pixelInputCntl,\n                storageBufferOffsetAlignment);",
"        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompilePixelCached(\n                state,\n                evaluation,\n                outputs,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                pixelInputEnable,\n                pixelInputAddress,\n                pixelInputCntl,\n                storageBufferOffsetAlignment);",
"ps-cache")
patch("SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
"        var translatedV74030 = Gen5SpirvTranslator.TryCompileComputeShader(\n                state,\n                evaluation,\n                localSizeX,\n                localSizeY,\n                localSizeZ,\n                out var compiled,\n                out error,\n                totalGlobalBufferCount,\n                initialScalarBufferIndex,\n                waveLaneCount,\n                storageBufferOffsetAlignment);",
"        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompileComputeCached(\n                state,\n                evaluation,\n                localSizeX,\n                localSizeY,\n                localSizeZ,\n                out var compiled,\n                out error,\n                totalGlobalBufferCount,\n                initialScalarBufferIndex,\n                waveLaneCount,\n                storageBufferOffsetAlignment);",
"cs-cache")
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)\n            : 8;",
"            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)\n            : 12; // V76.0.3",
"bink-catchup-frames")
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)\n                : 6));",
"                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)\n                : 10)); // V76.0.3",
"bink-catchup-budget")
print("[APPLY V76.0.3] done")
PY
echo "Rebuild: cd \"$ROOT\" && dotnet build"
