param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Root)) { throw "Root not found: $Root" }
Write-Host "[V76.0.9 MAX] root=$Root"

function Write-New($Rel, $Content) {
  $dst = Join-Path $Root $Rel
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -LiteralPath $dst -Value $Content -Encoding UTF8
  Write-Host "  + $Rel"
}

# ===== Soft-fail =====
Write-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftFailV7609.cs" @'
using System.Collections.Concurrent;
using SharpEmu.ShaderCompiler;

namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static readonly bool SoftFailEnabled =
            !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_SHADER_SOFT_FAIL"), "0", StringComparison.Ordinal);
        private static readonly bool SoftFailTrace =
            string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_TRACE_SHADER_SOFT_FAIL"), "1", StringComparison.Ordinal);
        private static readonly ConcurrentDictionary<string, byte> SoftFailSeen = new(StringComparer.Ordinal);

        private bool TrySoftFailInstruction(Gen5ShaderInstruction instruction, string reason, out string error)
        {
            error = string.Empty;
            if (!SoftFailEnabled) { error = reason; return false; }
            if (SoftFailTrace)
            {
                var key = $"{_stage}:{instruction.Opcode}";
                if (SoftFailSeen.TryAdd(key, 0))
                    Console.Error.WriteLine($"[SHADER-SOFT-FAIL][V76.0.9] stage={_stage} pc=0x{instruction.Pc:X} op={instruction.Opcode} reason={reason}");
            }
            foreach (var dest in instruction.Destinations)
            {
                if (dest.Kind == Gen5OperandKind.VectorRegister) StoreV(dest.Value, UInt(0));
                else if (dest.Kind == Gen5OperandKind.ScalarRegister) StoreS(dest.Value, UInt(0));
            }
            return true;
        }
    }
}
'@

# ===== Compares / DPP / LDS / atomics =====
Write-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaExpandV7609.cs" @'
namespace SharpEmu.ShaderCompiler.Vulkan;

public static partial class Gen5SpirvTranslator
{
    private sealed partial class CompilationContext
    {
        private static SpirvOp MapExtraFloatCompare(string opcode) => opcode switch
        {
            "VCmpLtF16" or "VCmpxLtF16" => SpirvOp.FOrdLessThan,
            "VCmpEqF16" or "VCmpxEqF16" => SpirvOp.FOrdEqual,
            "VCmpLeF16" or "VCmpxLeF16" => SpirvOp.FOrdLessThanEqual,
            "VCmpGtF16" or "VCmpxGtF16" => SpirvOp.FOrdGreaterThan,
            "VCmpLgF16" or "VCmpxLgF16" => SpirvOp.FOrdNotEqual,
            "VCmpGeF16" or "VCmpxGeF16" => SpirvOp.FOrdGreaterThanEqual,
            "VCmpNeqF16" or "VCmpxNeqF16" => SpirvOp.FUnordNotEqual,
            "VCmpNltF16" or "VCmpxNltF16" => SpirvOp.FUnordGreaterThanEqual,
            "VCmpNleF16" or "VCmpxNleF16" => SpirvOp.FUnordGreaterThan,
            "VCmpNgtF16" or "VCmpxNgtF16" => SpirvOp.FUnordLessThanEqual,
            "VCmpNgeF16" or "VCmpxNgeF16" => SpirvOp.FUnordLessThan,
            "VCmpNlgF16" or "VCmpxNlgF16" => SpirvOp.FUnordEqual,
            _ => SpirvOp.Nop,
        };

        private static SpirvOp MapExtraIntegerCompare(string opcode) => opcode switch
        {
            "VCmpEqI64" or "VCmpxEqI64" or "VCmpEqU64" or "VCmpxEqU64" => SpirvOp.IEqual,
            "VCmpNeI64" or "VCmpxNeI64" or "VCmpNeU64" or "VCmpxNeU64" => SpirvOp.INotEqual,
            "VCmpLtI64" or "VCmpxLtI64" => SpirvOp.SLessThan,
            "VCmpLeI64" or "VCmpxLeI64" => SpirvOp.SLessThanEqual,
            "VCmpGtI64" or "VCmpxGtI64" => SpirvOp.SGreaterThan,
            "VCmpGeI64" or "VCmpxGeI64" => SpirvOp.SGreaterThanEqual,
            "VCmpLtU64" or "VCmpxLtU64" => SpirvOp.ULessThan,
            "VCmpLeU64" or "VCmpxLeU64" => SpirvOp.ULessThanEqual,
            "VCmpGtU64" or "VCmpxGtU64" => SpirvOp.UGreaterThan,
            "VCmpGeU64" or "VCmpxGeU64" => SpirvOp.UGreaterThanEqual,
            _ => SpirvOp.Nop,
        };

        private static bool IsSupportedDppControlV7609(uint control) =>
            control <= 0xFF ||
            control is >= 0x101 and <= 0x10F or >= 0x111 and <= 0x11F or
                >= 0x121 and <= 0x12F or >= 0x130 and <= 0x13F or
                0x140 or 0x141 or >= 0x150 and <= 0x15F or
                >= 0x160 and <= 0x16F or >= 0x1F0 and <= 0x1FF;

        private static SpirvOp MapExtraLdsAtomic(string opcode) => opcode switch
        {
            "DsAddU64" or "DsAddRtnU64" => SpirvOp.AtomicIAdd,
            "DsSubU64" or "DsSubRtnU64" => SpirvOp.AtomicISub,
            "DsMinI64" or "DsMinRtnI64" => SpirvOp.AtomicSMin,
            "DsMaxI64" or "DsMaxRtnI64" => SpirvOp.AtomicSMax,
            "DsMinU64" or "DsMinRtnU64" => SpirvOp.AtomicUMin,
            "DsMaxU64" or "DsMaxRtnU64" => SpirvOp.AtomicUMax,
            "DsAndB64" or "DsAndRtnB64" => SpirvOp.AtomicAnd,
            "DsOrB64" or "DsOrRtnB64" => SpirvOp.AtomicOr,
            "DsXorB64" or "DsXorRtnB64" => SpirvOp.AtomicXor,
            "DsWrxchgRtnB64" => SpirvOp.AtomicExchange,
            "DsCmpstB64" or "DsCmpstRtnB64" => SpirvOp.AtomicCompareExchange,
            "DsIncU64" or "DsIncRtnU64" => SpirvOp.AtomicIIncrement,
            "DsDecU64" or "DsDecRtnU64" => SpirvOp.AtomicIDecrement,
            _ => SpirvOp.Nop,
        };

        private static bool TryGetAtomicOpV7609(string name, out SpirvOp op)
        {
            op = name switch
            {
                "Swap" or "Xchg" or "Exchange" => SpirvOp.AtomicExchange,
                "Cmpswap" or "CmpSwap" or "CompareExchange" => SpirvOp.AtomicCompareExchange,
                "Add" => SpirvOp.AtomicIAdd,
                "Sub" => SpirvOp.AtomicISub,
                "Smin" or "SMin" => SpirvOp.AtomicSMin,
                "Umin" or "UMin" => SpirvOp.AtomicUMin,
                "Smax" or "SMax" => SpirvOp.AtomicSMax,
                "Umax" or "UMax" => SpirvOp.AtomicUMax,
                "And" => SpirvOp.AtomicAnd,
                "Or" => SpirvOp.AtomicOr,
                "Xor" => SpirvOp.AtomicXor,
                "Inc" => SpirvOp.AtomicIIncrement,
                "Dec" => SpirvOp.AtomicIDecrement,
                _ => SpirvOp.Nop,
            };
            return op != SpirvOp.Nop;
        }

        private void EmitStageBarrierV7609()
        {
            if (_stage == Gen5SpirvStage.Compute)
            {
                var wg = UInt(2); var sem = UInt(0x108);
                _module.AddStatement(SpirvOp.ControlBarrier, wg, wg, sem);
                return;
            }
            _module.AddStatement(SpirvOp.MemoryBarrier, UInt(1), UInt(0x48));
            if (_usesSubgroupOperations || _usesWaveControl)
            {
                var sg = UInt(3);
                _module.AddStatement(SpirvOp.ControlBarrier, sg, sg, UInt(0x48));
            }
        }
    }
}
'@

# ===== Bink handoff expand =====
Write-New "SharpEmu.Libs\Media\BinkHandoffMoviesV7609.cs" @'
namespace SharpEmu.Libs.Media;

internal static class BinkHandoffMoviesV7609
{
    private static readonly HashSet<string> Movies = new(StringComparer.OrdinalIgnoreCase)
    {
        "ps_studios_logo.bk2","playstation_studios_logo.bk2","SIE_logo.bk2",
        "attract.bk2","attract_movie.bk2","intro.bk2","opening.bk2","boot_movie.bk2","logo.bk2"
    };

    internal static bool ShouldArm(string? movieName)
    {
        if (string.IsNullOrWhiteSpace(movieName)) return false;
        if (string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_POST_STUDIOS_FRESH_FRAME_BARRIER"), "0", StringComparison.Ordinal))
            return false;
        var f = Path.GetFileName(movieName);
        return Movies.Contains(f) || f.Contains("logo", StringComparison.OrdinalIgnoreCase)
            || f.Contains("attract", StringComparison.OrdinalIgnoreCase);
    }
}
'@

# ===== Host frame pacer =====
Write-New "SharpEmu.Libs\VideoOut\HostFramePacerV7609.cs" @'
namespace SharpEmu.Libs.VideoOut;

internal static class HostFramePacerV7609
{
    private static readonly bool Enabled =
        !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_HOST_FRAME_PACER"), "0", StringComparison.Ordinal);
    private static readonly double TargetFps =
        double.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_HOST_TARGET_FPS"), out var fps)
            ? Math.Clamp(fps, 30.0, 120.0) : 60.0;
    private static readonly long PeriodTicks =
        (long)(System.Diagnostics.Stopwatch.Frequency / TargetFps);
    private static long _next;

    internal static void PaceBeforePresent()
    {
        if (!Enabled || PeriodTicks <= 0) return;
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var next = Interlocked.Read(ref _next);
        if (next == 0 || now > next + PeriodTicks * 2)
        {
            Interlocked.Exchange(ref _next, now + PeriodTicks);
            return;
        }
        if (now < next)
        {
            var remainMs = (next - now) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
            if (remainMs >= 1.0)
            {
                var sleepMs = Math.Max(0, (int)(remainMs - 0.3));
                if (sleepMs > 0) Thread.Sleep(sleepMs);
                while (System.Diagnostics.Stopwatch.GetTimestamp() < next) Thread.SpinWait(32);
            }
            Interlocked.Exchange(ref _next, next + PeriodTicks);
            return;
        }
        Interlocked.Exchange(ref _next, now + PeriodTicks);
    }
}
'@

# ===== Python patches =====
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

# Bink 60
patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 30;""",
"""            ? Math.Clamp(binkTargetFps, 1, 120)
            : 60; // V76.0.9""",
"bink-60")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 8;""",
"""            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 12; // V76.0.9""",
"bink-catchup-frames")

patch("SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 6));""",
"""                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 10)); // V76.0.9""",
"bink-catchup-budget")

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
            IsSupportedDppControlV7609(control);""",
"dpp")

# Float / int compares
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
                    _ => MapExtraFloatCompare(opcode),
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
                    _ => MapExtraIntegerCompare(opcode),
                };
                if (operation == SpirvOp.Nop)
                {
                    error = $"unsupported integer compare {opcode}";
                    return false;
                }""",
"int-i64")

# Vector soft-fail
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.Alu.cs",
"""                default:
                    error = $"unsupported vector opcode {instruction.Opcode}";
                    return false;
            }""",
"""                default:
                    if (TrySoftFailInstruction(instruction, $"unsupported vector opcode {instruction.Opcode}", out error))
                        return true;
                    return false;
            }""",
"vector-soft")

# Image soft-fail
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                error = $"unsupported image opcode {instruction.Opcode}";
                return false;
            }""",
"""                if (TrySoftFailInstruction(instruction, $"unsupported image opcode {instruction.Opcode}", out error))
                    return true;
                return false;
            }""",
"image-soft")

# Storage image soft-fail (all occurrences)
p = root / "SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    old = 'error = $"unsupported storage image opcode {instruction.Opcode}";\n                return false;'
    new = 'if (TrySoftFailInstruction(instruction, $"unsupported storage image opcode {instruction.Opcode}", out error))\n                    return true;\n                return false;'
    old2 = 'error = $"unsupported storage image opcode {instruction.Opcode}";\n                    return false;'
    new2 = 'if (TrySoftFailInstruction(instruction, $"unsupported storage image opcode {instruction.Opcode}", out error))\n                        return true;\n                    return false;'
    n = t.count(old) + t.count(old2)
    t = t.replace(old, new).replace(old2, new2)
    p.write_text(t, encoding="utf-8")
    print(f"  * storage-image-soft x{n}" if n else "  ! storage-image-soft")

# LDS soft + extra atomics in switch default
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
                _ => MapExtraLdsAtomic(instruction.Opcode),
            };
            if (atomicOp == SpirvOp.Nop)
            {
                if (TrySoftFailInstruction(instruction, $"unsupported LDS opcode {instruction.Opcode}", out error))
                    return true;
                return false;
            }""",
"lds-atomic-soft")

# LDS non-atomic default soft-fail
patch("SharpEmu.ShaderCompiler.Vulkan/Gen5SpirvTranslator.cs",
"""                    error = $"unsupported LDS opcode {instruction.Opcode}";
                    return false;
            }
        }

        private static uint EffectiveDsPairOffsetBytes""",
"""                    if (TrySoftFailInstruction(instruction, $"unsupported LDS opcode {instruction.Opcode}", out error))
                        return true;
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
"""            if (TryGetAtomicOpV7609(name, out op))
                return true;
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
                EmitStageBarrierV7609();
                return true;
            }""",
"sbarrier")

# Bink handoff
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
        // V76.0.9: expanded intro/attract/logo set
        if (!SharpEmu.Libs.Media.BinkHandoffMoviesV7609.ShouldArm(fileName))
        {
            return;
        }""",
"bink-handoff")

# Host pacer before QueuePresent
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "HostFramePacerV7609.PaceBeforePresent()" in t:
        print("  = already pacer")
    else:
        for pat in ("_swapchainApi.QueuePresent(", "QueuePresentKHR("):
            idx = t.find(pat)
            if idx >= 0:
                ls = t.rfind("\n", 0, idx) + 1
                ind = re.match(r"[ \t]*", t[ls:idx]).group(0)
                t = t[:ls] + f"{ind}HostFramePacerV7609.PaceBeforePresent();\n" + t[ls:]
                p.write_text(t, encoding="utf-8")
                print("  * host-pacer")
                break
        else:
            print("  ! host-pacer")

print("[V76.0.9 MAX] done")
'@

$pyFile = Join-Path $env:TEMP "sharpemu_v7609.py"
Set-Content -Path $pyFile -Value $py -Encoding UTF8
python $pyFile $Root
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $Root }

Write-Host ""
Write-Host "Next:  cd `"$Root`";  dotnet build"
Write-Host "Env: SHARPEMU_SHADER_SOFT_FAIL=1 (default), SHARPEMU_TRACE_SHADER_SOFT_FAIL=1, SHARPEMU_HOST_FRAME_PACER=1"