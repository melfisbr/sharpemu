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
        [Text.RegularExpressions.RegexOptions]::Singleline -bor
        [Text.RegularExpressions.RegexOptions]::Multiline)
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
        1)
}

function Find-MethodDefinition {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $escaped=[Text.RegularExpressions.Regex]::Escape($Name)
    $pattern=
        '(?m)^[ \t]*(?:private|internal|public|protected)\s+' +
        '(?:(?:static|unsafe|sealed|virtual|override|new|async)\s+)*' +
        '[A-Za-z_][A-Za-z0-9_<>,\.\?\[\]\s]*\b' +
        $escaped +
        '\s*\('

    $rx=[Text.RegularExpressions.Regex]::new($pattern)
    $matches=$rx.Matches($Text)
    if($matches.Count -ne 1){
        throw ("Method definition {0}: expected 1 match, found {1}." -f $Name,$matches.Count)
    }

    $lineEnd=$Text.IndexOf("`n",$matches[0].Index)
    if($lineEnd -lt 0){$lineEnd=$Text.Length}

    [PSCustomObject]@{
        Index=$matches[0].Index
        MatchLength=$matches[0].Length
        Signature=$Text.Substring(
            $matches[0].Index,
            $lineEnd-$matches[0].Index).Trim()
    }
}

function Region-BetweenDefinitions {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$StartName,
        [Parameter(Mandatory=$true)][string]$EndName
    )

    $start=Find-MethodDefinition $Text $StartName
    $end=Find-MethodDefinition $Text $EndName
    if($end.Index -le $start.Index){
        throw ("Method order unexpected: {0} index={1}; {2} index={3}" -f
            $StartName,$start.Index,$EndName,$end.Index)
    }

    [PSCustomObject]@{
        Start=$start.Index
        End=$end.Index
        StartSignature=$start.Signature
        EndSignature=$end.Signature
        Text=$Text.Substring($start.Index,$end.Index-$start.Index)
    }
}

function Region-FromDefinitionToNextMethod {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $start=Find-MethodDefinition $Text $Name

    $genericPattern=
        '(?m)^[ \t]*(?:private|internal|public|protected)\s+' +
        '(?:(?:static|unsafe|sealed|virtual|override|new|async)\s+)*' +
        '[A-Za-z_][A-Za-z0-9_<>,\.\?\[\]\s]*\b' +
        '[A-Za-z_][A-Za-z0-9_]*\s*\('
    $rx=[Text.RegularExpressions.Regex]::new($genericPattern)

    $next=$null
    foreach($m in $rx.Matches($Text)){
        if($m.Index -gt $start.Index){
            $next=$m
            break
        }
    }
    if($null -eq $next){
        throw ("No following method definition after {0}." -f $Name)
    }

    [PSCustomObject]@{
        Start=$start.Index
        End=$next.Index
        StartSignature=$start.Signature
        Text=$Text.Substring($start.Index,$next.Index-$start.Index)
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
# Presenter: permit the existing sparse content probe for very large images.
# The probe samples only a bounded set of bytes; logical resource size does
# not justify disabling it.
# ============================================================================

if(-not $presenter.Contains(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2'))
{
    $probeStart=Find-MethodDefinition $presenter 'TryBuildUntrackedTextureProbe'
    $probeEnd=Find-MethodDefinition $presenter 'ComputeSparseSubmittedContentProbe'
    if($probeEnd.Index -le $probeStart.Index){
        throw 'Presenter probe method order unexpected.'
    }

    $probeRegion=[PSCustomObject]@{
        Start=$probeStart.Index
        End=$probeEnd.Index
        Text=$presenter.Substring(
            $probeStart.Index,
            $probeEnd.Index-$probeStart.Index)
    }

    $probe=$probeRegion.Text
    $probe=Replace-RegexOnce `
        $probe `
        'probe\s*=\s*default\s*;\s*if\s*\(\s*texture\.Address\s*==\s*0\s*\|\|\s*byteCount\s*==\s*0\s*\|\|\s*byteCount\s*>\s*MaxTrackedGuestImageBytes\s*\)' `
        @'
probe = default;

        // SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2
        // Sparse probe traffic is bounded independently of the logical image
        // size. This keeps the 1024x1024x80 UI array from reuploading 320 MiB
        // every frame just because it exceeded the normal tracked-image cap.
        if (texture.Address == 0 ||
            byteCount == 0)
'@ `
        'large-sparse-probe-guard'

    $presenter=Put-Region $presenter $probeRegion $probe

    $markStart=Find-MethodDefinition $presenter 'MarkTextureContentCached'
    $markEnd=Find-MethodDefinition $presenter 'UnmarkTextureContentCached'
    if($markEnd.Index -le $markStart.Index){
        throw 'Presenter mark/unmark method order unexpected.'
    }

    $markRegion=[PSCustomObject]@{
        Start=$markStart.Index
        End=$markEnd.Index
        Text=$presenter.Substring(
            $markStart.Index,
            $markEnd.Index-$markStart.Index)
    }

    $mark=$markRegion.Text
    $mark=Replace-RegexOnce `
        $mark `
        '_untrackedTextureCacheProbes\s*\[\s*identity\s*\]\s*=\s*probe\s*;' `
        @'
_untrackedTextureCacheProbes[identity] = probe;

        if (probe.ByteCount > MaxTrackedGuestImageBytes)
        {
            Console.Error.WriteLine(
                $"[V73.0.20.2][LARGE_PROBE_SEEDED] " +
                $"addr=0x{identity.Address:X16} bytes={probe.ByteCount} " +
                $"size={identity.Width}x{identity.Height} " +
                $"layers={identity.ArrayLayers}");
        }
'@ `
        'large-probe-seeded-trace'

    $presenter=Put-Region $presenter $markRegion $mark
}

# ============================================================================
# AGC DCC alias repair. Method discovery is based on actual C# definitions,
# not a hard-coded "private static bool" signature.
# ============================================================================

if(-not $agc.Contains(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2'))
{
    $resolveRegion=Region-BetweenDefinitions `
        $agc `
        'TryResolveDccMetadataAlias' `
        'TryCreateGuestDrawTexture'

    Write-Host (
        "[V73.0.20.2] Resolve definition: {0}" -f
        $resolveRegion.StartSignature) -ForegroundColor DarkCyan

    $resolve=$resolveRegion.Text

    # Add residency state specifically beside the DCC resolver's counters.
    $resolve=Replace-RegexOnce `
        $resolve `
        '(var\s+residentMatches\s*=\s*0\s*;\s*)(var\s+found\s*=\s*false\s*;)' `
        @'
$1var found = false;
        var foundResident = false;
'@ `
        'dcc-found-resident'

    # Replace only the exact candidate-residency/write-sequence decision.
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

            // SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2
            // Preserve a metadata/shape-compatible RT while its Vulkan image
            // is pending. Prefer resident candidates; otherwise take the
            // newest observed writer and let the existing pending-writer
            // dependency path keep the consumer reference-only.
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

    $createRegion=Region-FromDefinitionToNextMethod `
        $agc `
        'TryCreateGuestDrawTexture'

    Write-Host (
        "[V73.0.20.2] Texture definition: {0}" -f
        $createRegion.StartSignature) -ForegroundColor DarkCyan

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
                    $"[V73.0.20.2][DCC_ALIAS_PENDING] " +
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
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_2',
    '[V73.0.20.2][LARGE_PROBE_SEEDED]'
)){
    if(-not $presenter.Contains($marker)){
        throw "Presenter marker missing after patch: $marker"
    }
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_2',
    'var resolvedDccAlias = false;',
    '(preferGpuResident || resolvedDccAlias)',
    '[V73.0.20.2][DCC_ALIAS_PENDING]'
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

Write-Host '[V73.0.20.2] Structural UI/DCC patch applied.' -ForegroundColor Green
