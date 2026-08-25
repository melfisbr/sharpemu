param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.2.0] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $CodeRoot "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaF64PermV7620.cs"
Copy-Item (Join-Path $ScriptDir "new\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaF64PermV7620.cs") $dst -Force
Write-Host "  + IsaF64PermV7620.cs"

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

# Prefer V7620 before V7619 in vector default chain
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
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
"""                default:
                    if (TryEmitExtraVectorOpcodeV7620(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }

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
"vector-chain-7620")

# If only soft-fail or hard-fail without V7619
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
                    if (TryEmitExtraVectorOpcodeV7620(
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
"vector-chain-7620-softonly")

print("[APPLY V76.2.0] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7620.py"
Set-Content $pyFile $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
