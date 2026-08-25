param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"

# Support both repo layouts: <root>/SharpEmu.Libs and <root>/src/SharpEmu.Libs
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) {
  $CodeRoot = Join-Path $Root "src"
}
Write-Host "[APPLY V76.0.10] root=$Root code=$CodeRoot"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Copy-New([string]$Rel) {
  $src = Join-Path $ScriptDir "new\$Rel"
  $dst = Join-Path $CodeRoot $Rel
  if (-not (Test-Path $src)) { Write-Host "  ! missing $Rel"; return }
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $src $dst -Force
  Write-Host "  + $Rel"
}

Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.BufferScalarSoftV7610.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanSubmitThrottleV7610.cs"
Copy-New "SharpEmu.Libs\Media\BinkSessionDefaultsV7610.cs"
Copy-New "SharpEmu.Libs\Gpu\Vulkan\VulkanShaderCompileBudgetV7610.cs"

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

# Expand scalar nop list to call V7610 helper first
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""            if (instruction.Opcode is
                "SNop" or
                "SWaitcnt" or
                "SInstPrefetch" or
                "STtraceData" or
                // SHARPEMU_V74_0_104_RDNA2_S_TRAP_COMPAT
                // Guest trap-handler side effects are not representable in
                // SPIR-V here; preserve shader execution instead of failing
                // translation on the legal RDNA2 S_TRAP opcode.
                "STrap" or
                // NGG shaders bracket their exports with s_sendmsg
                // (GS_ALLOC_REQ/DEALLOC) to reserve hardware export space;
                // exports are translated directly, so the message is moot.
                "SSendmsg" or
                "VInterpMovF32")
            {
                return true;
            }""",
"""            if (TryEmitScalarSchedulingNopV7610(instruction, out error))
            {
                return true;
            }

            if (instruction.Opcode is
                "SNop" or
                "SWaitcnt" or
                "SInstPrefetch" or
                "STtraceData" or
                // SHARPEMU_V74_0_104_RDNA2_S_TRAP_COMPAT
                // Guest trap-handler side effects are not representable in
                // SPIR-V here; preserve shader execution instead of failing
                // translation on the legal RDNA2 S_TRAP opcode.
                "STrap" or
                // NGG shaders bracket their exports with s_sendmsg
                // (GS_ALLOC_REQ/DEALLOC) to reserve hardware export space;
                // exports are translated directly, so the message is moot.
                "SSendmsg" or
                "VInterpMovF32")
            {
                return true;
            }""",
"scalar-sched-nop")

# Buffer unsupported -> soft-fail if available
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""            if (!instruction.Opcode.StartsWith("BufferLoad", StringComparison.Ordinal) &&
                !instruction.Opcode.StartsWith("TBufferLoad", StringComparison.Ordinal))
            {
                error = $"unsupported buffer opcode {instruction.Opcode}";
                return false;
            }""",
"""            if (!instruction.Opcode.StartsWith("BufferLoad", StringComparison.Ordinal) &&
                !instruction.Opcode.StartsWith("TBufferLoad", StringComparison.Ordinal))
            {
                if (TrySoftFailInstruction(
                        instruction,
                        $"unsupported buffer opcode {instruction.Opcode}",
                        out error))
                {
                    return true;
                }

                return false;
            }""",
"buffer-soft-fail")

# Second buffer atomic unsupported path
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    old = '''                    error = $"unsupported buffer opcode {instruction.Opcode}";
                    return false;'''
    new = '''                    if (TrySoftFailInstruction(
                            instruction,
                            $"unsupported buffer opcode {instruction.Opcode}",
                            out error))
                    {
                        return true;
                    }

                    return false;'''
    if old in t:
        t = t.replace(old, new)
        p.write_text(t, encoding="utf-8")
        print("  * buffer-atomic-soft")
    else:
        print("  = buffer-atomic-soft skip")

# Scalar opcode default soft-fail
patch(
"SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                        default:
                            error = $"unsupported scalar opcode {instruction.Opcode}";
                            return false;
                    }

                    break;
                }""",
"""                        default:
                            if (TrySoftFailInstruction(
                                    instruction,
                                    $"unsupported scalar opcode {instruction.Opcode}",
                                    out error))
                            {
                                return true;
                            }

                            return false;
                    }

                    break;
                }""",
"scalar-soft")

# Wire submit throttle + present
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "VulkanSubmitThrottleV7610.OnPresented()" in t:
        print("  = already throttle-present")
    else:
        inserted = False
        for pat in ("HostFramePacerV7609.PaceBeforePresent();", "PaceHostPresentV7602();", "_swapchainApi.QueuePresent("):
            if pat in t:
                if pat.startswith("_"):
                    idx = t.find(pat)
                    ls = t.rfind("\n", 0, idx) + 1
                    ind = re.match(r"[ \t]*", t[ls:idx]).group(0)
                    t = t[:ls] + f"{ind}VulkanSubmitThrottleV7610.OnPresented();\n" + t[ls:]
                else:
                    t = t.replace(pat, pat + "\n                    VulkanSubmitThrottleV7610.OnPresented();", 1)
                p.write_text(t, encoding="utf-8")
                print("  * throttle-present")
                inserted = True
                break
        if not inserted:
            print("  ! throttle-present")

# Wire compile budget in Vulkan backend
p = root / "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "VulkanShaderCompileBudgetV7610" in t:
        print("  = already compile-budget")
    else:
        # After TraceShaderTranslateV74030 calls, add budget note - patch first occurrence pattern
        old = "TraceShaderTranslateV74030(\"vertex\", state, translateStartV74030, translatedV74030);"
        new = """TraceShaderTranslateV74030("vertex", state, translateStartV74030, translatedV74030);
        VulkanShaderCompileBudgetV7610.Note("vertex", state.Program.Address, translateStartV74030, translatedV74030);"""
        if old in t:
            t = t.replace(old, new, 1)
            print("  * budget-vs")
        old = "TraceShaderTranslateV74030(\"pixel\", state, translateStartV74030, translatedV74030);"
        new = """TraceShaderTranslateV74030("pixel", state, translateStartV74030, translatedV74030);
        VulkanShaderCompileBudgetV7610.Note("pixel", state.Program.Address, translateStartV74030, translatedV74030);"""
        if old in t:
            t = t.replace(old, new, 1)
            print("  * budget-ps")
        old = "TraceShaderTranslateV74030(\"compute\", state, translateStartV74030, translatedV74030);"
        new = """TraceShaderTranslateV74030("compute", state, translateStartV74030, translatedV74030);
        VulkanShaderCompileBudgetV7610.Note("compute", state.Program.Address, translateStartV74030, translatedV74030);"""
        if old in t:
            t = t.replace(old, new, 1)
            print("  * budget-cs")
        p.write_text(t, encoding="utf-8")

print("[APPLY V76.0.10] done")
'@

$pyFile = Join-Path $env:TEMP "sharpemu_v7610.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }

Write-Host "Rebuild: cd `"$Root`"; dotnet build"
