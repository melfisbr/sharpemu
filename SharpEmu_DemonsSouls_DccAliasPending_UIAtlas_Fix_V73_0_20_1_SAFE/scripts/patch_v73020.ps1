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

function Get-Region {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Start,
        [Parameter(Mandatory=$true)][string]$End,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $startIndex=$Text.IndexOf($Start,[StringComparison]::Ordinal)
    if($startIndex -lt 0){
        throw ("{0}: start marker not found." -f $Label)
    }

    $endIndex=$Text.IndexOf(
        $End,
        $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if($endIndex -lt 0){
        throw ("{0}: end marker not found." -f $Label)
    }

    [PSCustomObject]@{
        Start=$startIndex
        End=$endIndex
        Text=$Text.Substring($startIndex,$endIndex-$startIndex)
    }
}

function Put-Region {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)]$Region,
        [Parameter(Mandatory=$true)][string]$Replacement
    )

    return $Text.Substring(0,$Region.Start)+
        $Replacement+
        $Text.Substring($Region.End)
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
# Presenter: the V73.0.19.1 sparse probe reads only 8 x 64 bytes. The old
# MaxTrackedGuestImageBytes guard incorrectly prevented creation of a baseline
# for the 1024x1024x80 UI/atlas array (~320 MiB), causing missing-baseline
# eviction and a 320 MiB reupload every frame.
# ============================================================================

if(-not $presenter.Contains(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_1'))
{
    $probeRegion=Get-Region `
        $presenter `
        '    private static bool TryBuildUntrackedTextureProbe(' `
        '    private static ulong ComputeSparseSubmittedContentProbe(' `
        'TryBuildUntrackedTextureProbe'

    $probe=$probeRegion.Text
    $probe=Replace-RegexOnce `
        $probe `
        'probe\s*=\s*default\s*;\s*if\s*\(\s*texture\.Address\s*==\s*0\s*\|\|\s*byteCount\s*==\s*0\s*\|\|\s*byteCount\s*>\s*MaxTrackedGuestImageBytes\s*\)' `
        @'
probe = default;

        // SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_1
        // The probe samples only 512 bytes. Logical image size must not disable
        // it; doing so made the 320 MiB / 80-layer UI array churn every frame.
        if (texture.Address == 0 ||
            byteCount == 0)
'@ `
        'large-sparse-probe-guard'

    $presenter=Put-Region $presenter $probeRegion $probe

    $markRegion=Get-Region `
        $presenter `
        '    private static void MarkTextureContentCached(' `
        '    private static void UnmarkTextureContentCached(' `
        'MarkTextureContentCached'

    $mark=$markRegion.Text
    $mark=Replace-RegexOnce `
        $mark `
        '_untrackedTextureCacheProbes\s*\[\s*identity\s*\]\s*=\s*probe\s*;' `
        @'
_untrackedTextureCacheProbes[identity] = probe;

        if (probe.ByteCount > MaxTrackedGuestImageBytes)
        {
            Console.Error.WriteLine(
                $"[V73.0.20.1][LARGE_PROBE_SEEDED] " +
                $"addr=0x{identity.Address:X16} bytes={probe.ByteCount} " +
                $"size={identity.Width}x{identity.Height} " +
                $"layers={identity.ArrayLayers}");
        }
'@ `
        'large-probe-seeded-trace'

    $presenter=Put-Region $presenter $markRegion $mark
}

# ============================================================================
# AGC: keep DCC metadata aliases even when the matching render-target producer
# has been observed but the Vulkan image is not resident yet.
# ============================================================================

if(-not $agc.Contains(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_1'))
{
    $resolveRegion=Get-Region `
        $agc `
        '    private static bool TryResolveDccMetadataAlias(' `
        '    private static bool TryCreateGuestDrawTexture(' `
        'TryResolveDccMetadataAlias'

    $resolve=$resolveRegion.Text

    $resolve=Replace-RegexOnce `
        $resolve `
        'var\s+found\s*=\s*false\s*;' `
        @'
var found = false;
        var foundResident = false;
'@ `
        'dcc-found-resident'

    $resolve=Replace-RegexOnce `
        $resolve `
        'if\s*\(\s*!GuestGpu\.Current\.IsGpuGuestImageAvailable\(\s*candidate\.Address\s*,\s*candidate\.Format\s*,\s*candidate\.NumberType\s*\)\s*\)\s*\{\s*continue\s*;\s*\}\s*residentMatches\+\+\s*;\s*var\s+sequence\s*=\s*drawState\.RenderTargetWriters\.TryGetValue\(\s*candidate\.Address\s*,\s*out\s+var\s+writer\s*\)\s*\?\s*writer\.Sequence\s*:\s*0UL\s*;\s*if\s*\(\s*!found\s*\|\|\s*sequence\s*>=\s*writerSequence\s*\)\s*\{\s*alias\s*=\s*candidate\s*;\s*writerSequence\s*=\s*sequence\s*;\s*found\s*=\s*true\s*;\s*\}' `
        @'
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

            // SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_1
            // Prefer a resident matching alias. If none is resident yet, retain
            // the newest matching GPU producer so the consumer can use the
            // existing reference-only/pending-writer path instead of reading
            // compressed DCC bytes as CPU-linear texels.
            if (!found ||
                resident && !foundResident ||
                resident == foundResident && sequence >= writerSequence)
            {
                alias = candidate;
                writerSequence = sequence;
                found = true;
                foundResident = resident;
            }
'@ `
        'dcc-candidate-selection'

    $agc=Put-Region $agc $resolveRegion $resolve

    # Re-resolve the region because the previous replacement changed offsets.
    $createRegion=Get-Region `
        $agc `
        '    private static bool TryCreateGuestDrawTexture(' `
        '    private static GuestDrawTexture CreateFallbackGuestDrawTexture(' `
        'TryCreateGuestDrawTexture'

    $create=$createRegion.Text

    $create=Replace-RegexOnce `
        $create `
        'var\s+originalDescriptorAddress\s*=\s*descriptor\.Address\s*;' `
        @'
var originalDescriptorAddress = descriptor.Address;
        var resolvedDccAlias = false;
'@ `
        'dcc-alias-state'

    $create=Replace-RegexOnce `
        $create `
        'descriptor\s*=\s*descriptor\s+with\s*\{\s*Address\s*=\s*dccAlias\.Address\s*\}\s*;' `
        @'
resolvedDccAlias = true;
                descriptor = descriptor with { Address = dccAlias.Address };
'@ `
        'dcc-alias-flag'

    $create=Replace-RegexOnce `
        $create `
        'var\s+gpuResidentWriterImage\s*=\s*preferGpuResident\s*&&' `
        @'
var gpuResidentWriterImage =
            (preferGpuResident || resolvedDccAlias) &&
'@ `
        'dcc-writer-resident-gate'

    $create=Replace-RegexOnce `
        $create `
        'var\s+gpuWriterPending\s*=\s*preferGpuResident\s*&&' `
        @'
var gpuWriterPending =
            (preferGpuResident || resolvedDccAlias) &&
'@ `
        'dcc-writer-pending-gate'

    $create=Replace-RegexOnce `
        $create `
        'if\s*\(\s*gpuWriterPending\s*\)\s*\{\s*if\s*\(\s*_traceAgcShader\s*\)' `
        @'
if (gpuWriterPending)
        {
            if (resolvedDccAlias &&
                _traceDccAlias &&
                Interlocked.Increment(ref _dccAliasTraceCount) <= 512)
            {
                Console.Error.WriteLine(
                    $"[V73.0.20.1][DCC_ALIAS_PENDING] " +
                    $"sample=0x{originalDescriptorAddress:X16} " +
                    $"alias=0x{descriptor.Address:X16} " +
                    $"meta=0x{descriptor.MetadataAddress:X16} " +
                    $"size={descriptor.Width}x{descriptor.Height} " +
                    $"fmt={descriptor.Format}/{descriptor.NumberType}; " +
                    $"reference-only");
            }

            if (_traceAgcShader)
'@ `
        'dcc-pending-trace'

    $agc=Put-Region $agc $createRegion $create
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_1',
    '[V73.0.20.1][LARGE_PROBE_SEEDED]'
)){
    if(-not $presenter.Contains($marker)){
        throw "Presenter marker missing after patch: $marker"
    }
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_1',
    'var resolvedDccAlias = false;',
    '(preferGpuResident || resolvedDccAlias)',
    '[V73.0.20.1][DCC_ALIAS_PENDING]'
)){
    if(-not $agc.Contains($marker)){
        throw "AGC marker missing after patch: $marker"
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

Write-Host '[V73.0.20.1] Structural DCC alias + large sparse-probe patch applied.' -ForegroundColor Green
