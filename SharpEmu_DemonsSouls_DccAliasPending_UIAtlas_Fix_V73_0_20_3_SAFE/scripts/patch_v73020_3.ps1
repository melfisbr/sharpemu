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

function Find-MethodBlock {
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

    $matches=[Text.RegularExpressions.Regex]::Matches($Text,$pattern)
    if($matches.Count -ne 1){
        throw ("Method {0}: expected 1 definition, found {1}." -f
            $Name,$matches.Count)
    }

    $start=$matches[0].Index
    $open=$Text.IndexOf('{',$start)
    if($open -lt 0){
        throw ("Method {0}: opening brace not found." -f $Name)
    }

    # C# method bodies in these target methods contain no raw-string brace
    # syntax; balance braces while ignoring characters inside normal/verbatim
    # string and char literals.
    $depth=0
    $inString=$false
    $inChar=$false
    $verbatim=$false
    $escape=$false
    $end=-1

    for($i=$open;$i -lt $Text.Length;$i++){
        $c=$Text[$i]
        $prev=if($i -gt 0){$Text[$i-1]}else{[char]0}

        if($inString){
            if($verbatim){
                if($c -eq '"'){
                    if($i+1 -lt $Text.Length -and $Text[$i+1] -eq '"'){
                        $i++
                        continue
                    }
                    $inString=$false
                    $verbatim=$false
                }
                continue
            }

            if($escape){
                $escape=$false
                continue
            }
            if($c -eq '\'){
                $escape=$true
                continue
            }
            if($c -eq '"'){
                $inString=$false
            }
            continue
        }

        if($inChar){
            if($escape){
                $escape=$false
                continue
            }
            if($c -eq '\'){
                $escape=$true
                continue
            }
            if($c -eq "'"){
                $inChar=$false
            }
            continue
        }

        if($c -eq '"'){
            $inString=$true
            $verbatim=($prev -eq '@')
            continue
        }
        if($c -eq "'"){
            $inChar=$true
            continue
        }

        if($c -eq '{'){
            $depth++
        } elseif($c -eq '}'){
            $depth--
            if($depth -eq 0){
                $end=$i+1
                break
            }
        }
    }

    if($end -le $open){
        throw ("Method {0}: closing brace not found." -f $Name)
    }

    $lineEnd=$Text.IndexOf("`n",$start)
    if($lineEnd -lt 0){$lineEnd=$open}

    [PSCustomObject]@{
        Start=$start
        End=$end
        Signature=$Text.Substring($start,$lineEnd-$start).Trim()
        Text=$Text.Substring($start,$end-$start)
    }
}

function Put-MethodBlock {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)]$Block,
        [Parameter(Mandatory=$true)][string]$Replacement
    )

    return $Text.Substring(0,$Block.Start)+
        $Replacement+
        $Text.Substring($Block.End)
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
# 1. LARGE UI/ATLAS PROBE
# ============================================================================

if(-not $presenter.Contains(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_3'))
{
    $block=Find-MethodBlock $presenter 'TryBuildUntrackedTextureProbe'
    Write-Host (
        "[V73.0.20.3] Probe definition: {0}" -f $block.Signature
    ) -ForegroundColor DarkCyan

    $method=$block.Text

    # Remove ONLY the logical image size rejection from the existing guard.
    # The sparse probe itself remains bounded to its existing sample count.
    $method=Replace-RegexOnce `
        $method `
        '\|\|\s*byteCount\s*>\s*MaxTrackedGuestImageBytes' `
        @'
/* SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_3:
           sparse probe is bounded independently of logical image bytes */
'@ `
        'large-sparse-probe-size-clause'

    $presenter=Put-MethodBlock $presenter $block $method

    $mark=Find-MethodBlock $presenter 'MarkTextureContentCached'
    $markMethod=$mark.Text
    $markMethod=Replace-RegexOnce `
        $markMethod `
        '_untrackedTextureCacheProbes\s*\[\s*identity\s*\]\s*=\s*probe\s*;' `
        @'
_untrackedTextureCacheProbes[identity] = probe;

        if (probe.ByteCount > MaxTrackedGuestImageBytes)
        {
            Console.Error.WriteLine(
                $"[V73.0.20.3][LARGE_PROBE_SEEDED] " +
                $"addr=0x{identity.Address:X16} bytes={probe.ByteCount} " +
                $"size={identity.Width}x{identity.Height} " +
                $"layers={identity.ArrayLayers}");
        }
'@ `
        'large-probe-trace'

    $presenter=Put-MethodBlock $presenter $mark $markMethod
}

# ============================================================================
# 2. DCC ALIAS: DO NOT DROP A MATCHING PENDING GPU PRODUCER
# ============================================================================

if(-not $agc.Contains(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_3'))
{
    $resolve=Find-MethodBlock $agc 'TryResolveDccMetadataAlias'
    Write-Host (
        "[V73.0.20.3] Resolve definition: {0}" -f $resolve.Signature
    ) -ForegroundColor DarkCyan

    $resolveMethod=$resolve.Text

    # Old behavior:
    #   if (!IsGpuGuestImageAvailable(candidate...)) continue;
    #   residentMatches++;
    #
    # New behavior:
    #   count residency for diagnostics, but do NOT discard the candidate.
    #   Existing writer.Sequence selection below then chooses the newest
    #   matching DCC producer, even if its Vulkan image is still queued.
    $resolveMethod=Replace-RegexOnce `
        $resolveMethod `
        'if\s*\(\s*!GuestGpu\.Current\.IsGpuGuestImageAvailable\(\s*candidate\.Address\s*,\s*candidate\.Format\s*,\s*candidate\.NumberType\s*\)\s*\)\s*\{\s*continue\s*;\s*\}\s*residentMatches\+\+\s*;' `
        @'
var candidateResident =
                GuestGpu.Current.IsGpuGuestImageAvailable(
                    candidate.Address,
                    candidate.Format,
                    candidate.NumberType);
            if (candidateResident)
            {
                residentMatches++;
            }

            // SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_3
            // Do not discard a metadata/shape-compatible render target merely
            // because its VkImage is not resident YET. The writer sequence
            // below identifies the newest producer and the consumer path will
            // keep it reference-only while the producer is pending.
'@ `
        'dcc-residency-drop-gate'

    $agc=Put-MethodBlock $agc $resolve $resolveMethod

    $create=Find-MethodBlock $agc 'TryCreateGuestDrawTexture'
    Write-Host (
        "[V73.0.20.3] Texture definition: {0}" -f $create.Signature
    ) -ForegroundColor DarkCyan

    $createMethod=$create.Text

    $createMethod=Replace-RegexOnce `
        $createMethod `
        'var\s+originalDescriptorAddress\s*=\s*descriptor\.Address\s*;' `
        @'
var originalDescriptorAddress = descriptor.Address;
        var resolvedDccAlias = false;
'@ `
        'dcc-alias-state'

    $createMethod=Replace-RegexOnce `
        $createMethod `
        'descriptor\s*=\s*descriptor\s+with\s*\{\s*Address\s*=\s*dccAlias\.Address\s*\}\s*;' `
        @'
resolvedDccAlias = true;
                descriptor = descriptor with { Address = dccAlias.Address };
'@ `
        'dcc-alias-flag'

    # A resolved DCC alias is proof of a GPU writer lineage even when the
    # original call did not set preferGpuResident.
    $createMethod=Replace-RegexOnce `
        $createMethod `
        'var\s+gpuResidentWriterImage\s*=\s*preferGpuResident\s*&&' `
        @'
var gpuResidentWriterImage =
            (preferGpuResident || resolvedDccAlias) &&
'@ `
        'dcc-resident-writer-gate'

    $createMethod=Replace-RegexOnce `
        $createMethod `
        'var\s+gpuWriterPending\s*=\s*preferGpuResident\s*&&' `
        @'
var gpuWriterPending =
            (preferGpuResident || resolvedDccAlias) &&
'@ `
        'dcc-pending-writer-gate'

    $createMethod=Replace-RegexOnce `
        $createMethod `
        'if\s*\(\s*gpuWriterPending\s*\)\s*\{\s*if\s*\(\s*_traceAgcShader\s*\)' `
        @'
if (gpuWriterPending)
        {
            if (resolvedDccAlias &&
                _traceDccAlias &&
                Interlocked.Increment(ref _dccAliasTraceCount) <= 512)
            {
                Console.Error.WriteLine(
                    $"[V73.0.20.3][DCC_ALIAS_PENDING] " +
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

    $agc=Put-MethodBlock $agc $create $createMethod
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_3',
    '[V73.0.20.3][LARGE_PROBE_SEEDED]'
)){
    if(-not $presenter.Contains($marker)){
        throw "Presenter marker missing after patch: $marker"
    }
}

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_3',
    'var resolvedDccAlias = false;',
    '(preferGpuResident || resolvedDccAlias)',
    '[V73.0.20.3][DCC_ALIAS_PENDING]'
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

Write-Host '[V73.0.20.3] Structural DCC pending-alias + large UI probe patch applied.' -ForegroundColor Green
