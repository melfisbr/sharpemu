param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.1.8] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$src = Join-Path $ScriptDir "new\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftDepsV7618.cs"
$dst = Join-Path $CodeRoot "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftDepsV7618.cs"
Copy-Item $src $dst -Force
Write-Host "  + SoftDepsV7618.cs"

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

# Global-memory atomic soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                if (!TryGetAtomicOp(
                        memoryOpcode["GlobalAtomic".Length..],
                        out var atomicOp))
                {
                    error = $"unsupported global-memory opcode {memoryOpcode}";
                    return false;
                }""",
"""                if (!TryGetAtomicOp(
                        memoryOpcode["GlobalAtomic".Length..],
                        out var atomicOp))
                {
                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported global-memory opcode {memoryOpcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
                }""",
"global-atomic-soft")

# Generic global-memory fail if present
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    old = 'error = $"unsupported global-memory opcode {memoryOpcode}";\n                    return false;'
    new = '''if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported global-memory opcode {memoryOpcode}",
                        out error))
                    {
                        return true;
                    }

                    return false;'''
    if old in t:
        t = t.replace(old, new)
        p.write_text(t, encoding="utf-8")
        print("  * global-mem-soft-extra")
    else:
        print("  = global-mem-soft-extra skip")

# Storage image soft-fail (both indent levels)
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    n = 0
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
            n += 1
    p.write_text(t, encoding="utf-8")
    print(f"  * storage-image-soft x{n}" if n else "  ! storage-image-soft")

# Scalar compare soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                error = $"unsupported scalar compare {instruction.Opcode}";
                return false;
            }""",
"""                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported scalar compare {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"scalar-compare-soft")

patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                error = $"unsupported scalar immediate compare {instruction.Opcode}";
                return false;
            }""",
"""                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported scalar immediate compare {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"scalar-imm-compare-soft")

# Scalar 64-bit soft-fail (two sites)
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    n = 0
    for old in [
        '''                        $"unsupported scalar 64-bit opcode {instruction.Opcode}";
                    return false;''',
        '''                    error = $"unsupported scalar 64-bit opcode {instruction.Opcode}";
                    return false;''',
    ]:
        # normalize - the first might be incomplete
        pass
    old1 = 'error = $"unsupported scalar 64-bit opcode {instruction.Opcode}";\n                    return false;'
    new1 = '''if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported scalar 64-bit opcode {instruction.Opcode}",
                        out error))
                    {
                        return true;
                    }

                    return false;'''
    old2 = 'error = $"unsupported scalar 64-bit opcode {instruction.Opcode}";\n                return false;'
    new2 = '''if (TrySoftFailInstruction(
                    instruction,
                    $"unsupported scalar 64-bit opcode {instruction.Opcode}",
                    out error))
                {
                    return true;
                }

                return false;'''
    # also interpolated form with leading $"
    old3 = '''                        $"unsupported scalar 64-bit opcode {instruction.Opcode}";
                    return false;'''
    # skip odd forms
    c = 0
    if old1 in t:
        t = t.replace(old1, new1); c += 1
    if old2 in t:
        t = t.replace(old2, new2); c += 1
    p.write_text(t, encoding="utf-8")
    print(f"  * scalar-64-soft x{c}" if c else "  ! scalar-64-soft")

# Scalar immediate soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                    error = $"unsupported scalar immediate {instruction.Opcode}";
                    return false;
                }""",
"""                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported scalar immediate {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
                }""",
"scalar-imm-soft")

# saveexec soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                    error = $"unsupported scalar 32-bit saveexec opcode {instruction.Opcode}";
                    return false;
                }""",
"""                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported scalar 32-bit saveexec opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;
                }""",
"saveexec-soft")

# Bink AV clock default 60
patch(
"SharpEmu.Libs/Media/BinkGuestAvClockV7613.cs",
"""            ? Math.Clamp(targetFps, 1, 120)
            : 30;""",
"""            ? Math.Clamp(targetFps, 1, 120)
            : 60; // V76.1.8: align with host Bink 60 fps defaults""",
"bink-av-clock-60")

# DPP hard-fail -> soft-fail attempt (cannot soft-fail easily before emit; zero dest via soft-fail)
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""            if (instruction.Control is Gen5DppControl dppControl &&
                !IsSupportedDppControl(dppControl.Control))
            {
                error = $"unsupported DPP16 control 0x{dppControl.Control:X3}";
                return false;
            }""",
"""            if (instruction.Control is Gen5DppControl dppControl &&
                !IsSupportedDppControl(dppControl.Control))
            {
                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported DPP16 control 0x{dppControl.Control:X3}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"dpp-soft")

print("[APPLY V76.1.8] done")
'@

$pyFile = Join-Path $env:TEMP "sharpemu_v7618.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
