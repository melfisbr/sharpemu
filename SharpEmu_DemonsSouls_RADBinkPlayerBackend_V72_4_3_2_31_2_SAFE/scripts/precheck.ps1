param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$hostBridgePath =
    Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"

foreach ($path in @($hostBridgePath,$audio,$bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.2] Required source missing: $path"
    }
}

$h = Read-Normalized -Path $hostBridgePath
$a = Read-Normalized -Path $audio

foreach ($marker in @(
    "V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION",
    "AttachNihavMovieLocked",
    "private enum MovieMode",
    "private static void CloseActiveLocked()",
    "private static void AttachNextQueuedMovieLocked()"
)) {
    if (-not $h.Contains($marker)) {
        throw "[V72.4.3.2.31.2] HostMovieBridge prerequisite missing: $marker"
    }
}

if (-not (
    $a.Contains("return 0.9054;") -or
    $a.Contains("return 0.7000;") -or
    $a.Contains("return 1.0000;")))
{
    throw "[V72.4.3.2.31.2] Known attract-audio tempo baseline not found."
}

$rad = Find-RadVideo64 -RepositoryRoot $root

Write-Host "[V72.4.3.2.31.2] PRECHECK PASSED."

if ([string]::IsNullOrWhiteSpace($rad)) {
    Write-Host "[V72.4.3.2.31.2] RAD player: not found (OPTIONAL)." -ForegroundColor Yellow
    Write-Host "[V72.4.3.2.31.2] Build will continue with native -> NIHAV -> FFmpeg fallback."
    Write-Host "[V72.4.3.2.31.2] Existing V30 audio/tempo behavior will be preserved."
}
else {
    $hash = (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash
    Write-Host ("[V72.4.3.2.31.2] RAD player: " + $rad)
    Write-Host ("[V72.4.3.2.31.2] RAD SHA256: " + $hash)
    Write-Host "[V72.4.3.2.31.2] RAD will be primary; NIHAV remains fallback."
    Write-Host "[V72.4.3.2.31.2] RAD executable will NOT be copied; only its local path is stored."
}
