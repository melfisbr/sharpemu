#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"
SD="$(cd "$(dirname "$0")" && pwd)"
echo "[APPLY V76.0.4] root=$ROOT"
for f in \
  SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.SoftFailV7604.cs \
  SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.BarriersV7604.cs \
  SharpEmu.Libs/VideoOut/VulkanFrameStatsV7604.cs
do
  mkdir -p "$(dirname "$ROOT/$f")"
  cp -f "$SD/new/$f" "$ROOT/$f"
  echo "  + $f"
done
python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    if not p.exists():
        print("  ! missing", path); return
    t = p.read_text(encoding="utf-8")
    if new in t and old not in t:
        print("  = already", label); return
    if old not in t:
        print("  ! not found", label); return
    p.write_text(t.replace(old, new, 1), encoding="utf-8")
    print("  *", label)

patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                default:
                    error = $"unsupported vector opcode {instruction.Opcode}";
                    return false;
            }""",
"""                default:
                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported vector opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
            }""",
"vector-soft-fail")

patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                error = $"unsupported image opcode {instruction.Opcode}";
                return false;
            }""",
"""                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported image opcode {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"image-soft-fail")

p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
t = p.read_text(encoding="utf-8")
for old, new in [
( '''                    error = $"unsupported storage image opcode {instruction.Opcode}";
                    return false;''',
  '''                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported storage image opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;'''),
( '''                error = $"unsupported storage image opcode {instruction.Opcode}";
                return false;''',
  '''                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported storage image opcode {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;'''),
]:
    if old in t:
        t = t.replace(old, new)
        print("  * storage-image-soft-fail")
p.write_text(t, encoding="utf-8")

patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                    error = $"unsupported LDS opcode {instruction.Opcode}";
                    return false;
            }
        }

        private static uint EffectiveDsPairOffsetBytes""",
"""                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported LDS opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
            }
        }

        private static uint EffectiveDsPairOffsetBytes""",
"lds-soft-fail")

patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""            if (instruction.Opcode == "SBarrier")
            {
                if (_stage == Gen5SpirvStage.Compute)
                {
                    var workgroup = UInt(2);
                    var semantics = UInt(0x108);
                    _module.AddStatement(
                        SpirvOp.ControlBarrier,
                        workgroup,
                        workgroup,
                        semantics);
                }
                return true;
            }""",
"""            if (instruction.Opcode == "SBarrier")
            {
                // V76.0.4: workgroup barrier on compute; memory/subgroup on graphics
                EmitStageBarrierV7604();
                return true;
            }""",
"sbarrier-expand")
print("[APPLY V76.0.4] done")
PY
