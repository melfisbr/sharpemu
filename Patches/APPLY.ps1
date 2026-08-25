# Apply SharpEmu V76.0.2 fixes (Windows / PowerShell)
# Usage: .\APPLY.ps1 -Root "C:\Users\Edpo\Documents\GitHub\sharpemu"
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root not found: $Root"
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "[APPLY] root=$Root"

function Copy-New([string]$Rel) {
    $src = Join-Path $ScriptDir "new\$Rel"
    $dst = Join-Path $Root $Rel
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  + $Rel"
}

Copy-New "SharpEmu.ShaderCompiler.Vulkan\SpirvShaderDiskCache.cs"
Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.FixesV7602.cs"
Copy-New "SharpEmu.Libs\VideoOut\HostFramePacerV7602.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanVideoPresenter.FixesV7602.cs"
Copy-New "SharpEmu.Libs\Media\BinkVulkanPacingV7602.cs"

$py = @'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    if not p.exists():
        print(f"  ! missing {path}")
        return False
    text = p.read_text(encoding="utf-8")
    if new in text and old not in text:
        print(f"  = already applied: {label}")
        return True
    if old not in text:
        print(f"  ! pattern not found: {label}")
        return False
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  * patched: {label}")
    return True

patch(
    "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
    """    private static readonly int _binkTargetFps =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_TARGET_FPS"),
            out var binkTargetFps)
            ? Math.Clamp(binkTargetFps, 1, 120)
            : 30;""",
    """    private static readonly int _binkTargetFps =
        int.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_TARGET_FPS"),
            out var binkTargetFps)
            ? Math.Clamp(binkTargetFps, 1, 120)
            : 60; // V76.0.2: default 60 fps for Bink on Vulkan""",
    "bink-default-60fps",
)

patch(
    "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
    """        private static bool IsSupportedDppControl(uint control) =>
            control <= 0xFF ||
            control is >= 0x101 and <= 0x10F or
                >= 0x111 and <= 0x11F or
                >= 0x121 and <= 0x12F or
                0x140 or 0x141 or
                >= 0x150 and <= 0x15F or
                >= 0x160 and <= 0x16F;""",
    """        private static bool IsSupportedDppControl(uint control) =>
            IsSupportedDppControlV7602(control);""",
    "dpp16-expand",
)

patch(
    "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
    """                    "VCmpNlgF32" or "VCmpxNlgF32" => SpirvOp.FUnordEqual,
                    _ => SpirvOp.Nop,
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported float compare {opcode}";
                    return false;
                }""",
    """                    "VCmpNlgF32" or "VCmpxNlgF32" => SpirvOp.FUnordEqual,
                    _ => MapExtraFloatCompare(opcode),
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported float compare {opcode}";
                    return false;
                }""",
    "float-compare-f16",
)

patch(
    "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
    """                    "VCmpGeU32" or "VCmpxGeU32" => SpirvOp.UGreaterThanEqual,
                    _ => SpirvOp.Nop,
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported integer compare {opcode}";
                    return false;
                }""",
    """                    "VCmpGeU32" or "VCmpxGeU32" => SpirvOp.UGreaterThanEqual,
                    _ => MapExtraIntegerCompare(opcode),
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported integer compare {opcode}";
                    return false;
                }""",
    "integer-compare-i64",
)

patch(
    "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
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
    """            if (TryGetAtomicOpV7602(name, out op))
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
    "buffer-atomic-aliases",
)

patch(
    "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
    """                "DsCmpstB32" or "DsCmpstRtnB32" => SpirvOp.AtomicCompareExchange,
                _ => SpirvOp.Nop,
            };
            if (atomicOp == SpirvOp.Nop)
            {
                error = $"unsupported LDS opcode {instruction.Opcode}";
                return false;
            }""",
    """                "DsCmpstB32" or "DsCmpstRtnB32" => SpirvOp.AtomicCompareExchange,
                _ => MapExtraLdsAtomic(instruction.Opcode),
            };
            if (atomicOp == SpirvOp.Nop)
            {
                error = $"unsupported LDS opcode {instruction.Opcode}";
                return false;
            }""",
    "lds-atomic-expand",
)

patch(
    "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.BinkHandoffBarrierV31722.cs",
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
        // V76.0.2: arm for intro/attract/logo family, not only ps_studios_logo.bk2
        if (!ShouldArmPostStudiosBarrierV7602(fileName))
        {
            return;
        }""",
    "bink-handoff-movies",
)

presenter = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if presenter.exists():
    text = presenter.read_text(encoding="utf-8")
    marker = "PaceHostPresentV7602();"
    if marker in text:
        print("  = already applied: host-frame-pacer-call")
    else:
        inserted = False
        for pat in ("var presentResult = _swapchainApi.QueuePresent(", "_swapchainApi.QueuePresent(", "QueuePresentKHR("):
            idx = text.find(pat)
            if idx >= 0:
                line_start = text.rfind("\n", 0, idx) + 1
                indent = re.match(r"[ \t]*", text[line_start:idx]).group(0)
                text = text[:line_start] + f"{indent}PaceHostPresentV7602();\n" + text[line_start:]
                presenter.write_text(text, encoding="utf-8")
                print(f"  * patched: host-frame-pacer-call (before {pat.strip()})")
                inserted = True
                break
        if not inserted:
            print("  ! pattern not found: host-frame-pacer-call (manual wire-up needed)")

backend = root / "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs"
if backend.exists():
    text = backend.read_text(encoding="utf-8")
    if "SpirvShaderDiskCache.StatusLine" in text:
        print("  = already applied: spirv-cache-status-log")
    else:
        needle = 'public string BackendName => "Vulkan";'
        if needle in text:
            text = text.replace(
                needle,
                needle + """

    static VulkanGuestGpuBackend()
    {
        // V76.0.2: surface SPIR-V disk cache status once per process.
        Console.Error.WriteLine(SpirvShaderDiskCache.StatusLine());
    }""",
                1,
            )
            backend.write_text(text, encoding="utf-8")
            print("  * patched: spirv-cache-status-log")
        else:
            print("  ! pattern not found: spirv-cache-status-log")

print("[APPLY] done")
'@

$pyFile = Join-Path $env:TEMP "sharpemu_apply_v7602.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $Root
if ($LASTEXITCODE -ne 0) {
    # fallback: py launcher
    py -3 $pyFile $Root
}

Write-Host "[APPLY] complete. Rebuild with:"
Write-Host "  cd `"$Root`""
Write-Host "  dotnet build"
