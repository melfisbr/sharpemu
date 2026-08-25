param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.2.1] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Copy-Item (Join-Path $ScriptDir "new\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaF16ReadlaneV7621.cs") `
  (Join-Path $CodeRoot "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaF16ReadlaneV7621.cs") -Force
Write-Host "  + IsaF16ReadlaneV7621.cs"

$py = @'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs"
if not p.exists():
    print("  ! missing Alu.cs"); raise SystemExit(1)
t = p.read_text(encoding="utf-8")
needle = """                default:
                    if (TryEmitExtraVectorOpcodeV7620(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }
"""
insert = """                default:
                    if (TryEmitExtraVectorOpcodeV7621(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }

                    if (TryEmitExtraVectorOpcodeV7620(
                            instruction,
                            destination,
                            out result,
                            out error))
                    {
                        break;
                    }
"""
if "TryEmitExtraVectorOpcodeV7621" in t:
    print("  = already v7621-chain")
elif needle in t:
    t = t.replace(needle, insert, 1)
    p.write_text(t, encoding="utf-8")
    print("  * v7621-chain")
else:
    # soft-only chain
    needle2 = """                default:
                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported vector opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
            }"""
    insert2 = """                default:
                    if (TryEmitExtraVectorOpcodeV7621(
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
            }"""
    if needle2 in t:
        t = t.replace(needle2, insert2, 1)
        p.write_text(t, encoding="utf-8")
        print("  * v7621-chain-soft")
    else:
        print("  ! vector default chain not found — add TryEmitExtraVectorOpcodeV7621 manually")
print("[APPLY V76.2.1] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7621.py"
Set-Content $pyFile $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
