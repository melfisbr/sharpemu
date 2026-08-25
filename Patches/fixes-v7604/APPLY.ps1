param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "[APPLY V76.0.4] root=$Root"

function Copy-New($Rel) {
  $src = Join-Path $ScriptDir "new\$Rel"
  $dst = Join-Path $Root $Rel
  if (-not (Test-Path $src)) { Write-Host "  ! $Rel"; return }
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $src $dst -Force
  Write-Host "  + $Rel"
}
Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftFailV7604.cs"
Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.BarriersV7604.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanFrameStatsV7604.cs"

$py = @'
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

# Vector opcode soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
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

# Image unsupported soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
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

# Storage image soft-fail (two sites - replace_all via loop)
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    old = '''                    error = $"unsupported storage image opcode {instruction.Opcode}";
                    return false;'''
    new = '''                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported storage image opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;'''
    # also the non-indented variant
    old2 = '''                error = $"unsupported storage image opcode {instruction.Opcode}";
                return false;'''
    new2 = '''                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported storage image opcode {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;'''
    c = 0
    if old in t:
        t = t.replace(old, new)
        c += 1
    if old2 in t:
        t = t.replace(old2, new2)
        c += 1
    if c:
        p.write_text(t, encoding="utf-8")
        print(f"  * storage-image-soft-fail x{c}")
    else:
        print("  ! storage-image-soft-fail")

# LDS unsupported soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
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

# SBarrier: use EmitStageBarrierV7604
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
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

# Frame stats near present diagnostics
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "VulkanFrameStatsV7604.NoteFrameEnd()" in t:
        print("  = already frame-stats")
    elif "VulkanPresentDiagnosticsV7603.NotePresent()" in t:
        t = t.replace(
            "VulkanPresentDiagnosticsV7603.NotePresent();",
            "VulkanPresentDiagnosticsV7603.NotePresent();\n                    VulkanFrameStatsV7604.NoteFrameEnd();",
            1)
        p.write_text(t, encoding="utf-8")
        print("  * frame-stats")
    elif "PaceHostPresentV7602();" in t:
        t = t.replace(
            "PaceHostPresentV7602();",
            "PaceHostPresentV7602();\n                    VulkanFrameStatsV7604.NoteFrameEnd();",
            1)
        p.write_text(t, encoding="utf-8")
        print("  * frame-stats-pacer")
    else:
        print("  ! frame-stats not wired")

print("[APPLY V76.0.4] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7604.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $Root
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $Root }
Write-Host "dotnet build in $Root"
