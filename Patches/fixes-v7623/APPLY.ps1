param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$CodeRoot = $Root
if (Test-Path (Join-Path $Root "src\SharpEmu.Libs")) { $CodeRoot = Join-Path $Root "src" }
Write-Host "[APPLY V76.2.3 BINK] code=$CodeRoot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $CodeRoot "SharpEmu.Libs\Media\BinkDecodePolicyV7623.cs"
Copy-Item (Join-Path $ScriptDir "new\SharpEmu.Libs\Media\BinkDecodePolicyV7623.cs") $dst -Force
Write-Host "  + BinkDecodePolicyV7623.cs"

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

# Soften V7600 Initialize: do not force SHARPEMU_BINK_MODE=guest when hybrid wants host
patch(
"SharpEmu.Libs/Media/BinkGuestOwnedRuntimeV7600.cs",
'''        Set("SHARPEMU_BINK_MODE", "guest");
        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_BINK_BOOT_SEQUENCE", null);
        Set("SHARPEMU_BINK_NATIVE_PREFER", "0");
        Set("SHARPEMU_BINK_NATIVE_EXCLUSIVE", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_CPU", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");
        Set("SHARPEMU_BINK_HOST_AUDIO", "0");''',
'''        // V76.2.3: leave MODE/HOST_AUDIO alone when hybrid host decode is enabled.
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_ALLOW_HOST_DECODER"),
                "1",
                StringComparison.Ordinal))
        {
            Set("SHARPEMU_BINK_MODE", "guest");
            Set("SHARPEMU_BINK_HOST_AUDIO", "0");
        }
        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_BINK_BOOT_SEQUENCE", null);
        Set("SHARPEMU_BINK_NATIVE_PREFER", "0");
        Set("SHARPEMU_BINK_NATIVE_EXCLUSIVE", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_CPU", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");''',
"guest-init-hybrid")

# YUV producer: accept GPU-written images even if epoch registry missed a stamp
# (stale reject causes black frames while guest "decodes")
patch(
"SharpEmu.Libs/VideoOut/VulkanVideoPresenter.BinkGuestYuvV7612.cs",
'''            if (_v7612GuestBinkYuvProducerEpochs.TryGetValue(
                    (candidate.Address, candidate.Image.Handle),
                    out var producerEpoch) &&
                producerEpoch == epoch)
            {
                return true;
            }

            var reject = Interlocked.Increment(
                ref _v7612GuestBinkStaleProducerRejectCount);''',
'''            if (_v7612GuestBinkYuvProducerEpochs.TryGetValue(
                    (candidate.Address, candidate.Image.Handle),
                    out var producerEpoch) &&
                producerEpoch == epoch)
            {
                return true;
            }

            // V76.2.3: if the image was written this session (generation>0),
            // accept it — missing MarkGuestBinkYuvProducer caused false rejects
            // and black Bink output while GPU work continued slowly.
            if (candidate.ContentGeneration > 0)
            {
                _v7612GuestBinkYuvProducerEpochs[
                    (candidate.Address, candidate.Image.Handle)] = epoch;
                return true;
            }

            var reject = Interlocked.Increment(
                ref _v7612GuestBinkStaleProducerRejectCount);''',
"yuv-accept-generation")

# AV clock hold default 180 → 16 is set by policy env; also patch constant default if present
patch(
"SharpEmu.Libs/Media/BinkGuestAvClockV7613.cs",
'''            ? Math.Clamp(holdMs, 0, 500)
            : 180;''',
'''            ? Math.Clamp(holdMs, 0, 500)
            : 16; // V76.2.3: do not hold first frame ~180ms''',
"av-hold-16")

print("[APPLY V76.2.3 BINK] done")
'@
$pyFile = Join-Path $env:TEMP "sharpemu_v7623.py"
Set-Content $pyFile $py -Encoding UTF8
python $pyFile $CodeRoot
if ($LASTEXITCODE -ne 0) { py -3 $pyFile $CodeRoot }
Write-Host "Rebuild: cd `"$Root`"; dotnet build"
Write-Host "Runtime: expect [V76.2.3_BINK_HYBRID_HOST] host_decoder=on"
Write-Host "Pure guest: `$env:SHARPEMU_BINK_FORCE_GUEST='1'"
