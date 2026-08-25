param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.1.9 MAX] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Copy-New($Rel) {
  $s = Join-Path $ScriptDir "new\$Rel"
  $d = Join-Path $CodeRoot $Rel
  $dir = Split-Path $d -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $s $d -Force
  Write-Host "  + $Rel"
}
Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaImplementV7619.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanPresentCadenceBoostV7619.cs"

$py = @'
import pathlib, sys, re
root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    if not p.exists():
        print("  ! missing", path); return False
    t = p.read_text(encoding="utf-8")
    if new in t and old not in t:
        print("  = already", label); return True
    if old not in t:
        print("  ! not found", label); return False
    p.write_text(t.replace(old, new, 1), encoding="utf-8")
    print("  *", label); return True

# Vector default: try real emit then soft-fail
# May already have soft-fail from 7617
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
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
"""                default:
                    if (TryEmitExtraVectorOpcodeV7619(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }

                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported vector opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
            }""",
"vector-extra-impl")

# If still hard-fail form (no soft-fail applied)
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                default:
                    error = $"unsupported vector opcode {instruction.Opcode}";
                    return false;
            }""",
"""                default:
                    if (TryEmitExtraVectorOpcodeV7619(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }

                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported vector opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
            }""",
"vector-extra-impl-hard")

# Scalar compare: map 64-bit
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                "SCmpLeU32" => SpirvOp.ULessThanEqual,
                _ => SpirvOp.Nop,
            };
            if (operation == SpirvOp.Nop)
            {
                error = $"unsupported scalar compare {instruction.Opcode}";
                return false;
            }""",
"""                "SCmpLeU32" => SpirvOp.ULessThanEqual,
                _ => MapExtraScalarCompareV7619(instruction.Opcode),
            };
            if (operation == SpirvOp.Nop)
            {
                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported scalar compare {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"scalar-cmp-64")

# Scalar compareK 64
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                "SCmpkLeU32" => SpirvOp.ULessThanEqual,
                _ => SpirvOp.Nop,
            };
            if (operation == SpirvOp.Nop)
            {
                error = $"unsupported scalar immediate compare {instruction.Opcode}";
                return false;
            }""",
"""                "SCmpkLeU32" => SpirvOp.ULessThanEqual,
                _ => MapExtraScalarCompareKV7619(instruction.Opcode),
            };
            if (operation == SpirvOp.Nop)
            {
                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported scalar immediate compare {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"scalar-cmpk-64")

# Bink defaults if still 30
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 30;""",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 60; // V76.1.9""",
"bink-60")

patch("SharpEmu.Libs/Media/BinkGuestAvClockV7613.cs",
"""            ? Math.Clamp(targetFps, 1, 120)
            : 30;""",
"""            ? Math.Clamp(targetFps, 1, 120)
            : 60; // V76.1.9""",
"bink-av-60")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 8;""",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 12; // V76.1.9""",
"bink-catchup")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 6));""",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 10)); // V76.1.9""",
"bink-budget")

print("[APPLY V76.1.9 MAX] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7619.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
