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
        throw "[V72.4.3.2.31] Required source missing: $path"
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
        throw "[V72.4.3.2.31] HostMovieBridge prerequisite missing: $marker"
    }
}

if (-not (
    $a.Contains("return 0.9054;") -or
    $a.Contains("return 0.7000;") -or
    $a.Contains("return 1.0000;")))
{
    throw "[V72.4.3.2.31] Known attract-audio tempo baseline not found."
}

$rad = Find-RadVideo64

if ([string]::IsNullOrWhiteSpace($rad)) {
    throw (
        "[V72.4.3.2.31] radvideo64.exe was not found. " +
        "Set SHARPEMU_RADVIDEO64 to the executable you tested, " +
        "or keep it under Downloads/Desktop.")
}

$hash =
    (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash

Write-Host "[V72.4.3.2.31] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31] RAD player: " + $rad)
Write-Host ("[V72.4.3.2.31] RAD SHA256: " + $hash)
Write-Host "[V72.4.3.2.31] RAD executable will NOT be copied; only its local path is stored."
Write-Host "[V72.4.3.2.31] NIHAV remains fallback."
