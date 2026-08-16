param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$hostBridgePath =
    Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$bootstrap =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$audio =
    Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"

foreach ($path in @($hostBridgePath,$bootstrap,$audio)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.4] Required source missing: $path"
    }
}

$h = Read-Normalized -Path $hostBridgePath

foreach ($marker in @(
    "V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION",
    "AttachNihavMovieLocked",
    "private enum MovieMode",
    "private static void CloseActiveLocked()",
    "private static void AttachNextQueuedMovieLocked()",
    "private static MovieMode ResolveMode()"
)) {
    if (-not $h.Contains($marker)) {
        throw "[V72.4.3.2.31.4] HostMovieBridge prerequisite missing: $marker"
    }
}

$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
$report = Write-RadDiscoveryReport -RepositoryRoot $root -RadPath $rad

if ([string]::IsNullOrWhiteSpace($rad)) {
    Write-Host "[V72.4.3.2.31.4] RAD REQUIRED precheck failed." -ForegroundColor Red
    Write-Host "[V72.4.3.2.31.4] radvideo64.exe was not found after deep discovery." -ForegroundColor Red
    Write-Host "[V72.4.3.2.31.4] NIHAV fallback is intentionally disabled for this revision."
    Write-Host ("[V72.4.3.2.31.4] Discovery report: " + $report) -ForegroundColor Yellow
    throw "[V72.4.3.2.31.4] RAD player is required; refusing another NIHAV test."
}

$hash = (Get-FileHash -LiteralPath $rad -Algorithm SHA256).Hash
$item = Get-Item -LiteralPath $rad

Write-Host "[V72.4.3.2.31.4] PRECHECK PASSED." -ForegroundColor Green
Write-Host ("[V72.4.3.2.31.4] RAD_PLAYER=" + $rad)
Write-Host ("[V72.4.3.2.31.4] RAD_VERSION=" + $item.VersionInfo.FileVersion)
Write-Host ("[V72.4.3.2.31.4] RAD_SHA256=" + $hash)
Write-Host "[V72.4.3.2.31.4] Runtime policy: RAD REQUIRED; NIHAV/FFmpeg fallback forbidden for RAD mode."
Write-Host "[V72.4.3.2.31.4] RAD owns both video and embedded Bink audio."
Write-Host ("[V72.4.3.2.31.4] Discovery report: " + $report)
