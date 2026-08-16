param([string]$PackageRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root=(Resolve-Path -LiteralPath $PackageRoot).Path
$manifest=Join-Path $root "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "[V72.4.3.2.31.8] SHA256SUMS.txt missing." }
$entries=@()
foreach($line in Get-Content -LiteralPath $manifest) {
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$'){throw "[V72.4.3.2.31.8] Invalid manifest line: $line"}
    $entries += [pscustomobject]@{Hash=$matches[1].ToUpperInvariant();Rel=$matches[2]}
}
foreach($entry in $entries){
    $path=Join-Path $root ($entry.Rel -replace '/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[V72.4.3.2.31.8] Hashed file missing: $($entry.Rel)"}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Hash){throw "[V72.4.3.2.31.8] Hash mismatch: $($entry.Rel)"}
}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter *.ps1 -File){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){throw "[V72.4.3.2.31.8] PowerShell parse failed: $($file.Name): $($errors[0].Message)"}
}
$rad=[IO.File]::ReadAllText((Join-Path $root 'payload\RadBinkExternalPlaybackV7243231.cs'))
$api=[IO.File]::ReadAllText((Join-Path $root 'payload\RadBinkEmbeddedHostApiV724323171.cs'))
$profile=[IO.File]::ReadAllText((Join-Path $root 'payload\BinkPs5RuntimeProfileV724323180.cs'))
$bootstrap=[IO.File]::ReadAllText((Join-Path $root 'payload\BinkRadAutoSelectV724323180.cs'))
foreach($m in @('BinkPs5RuntimeProfileV724323180.TryInspect','bink2.ps5_runtime_profile','start.ArgumentList.Add("/I2");','external_window_forbidden=True')){if(-not $rad.Contains($m)){throw "[V72.4.3.2.31.8] RAD marker missing: $m"}}
foreach($m in @('SetParent','GetParent','IsChild','ResizeChildToHost','SHARPEMU_RAD_STRETCH','bink2.rad_aspect_fit','render_location=sharpemu-child-window')){if(-not $api.Contains($m)){throw "[V72.4.3.2.31.8] Host API marker missing: $m"}}
foreach($m in @('BinkPs5RuntimeProfileV724323180','decode_owner=official-rad','color_owner=official-rad','sharpemu_bgra_conversion=False')){if(-not $profile.Contains($m)){throw "[V72.4.3.2.31.8] Profile marker missing: $m"}}
foreach($m in @('BinkRadAutoSelectV724323180','SHARPEMU_BINK_MODE','bink2.rad_auto_selected','embedded_required=True')){if(-not $bootstrap.Contains($m)){throw "[V72.4.3.2.31.8] Bootstrap marker missing: $m"}}
if($api.Contains('GetWindowTextW(') -or $api.Contains('GetWindowTextLengthW(')){throw '[V72.4.3.2.31.8] Blocking title-based HWND discovery regression present.'}
if(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Name -ieq 'radvideo64.exe' -or $_.Name -ieq 'binkplay.exe' -or $_.Name -match '^bink.*\.dll$'}){throw '[V72.4.3.2.31.8] Proprietary RAD/Bink binary must not be redistributed.'}
Write-Host ("[V72.4.3.2.31.8] PACKAGE VALIDATION PASSED ("+$entries.Count+" hashed files; scripts parsed; PS5 profile/aspect-fit/auto-select verified; no proprietary RAD/Bink binary redistributed).") -ForegroundColor Green
