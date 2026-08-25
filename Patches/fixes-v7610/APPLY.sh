#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"
CODE="$ROOT"
[[ -d "$ROOT/src/SharpEmu.Libs" ]] && CODE="$ROOT/src"
SD="$(cd "$(dirname "$0")" && pwd)"
echo "[APPLY V76.0.10] code=$CODE"
for f in \
  SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.BufferScalarSoftV7610.cs \
  SharpEmu.Libs/VideoOut/VulkanSubmitThrottleV7610.cs \
  SharpEmu.Libs/Media/BinkSessionDefaultsV7610.cs \
  SharpEmu.Libs/Gpu/Vulkan/VulkanShaderCompileBudgetV7610.cs
do
  mkdir -p "$(dirname "$CODE/$f")"
  cp -f "$SD/new/$f" "$CODE/$f"
  echo "  + $f"
done
echo "Run APPLY.ps1 on Windows for surgical patches, or use the python block from APPLY.ps1"
