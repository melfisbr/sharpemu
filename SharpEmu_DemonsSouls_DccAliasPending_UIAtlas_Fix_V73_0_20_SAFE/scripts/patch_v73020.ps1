param(
    [Parameter(Mandatory=$true)][string]$PresenterPath,
    [Parameter(Mandatory=$true)][string]$AgcPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Replace-RegexOnce {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$Replacement,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $rx=[Text.RegularExpressions.Regex]::new(
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches=$rx.Matches($Text)
    if($matches.Count -ne 1){
        throw ("{0}: expected 1 match, found {1}." -f $Label,$matches.Count)
    }

    return $rx.Replace(
        $Text,
        [Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $Replacement
        },
        1
    )
}

if(-not [IO.File]::Exists($PresenterPath)){
    throw "Presenter missing: $PresenterPath"
}
if(-not [IO.File]::Exists($AgcPath)){
    throw "AgcExports missing: $AgcPath"
}

$presenter=[IO.File]::ReadAllText($PresenterPath)
$agc=[IO.File]::ReadAllText($AgcPath)

# ============================================================================
# Presenter: make the sparse probe truly size-independent.
# The V73.0.19.1 result proved the 80-layer / 320 MiB array never gets a
# baseline because TryBuildUntrackedTextureProbe rejects byteCount above the
# normal tracked-image budget. The probe itself reads only 8 x 64 bytes.
# ============================================================================

if(-not $presenter.Contains(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20'))
{
    $probeGuardPattern=@'
if\s*\(\s*texture\.Address\s*==\s*0\s*\|\|\s*
\s*byteCount\s*==\s*0\s*\|\|\s*
\s*byteCount\s*>\s*MaxTrackedGuestImageBytes\s*\)
'@

    $probeGuardReplacement=@'
if (texture.Address == 0 ||
            byteCount == 0)
'@

    $presenter=Replace-RegexOnce `
        $presenter `
        $probeGuardPattern `
        $probeGuardReplacement `
        'large-sparse-probe-guard'

    $missingBaselinePattern=@'
if\s*\(\s*!_untrackedTextureCacheProbes\.TryGetValue\(
\s*identity\s*,\s*out\s+var\s+previous\s*\)\s*\)\s*
\{\s*
.*?"missing-baseline"\s*\)\s*;\s*
return\s+false\s*;\s*
\}
'@

    $missingBaselineReplacement=@'
if (!_untrackedTextureCacheProbes.TryGetValue(identity, out var previous))
        {
            // SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20
            // Sparse probing reads only 512 guest bytes regardless of the
            // logical resource size. Do not evict a 320 MiB array every frame
            // just because it exceeds the ordinary tracked-image byte budget.
            var memory = _guestMemory;
            var byteCount = GetTextureContentProbeByteCount(identity);
            if (memory is null || byteCount == 0)
            {
                return true;
            }

            previous = new UntrackedTextureCacheProbe(
                ComputeSparseGuestContentProbe(
                    memory,
                    identity.Address,
                    byteCount),
                byteCount);
            _untrackedTextureCacheProbes.TryAdd(identity, previous);

            Console.Error.WriteLine(
                $"[V73.0.20][LARGE_PROBE_SEEDED] " +
                $"addr=0x{identity.Address:X16} bytes={byteCount} " +
                $"size={identity.Width}x{identity.Height} " +
                $"layers={identity.ArrayLayers}");
        }
'@

    $presenter=Replace-RegexOnce `
        $presenter `
        $missingBaselinePattern `
        $missingBaselineReplacement `
        'large-sparse-probe-seed'
}

# ============================================================================
# AGC: DCC metadata alias must survive the queued-producer interval.
#
# Before V73.0.20 TryResolveDccMetadataAlias discarded every metadata/shape
# match whose VkImage was not resident yet. If the matching render target was
# queued but not executed, TryCreateGuestDrawTexture fell through toward a CPU
# snapshot of DCC-compressed guest RAM. Newer SharpEmu correctly suppresses
# that untrustworthy snapshot, but then the texture is effectively black.
#
# Select the newest matching DCC producer even while pending. Prefer a resident
# candidate when available. Then force the existing gpuWriterPending
# reference-only path for the resolved alias.
# ============================================================================

if(-not $agc.Contains(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20'))
{
    $foundPattern=@'
var\s+found\s*=\s*false\s*;
'@
    $foundReplacement=@'
var found = false;
        var foundResident = false;
'@
    $agc=Replace-RegexOnce `
        $agc `
        $foundPattern `
        $foundReplacement `
        'dcc-found-resident-state'

    $candidatePattern=@'
if\s*\(\s*!GuestGpu\.Current\.IsGpuGuestImageAvailable\(
\s*candidate\.Address\s*,\s*
candidate\.Format\s*,\s*
candidate\.NumberType\s*\)\s*\)\s*
\{\s*
continue\s*;\s*
\}\s*
residentMatches\+\+\s*;\s*
var\s+sequence\s*=\s*drawState\.RenderTargetWriters\.TryGetValue\(
\s*candidate\.Address\s*,\s*
out\s+var\s+writer\s*\)\s*
\?\s*writer\.Sequence\s*
:\s*0UL\s*;\s*
if\s*\(\s*!found\s*\|\|\s*sequence\s*>=\s*writerSequence\s*\)\s*
\{\s*
alias\s*=\s*candidate\s*;\s*
writerSequence\s*=\s*sequence\s*;\s*
found\s*=\s*true\s*;\s*
\}
'@

    $candidateReplacement=@'
var resident =
                GuestGpu.Current.IsGpuGuestImageAvailable(
                    candidate.Address,
                    candidate.Format,
                    candidate.NumberType);
            if (resident)
            {
                residentMatches++;
            }

            var sequence = drawState.RenderTargetWriters.TryGetValue(
                    candidate.Address,
                    out var writer)
                ? writer.Sequence
                : 0UL;

            // SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20
            // Keep a metadata/shape-compatible render target even when its
            // Vulkan image is not resident yet. Prefer resident aliases; among
            // equal residency states choose the newest observed writer.
            if (!found ||
                resident && !foundResident ||
                resident == foundResident && sequence >= writerSequence)
            {
                alias = candidate;
                writerSequence = sequence;
                found = true;
                foundResident = resident;
            }
'@

    $agc=Replace-RegexOnce `
        $agc `
        $candidatePattern `
        $candidateReplacement `
        'dcc-pending-candidate-selection'

    $originalAddressPattern=@'
var\s+originalDescriptorAddress\s*=\s*descriptor\.Address\s*;
'@
    $originalAddressReplacement=@'
var originalDescriptorAddress = descriptor.Address;
        var resolvedDccAlias = false;
'@
    $agc=Replace-RegexOnce `
        $agc `
        $originalAddressPattern `
        $originalAddressReplacement `
        'dcc-resolved-alias-state'

    $aliasAssignmentPattern=@'
descriptor\s*=\s*descriptor\s+with\s*\{\s*Address\s*=\s*dccAlias\.Address\s*\}\s*;
'@
    $aliasAssignmentReplacement=@'
resolvedDccAlias = true;
                descriptor = descriptor with { Address = dccAlias.Address };
'@
    $agc=Replace-RegexOnce `
        $agc `
        $aliasAssignmentPattern `
        $aliasAssignmentReplacement `
        'dcc-resolved-alias-flag'

    $residentWriterPattern=@'
var\s+gpuResidentWriterImage\s*=\s*
preferGpuResident\s*&&
'@
    $residentWriterReplacement=@'
var gpuResidentWriterImage =
            (preferGpuResident || resolvedDccAlias) &&
'@
    $agc=Replace-RegexOnce `
        $agc `
        $residentWriterPattern `
        $residentWriterReplacement `
        'dcc-resident-writer-gate'

    $pendingWriterPattern=@'
var\s+gpuWriterPending\s*=\s*
preferGpuResident\s*&&
'@
    $pendingWriterReplacement=@'
var gpuWriterPending =
            (preferGpuResident || resolvedDccAlias) &&
'@
    $agc=Replace-RegexOnce `
        $agc `
        $pendingWriterPattern `
        $pendingWriterReplacement `
        'dcc-pending-writer-gate'

    $pendingBlockPattern=@'
if\s*\(\s*gpuWriterPending\s*\)\s*
\{\s*
if\s*\(\s*_traceAgcShader\s*\)
'@
    $pendingBlockReplacement=@'
if (gpuWriterPending)
        {
            if (resolvedDccAlias &&
                _traceDccAlias &&
                Interlocked.Increment(ref _dccAliasTraceCount) <= 512)
            {
                Console.Error.WriteLine(
                    $"[V73.0.20][DCC_ALIAS_PENDING] " +
                    $"sample=0x{originalDescriptorAddress:X16} " +
                    $"alias=0x{descriptor.Address:X16} " +
                    $"meta=0x{descriptor.MetadataAddress:X16} " +
                    $"size={descriptor.Width}x{descriptor.Height} " +
                    $"fmt={descriptor.Format}/{descriptor.NumberType}; " +
                    $"reference-only");
            }

            if (_traceAgcShader)
'@
    $agc=Replace-RegexOnce `
        $agc `
        $pendingBlockPattern `
        $pendingBlockReplacement `
        'dcc-pending-trace'
}

# Final invariants.
foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20',
    '[V73.0.20][LARGE_PROBE_SEEDED]'
)){
    if(-not $presenter.Contains($marker)){
        throw "Presenter post-patch marker missing: $marker"
    }
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20',
    'var resolvedDccAlias = false;',
    '(preferGpuResident || resolvedDccAlias)',
    '[V73.0.20][DCC_ALIAS_PENDING]'
)){
    if(-not $agc.Contains($marker)){
        throw "AGC post-patch marker missing: $marker"
    }
}

[IO.File]::WriteAllText(
    $PresenterPath,
    $presenter,
    [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText(
    $AgcPath,
    $agc,
    [Text.UTF8Encoding]::new($false))

Write-Host '[V73.0.20] DCC pending-alias + large sparse-probe patch applied.' -ForegroundColor Green
