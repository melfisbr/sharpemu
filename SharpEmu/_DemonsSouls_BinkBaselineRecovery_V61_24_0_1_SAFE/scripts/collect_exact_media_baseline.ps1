param(
    [string]$RepositoryRoot,
    [string]$OutputDirectory
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$files=Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Filter '*.cs'
$media=$files | Where-Object {
    $_.FullName -match '\\Media\\|\\VideoOut\\' -or
    $_.Name -match 'Bink|Nihav|VideoPresenter'
}
$audio=$files | Where-Object {
    $_.FullName -match '\\Ajm\\|\\Audio' -or
    $_.Name -match 'Ajm|AudioOut|Audio'
}

$out=[Collections.Generic.List[string]]::new()
$out.Add('SharpEmu V61.24.0.1 exact current Bink/color/audio source baseline')
foreach($f in $media){
    Add-Matches $out $f.FullName @(
        'Bink2 bridge completed',
        'direct_boot_completed',
        'clock_catchup',
        'deadline',
        'realtime',
        'frameCount',
        'frames',
        'elapsed',
        'duration',
        'uv_swap',
        'UvSwap',
        'BT709',
        'BT.709',
        'color_range',
        'full',
        'limited',
        'PGMYUV',
        'YUV',
        'chroma',
        'matrix',
        'LUT'
    ) 22
}
foreach($f in $audio){
    Add-Matches $out $f.FullName @(
        'sceAjm',
        'module-register',
        'instance',
        'decode',
        'context',
        'batch',
        'submit',
        'AudioOut2',
        'port-zero-pcm',
        'port-nonzero-pcm',
        'pcm',
        'opus',
        'atrac'
    ) 18
}
$out | Set-Content -LiteralPath (Join-Path $OutputDirectory 'EXACT_MEDIA_AUDIO_SOURCE.txt') -Encoding UTF8

$inventory=[Collections.Generic.List[string]]::new()
$snap=Join-Path $OutputDirectory 'source_snapshots'
New-Item -ItemType Directory -Force -Path $snap | Out-Null
$selected=@($media)+@($audio) | Sort-Object FullName -Unique
foreach($f in $selected){
    $hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $inventory.Add("$($f.FullName)`t$($f.Length)`t$hash")
    if($f.Length -le 2500000){
        $rel=$f.FullName.Substring($root.Length).TrimStart('\')
        $safe=$rel -replace '[\\/:*?"<>|]','_'
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $snap $safe)
    }
}
$inventory | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SOURCE_INVENTORY.txt') -Encoding UTF8
