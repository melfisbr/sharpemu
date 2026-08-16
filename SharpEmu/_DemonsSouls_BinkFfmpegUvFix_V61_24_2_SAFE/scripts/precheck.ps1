param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
$t=Join-Path $r 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
if(!(Test-Path -LiteralPath $t -PathType Leaf)){throw "PRECHECK ERROR: missing $t"}
$s=[IO.File]::ReadAllText($t)

$anchors=@(
    'private byte[]? _pgmPlanarBuffer;',
    'var planarU = planar.Slice(yBytes, chromaBytes);',
    'var planarV = planar.Slice(yBytes + chromaBytes, chromaBytes);',
    'if (!TryConvertYuvViaFfmpeg(',
    '_pgmPlanarBuffer!,',
    'private bool TryConvertYuvViaFfmpeg('
)
foreach($a in $anchors){
    if($s.IndexOf($a,[StringComparison]::Ordinal)-lt 0){
        throw "PRECHECK ERROR: source anchor missing: $a"
    }
}

if($s.IndexOf('V61.24.2 FFMPEG_UV_SWAP',[StringComparison]::Ordinal)-ge 0){
    Write-Host '[V61.24.2] PRECHECK PASSED: patch already present.'
    exit 0
}

# Detect unsupported divergence around the exact current V70.1/V61.13.23 path.
if($s.IndexOf('The reusable repacked buffer is true I420/YUV420P',[StringComparison]::Ordinal)-lt 0){
    throw 'PRECHECK ERROR: current PGMYUV->FFmpeg baseline differs from supported source.'
}
Write-Host '[V61.24.2] PRECHECK PASSED.'
Write-Host '[V61.24.2] Confirmed: current FFmpeg path bypasses _swapUv and consumes _pgmPlanarBuffer directly.'
