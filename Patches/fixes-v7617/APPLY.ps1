param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.1.7] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Copy-New($Rel) {
  $src = Join-Path $ScriptDir "new\$Rel"
  $dst = Join-Path $CodeRoot $Rel
  if (-not (Test-Path $src)) { Write-Host "  ! $Rel"; return }
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $src $dst -Force
  Write-Host "  + $Rel"
}
Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaExpandV7617.cs"
Copy-New "SharpEmu.Libs\Media\BinkHandoffMoviesV7617.cs"
Copy-New "SharpEmu.Libs\VideoOut\HostFramePacerV7617.cs"

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

# Bink 60 / catchup
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 30;""",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 60; // V76.1.7""",
"bink-60")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 8;""",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 12; // V76.1.7""",
"bink-catchup-frames")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 6));""",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 10)); // V76.1.7""",
"bink-catchup-budget")

# Vector soft-fail
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
"vector-soft")

# Float F16 / int I64
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                    "VCmpNlgF32" or "VCmpxNlgF32" => SpirvOp.FUnordEqual,
                    _ => SpirvOp.Nop,
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported float compare {opcode}";
                    return false;
                }""",
"""                    "VCmpNlgF32" or "VCmpxNlgF32" => SpirvOp.FUnordEqual,
                    _ => MapExtraFloatCompareV7617(opcode),
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported float compare {opcode}";
                    return false;
                }""",
"float-f16")

patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                    "VCmpGeU32" or "VCmpxGeU32" => SpirvOp.UGreaterThanEqual,
                    _ => SpirvOp.Nop,
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported integer compare {opcode}";
                    return false;
                }""",
"""                    "VCmpGeU32" or "VCmpxGeU32" => SpirvOp.UGreaterThanEqual,
                    _ => MapExtraIntegerCompareV7617(opcode),
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported integer compare {opcode}";
                    return false;
                }""",
"int-i64")

# DPP
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""        private static bool IsSupportedDppControl(uint control) =>
            control <= 0xFF ||
            control is >= 0x101 and <= 0x10F or
                >= 0x111 and <= 0x11F or
                >= 0x121 and <= 0x12F or
                0x140 or 0x141 or
                >= 0x150 and <= 0x15F or
                >= 0x160 and <= 0x16F;""",
"""        private static bool IsSupportedDppControl(uint control) =>
            IsSupportedDppControlV7617(control);""",
"dpp")

# Image soft-fail
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
"image-soft")

# LDS atomic expand + soft
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                "DsCmpstB32" or "DsCmpstRtnB32" => SpirvOp.AtomicCompareExchange,
                _ => SpirvOp.Nop,
            };
            if (atomicOp == SpirvOp.Nop)
            {
                error = $"unsupported LDS opcode {instruction.Opcode}";
                return false;
            }""",
"""                "DsCmpstB32" or "DsCmpstRtnB32" => SpirvOp.AtomicCompareExchange,
                _ => MapExtraLdsAtomicV7617(instruction.Opcode),
            };
            if (atomicOp == SpirvOp.Nop)
            {
                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported LDS opcode {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"lds-atomic")

# LDS non-atomic default soft (if still hard)
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
"lds-default-soft")

# Atomic aliases
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""            op = name switch
            {
                "Swap" => SpirvOp.AtomicExchange,
                "Cmpswap" => SpirvOp.AtomicCompareExchange,
                "Add" => SpirvOp.AtomicIAdd,
                "Sub" => SpirvOp.AtomicISub,
                "Smin" => SpirvOp.AtomicSMin,
                "Umin" => SpirvOp.AtomicUMin,
                "Smax" => SpirvOp.AtomicSMax,
                "Umax" => SpirvOp.AtomicUMax,
                "And" => SpirvOp.AtomicAnd,
                "Or" => SpirvOp.AtomicOr,
                "Xor" => SpirvOp.AtomicXor,
                "Inc" => SpirvOp.AtomicIIncrement,
                "Dec" => SpirvOp.AtomicIDecrement,
                _ => SpirvOp.Nop,
            };
            return op != SpirvOp.Nop;
        }""",
"""            if (TryGetAtomicOpV7617(name, out op))
            {
                return true;
            }

            op = name switch
            {
                "Swap" => SpirvOp.AtomicExchange,
                "Cmpswap" => SpirvOp.AtomicCompareExchange,
                "Add" => SpirvOp.AtomicIAdd,
                "Sub" => SpirvOp.AtomicISub,
                "Smin" => SpirvOp.AtomicSMin,
                "Umin" => SpirvOp.AtomicUMin,
                "Smax" => SpirvOp.AtomicSMax,
                "Umax" => SpirvOp.AtomicUMax,
                "And" => SpirvOp.AtomicAnd,
                "Or" => SpirvOp.AtomicOr,
                "Xor" => SpirvOp.AtomicXor,
                "Inc" => SpirvOp.AtomicIIncrement,
                "Dec" => SpirvOp.AtomicIDecrement,
                _ => SpirvOp.Nop,
            };
            return op != SpirvOp.Nop;
        }""",
"atomic-aliases")

# SBarrier
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
                EmitStageBarrierV7617();
                return true;
            }""",
"sbarrier")

# Handoff
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.BinkHandoffBarrierV31722.cs",
"""        var fileName = Path.GetFileName(movieName ?? string.Empty);
        if (!string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_POST_STUDIOS_FRESH_FRAME_BARRIER"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }""",
"""        var fileName = Path.GetFileName(movieName ?? string.Empty);
        // V76.1.7: attract/intro/logo family
        if (!SharpEmu.Libs.Media.BinkHandoffMoviesV7617.ShouldArm(fileName))
        {
            return;
        }""",
"bink-handoff")

# Host pacer
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "HostFramePacerV7617.PaceBeforePresent()" in t:
        print("  = already pacer")
    else:
        for pat in ("VulkanSubmitThrottleV7610.OnPresented();", "_swapchainApi.QueuePresent(", "QueuePresentKHR("):
            idx = t.find(pat)
            if idx >= 0:
                ls = t.rfind("\n", 0, idx) + 1
                ind = re.match(r"[ \t]*", t[ls:idx]).group(0)
                insert = f"{ind}HostFramePacerV7617.PaceBeforePresent();\n"
                if "OnPresented" in pat:
                    insert = f"{ind}HostFramePacerV7617.PaceBeforePresent();\n"
                t = t[:ls] + insert + t[ls:]
                p.write_text(t, encoding="utf-8")
                print("  * host-pacer")
                break
        else:
            print("  ! host-pacer")

print("[APPLY V76.1.7] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7617.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
