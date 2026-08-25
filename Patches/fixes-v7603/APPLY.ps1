param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Root)) { Write-Error "Root not found: $Root"; exit 1 }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "[APPLY V76.0.3] root=$Root"

function Copy-New([string]$Rel) {
    $src = Join-Path $ScriptDir "new\$Rel"
    $dst = Join-Path $Root $Rel
    if (-not (Test-Path $src)) { Write-Host "  ! missing source $Rel"; return }
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  + $Rel"
}

Copy-New "SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.CacheV7603.cs"
Copy-New "SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.CacheV7603.cs"
Copy-New "SharpEmu.Libs\Media\BinkCatchupV7603.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanPresentDiagnosticsV7603.cs"

$py = @'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def patch(path, old, new, label):
    p = root / path
    if not p.exists():
        print(f"  ! missing {path}"); return
    t = p.read_text(encoding="utf-8")
    if new.strip() in t and old not in t:
        print(f"  = already {label}"); return
    if old not in t:
        print(f"  ! not found {label}"); return
    p.write_text(t.replace(old, new, 1), encoding="utf-8")
    print(f"  * {label}")

# Wire cached compiles in Vulkan backend
patch(
    "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
    "        var translatedV74030 = Gen5SpirvTranslator.TryCompileVertexShader(\n                state,\n                evaluation,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                requiredVertexOutputCount,\n                storageBufferOffsetAlignment);",
    "        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompileVertexCached(\n                state,\n                evaluation,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                requiredVertexOutputCount,\n                storageBufferOffsetAlignment);",
    "vs-cache",
)

patch(
    "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
    "        var translatedV74030 = Gen5SpirvTranslator.TryCompilePixelShader(\n                state,\n                evaluation,\n                outputs,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                pixelInputEnable,\n                pixelInputAddress,\n                pixelInputCntl,\n                storageBufferOffsetAlignment);",
    "        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompilePixelCached(\n                state,\n                evaluation,\n                outputs,\n                out var compiled,\n                out error,\n                globalBufferBase,\n                totalGlobalBufferCount,\n                imageBindingBase,\n                scalarRegisterBufferIndex,\n                pixelInputEnable,\n                pixelInputAddress,\n                pixelInputCntl,\n                storageBufferOffsetAlignment);",
    "ps-cache",
)

patch(
    "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs",
    "        var translatedV74030 = Gen5SpirvTranslator.TryCompileComputeShader(\n                state,\n                evaluation,\n                localSizeX,\n                localSizeY,\n                localSizeZ,\n                out var compiled,\n                out error,\n                totalGlobalBufferCount,\n                initialScalarBufferIndex,\n                waveLaneCount,\n                storageBufferOffsetAlignment);",
    "        var translatedV74030 = VulkanShaderCompileCacheV7603.TryCompileComputeCached(\n                state,\n                evaluation,\n                localSizeX,\n                localSizeY,\n                localSizeZ,\n                out var compiled,\n                out error,\n                totalGlobalBufferCount,\n                initialScalarBufferIndex,\n                waveLaneCount,\n                storageBufferOffsetAlignment);",
    "cs-cache",
)

# Bink catchup defaults 8->12 and 6->10
patch(
    "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
    """            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 8;""",
    """            ? Math.Clamp(binkCatchupMaxFrames, 1, 32)
            : 12; // V76.0.3""",
    "bink-catchup-frames",
)

patch(
    "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs",
    """                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 6));""",
    """                ? Math.Clamp(binkCatchupBudgetMs, 1, 50)
                : 10)); // V76.0.3""",
    "bink-catchup-budget",
)

# Present diagnostics after pacer call if present
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "VulkanPresentDiagnosticsV7603.NotePresent()" in t:
        print("  = already present-diag")
    elif "PaceHostPresentV7602();" in t:
        t = t.replace(
            "PaceHostPresentV7602();",
            "PaceHostPresentV7602();\n                    VulkanPresentDiagnosticsV7603.NotePresent();",
            1,
        )
        p.write_text(t, encoding="utf-8")
        print("  * present-diag")
    else:
        # insert before QueuePresent
        needle = "_swapchainApi.QueuePresent("
        idx = t.find(needle)
        if idx >= 0:
            line_start = t.rfind("\n", 0, idx) + 1
            indent = ""
            while line_start + len(indent) < len(t) and t[line_start + len(indent)] in " \t":
                indent += t[line_start + len(indent)]
            t = t[:line_start] + f"{indent}VulkanPresentDiagnosticsV7603.NotePresent();\n" + t[line_start:]
            p.write_text(t, encoding="utf-8")
            print("  * present-diag (queue)")
        else:
            print("  ! present-diag not wired")

# Log cache status from backend static ctor if exists
p = root / "SharpEmu.Libs/Gpu/Vulkan/VulkanGuestGpuBackend.cs"
if p.exists():
    t = p.read_text(encoding="utf-8")
    if "ResultCacheStatusLine" in t:
        print("  = already cache-status")
    elif "SpirvShaderDiskCache.StatusLine()" in t:
        t = t.replace(
            "Console.Error.WriteLine(SpirvShaderDiskCache.StatusLine());",
            "Console.Error.WriteLine(SpirvShaderDiskCache.StatusLine());\n        Console.Error.WriteLine(Gen5SpirvTranslator.ResultCacheStatusLine());",
            1,
        )
        p.write_text(t, encoding="utf-8")
        print("  * cache-status")
    else:
        needle = 'public string BackendName => "Vulkan";'
        if needle in t:
            t = t.replace(needle, needle + """

    static VulkanGuestGpuBackend()
    {
        Console.Error.WriteLine(Gen5SpirvTranslator.ResultCacheStatusLine());
    }""", 1)
            p.write_text(t, encoding="utf-8")
            print("  * cache-status-ctor")

print("[APPLY V76.0.3] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7603.py"
Set-Content -LiteralPath $pyFile -Value $py -Encoding UTF8
python $pyFile $Root
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $Root }

Write-Host "[APPLY] Rebuild:"
Write-Host "  cd `"$Root`""
Write-Host "  dotnet build"
