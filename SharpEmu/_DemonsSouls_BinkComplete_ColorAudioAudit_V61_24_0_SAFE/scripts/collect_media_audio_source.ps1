param(
    [string]$RepositoryRoot,
    [string]$OutputDirectory
)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw 'OutputDirectory required.'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$allCs=Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Filter '*.cs'
$mediaFiles=$allCs | Where-Object {
    $_.FullName -match '\\Media\\|Bink|Nihav|VideoOut'
}
$audioFiles=$allCs | Where-Object {
    $_.FullName -match 'Ajm|AudioOut|Audio|Acm'
}

$e=[Collections.Generic.List[string]]::new()
$e.Add('SharpEmu V61.24.0 Bink/color/audio exact-source evidence')
$e.Add("powershell=$($PSVersionTable.PSVersion)")

foreach($f in $mediaFiles) {
    Add-SourceMatches $e $f.FullName @(
        'realtime_deadline',
        'SHARPEMU_BINK_REALTIME_DEADLINE',
        'clock_catchup',
        'color_range_auto',
        'auto_range',
        'uv_swap',
        'fallback_chroma',
        'BT709',
        'PGMYUV',
        'YUV',
        'LUT',
        'Bink2 bridge completed',
        'direct_boot_completed',
        'NihavBink2Decoder',
        'output_cap'
    ) 18
}

foreach($f in $audioFiles) {
    Add-SourceMatches $e $f.FullName @(
        'port-zero-pcm',
        'port-nonzero-pcm',
        'module-register',
        'instance',
        'decode',
        'context',
        'submit',
        'batch',
        'sceAjm',
        'AudioOut2',
        'pcm',
        'opus',
        'atrac'
    ) 14
}
$e | Set-Content -LiteralPath (Join-Path $OutputDirectory 'MEDIA_AUDIO_SOURCE_EVIDENCE.txt') -Encoding UTF8

# Snapshot the most relevant small/medium source files so the next semantic patch
# can be generated against the user's exact current baseline.
$snapshotDir=Join-Path $OutputDirectory 'source_snapshots'
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

$candidates=@()
$candidates += $mediaFiles | Where-Object {
    $_.Name -match 'Bink|Nihav|Media|VideoPresenter'
}
$candidates += $audioFiles | Where-Object {
    $_.Name -match 'Ajm|AudioOut2|AudioOut|Acm'
}
$candidates = $candidates | Sort-Object FullName -Unique

$inventory=[Collections.Generic.List[string]]::new()
foreach($f in $candidates) {
    $hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $inventory.Add("$($f.FullName)`t$($f.Length)`t$hash")
    # Avoid giant accidental copies; snippets remain in evidence for larger files.
    if ($f.Length -le 2000000) {
        $safe=($f.FullName.Substring($root.Length).TrimStart('\') -replace '[\\/:*?"<>|]','_')
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $snapshotDir $safe)
    }
}
$inventory | Set-Content -LiteralPath (Join-Path $OutputDirectory 'MEDIA_AUDIO_SOURCE_INVENTORY.txt') -Encoding UTF8
