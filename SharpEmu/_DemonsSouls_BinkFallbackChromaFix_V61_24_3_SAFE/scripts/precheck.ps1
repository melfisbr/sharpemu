param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
$t=Join-Path $r 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
if(!(Test-Path -LiteralPath $t -PathType Leaf)){throw "PRECHECK ERROR: missing $t"}
$s=[IO.File]::ReadAllText($t)
$anchors=@(
    'SHARPEMU_BINK_FORCE_UV_SWAP',
    'bink2.fallback_chroma_forced uv_swap=True',
    'TryRepairGreenFallback(',
    'ConvertYuv420ToBgra(',
    'SHARPEMU_BINK_FFMPEG_COLOR'
)
foreach($a in $anchors){
    if($s.IndexOf($a,[StringComparison]::Ordinal)-lt 0){
        throw "PRECHECK ERROR: required current color-path anchor missing: $a"
    }
}
Write-Host '[V61.24.3] PRECHECK PASSED.'
Write-Host '[V61.24.3] Existing fallback forced-U/V recovery is present.'
Write-Host '[V61.24.3] V61.24.2 logs proved FFmpeg color times out and falls back before visible playback.'
