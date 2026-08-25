param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.2.2 QUEUE] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Copy-New($Rel) {
  $s = Join-Path $ScriptDir "new\$Rel"
  $d = Join-Path $CodeRoot $Rel
  $dir = Split-Path $d -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $s $d -Force
  Write-Host "  + $Rel"
}
Copy-New "SharpEmu.Libs\VideoOut\VulkanQueueOptimizerV7622.cs"
Copy-New "SharpEmu.Libs\VideoOut\VulkanQueueSubmitHooksV7622.cs"

$py = @'
import pathlib, sys, re
root = pathlib.Path(sys.argv[1])
p = root / "SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs"
if not p.exists():
    print("  ! missing VulkanVideoPresenter.cs"); raise SystemExit(1)
t = p.read_text(encoding="utf-8")

def insert_before(pat, line, label):
    global t
    if line.strip() in t and label in t:
        print("  = already", label)
        return
    idx = t.find(pat)
    if idx < 0:
        print("  ! not found", label, pat[:40])
        return
    ls = t.rfind("\n", 0, idx) + 1
    ind = re.match(r"[ \t]*", t[ls:idx]).group(0)
    t = t[:ls] + ind + line + "\n" + t[ls:]
    print("  *", label)

# Present path
if "VulkanQueueSubmitHooksV7622.NotePresented()" not in t:
    for pat in (
        "HostFramePacerV7617.PaceBeforePresent();",
        "HostFramePacerV7609.PaceBeforePresent();",
        "VulkanSubmitThrottleV7610.OnPresented();",
        "VulkanFrameStatsV7604.NoteFrameEnd();",
    ):
        if pat in t:
            t = t.replace(pat, pat + "\n                    VulkanQueueSubmitHooksV7622.NotePresented();", 1)
            print("  * present-hook via", pat.split("(")[0])
            break
    else:
        # QueuePresent
        insert_before("_swapchainApi.QueuePresent(", "VulkanQueueSubmitHooksV7622.NotePresented();", "present-hook-qp")
else:
    print("  = already present-hook")

# Graphics QueueSubmit — first few QueueSubmit calls get graphics note
# Prefer explicit patterns used in presenter
count_gfx = 0
if "VulkanQueueSubmitHooksV7622.NoteGraphicsSubmit()" not in t:
    # Insert before common submit API usage
    for pat in ("_deviceApi.QueueSubmit(", "vk.QueueSubmit(", "QueueSubmit("):
        # only first 3 graphics-looking occurrences that aren't compute
        start = 0
        while count_gfx < 2:
            idx = t.find(pat, start)
            if idx < 0:
                break
            # skip if recent context has "compute"
            ctx = t[max(0, idx-200):idx].lower()
            ls = t.rfind("\n", 0, idx) + 1
            ind = re.match(r"[ \t]*", t[ls:idx]).group(0)
            if "compute" in ctx:
                hook = ind + "VulkanQueueSubmitHooksV7622.NoteComputeSubmit();\n"
            else:
                hook = ind + "VulkanQueueSubmitHooksV7622.NoteGraphicsSubmit();\n"
                count_gfx += 1
            t = t[:ls] + hook + t[ls:]
            start = ls + len(hook) + 20
        if count_gfx:
            print(f"  * submit-hooks gfx~{count_gfx}")
            break
    if not count_gfx:
        print("  ! no QueueSubmit patterns — optimizer present-only")
else:
    print("  = already submit-hooks")

# Adaptive guest burst: replace hard-coded safe burst default site if present
old_burst = """            : 8; // SHARPEMU_V74_0_94_1_SAFE_QUEUE_BURST_DEFAULT"""
# Can't easily replace static readonly with method call without more context.
# Document env instead.

p.write_text(t, encoding="utf-8")
print("[APPLY V76.2.2 QUEUE] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7622.py"
Set-Content $pyFile $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
Write-Host "Env: SHARPEMU_QUEUE_OPTIMIZER=1 SHARPEMU_QUEUE_MAX_INFLIGHT=3 SHARPEMU_TRACE_QUEUE_OPTIMIZER=1"
