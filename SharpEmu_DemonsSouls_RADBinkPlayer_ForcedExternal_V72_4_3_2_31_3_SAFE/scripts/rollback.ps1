param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer =
    Join-Path $root (
        ".sharpemu-hotfix-backup\" +
        "RADBinkPlayerBackend_V72_4_3_2_31_3_LAST.txt")

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.31.3] Last-backup pointer missing."
}

$backup = [IO.File]::ReadAllText($pointer).Trim()

foreach ($rel in @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
)) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel

    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
        throw "[V72.4.3.2.31.3] Backup file missing: $saved"
    }

    Copy-Item -LiteralPath $saved -Destination $target -Force
}

$radRel =
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$savedRad = Join-Path $backup $radRel
$targetRad = Join-Path $root $radRel

if (Test-Path -LiteralPath $savedRad -PathType Leaf) {
    Copy-Item -LiteralPath $savedRad -Destination $targetRad -Force
}
elseif (Test-Path -LiteralPath $targetRad -PathType Leaf) {
    Remove-Item -LiteralPath $targetRad -Force
}

$configRel =
    "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"
$savedConfig = Join-Path $backup $configRel
$targetConfig = Join-Path $root $configRel

if (Test-Path -LiteralPath $savedConfig -PathType Leaf) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetConfig) | Out-Null
    Copy-Item -LiteralPath $savedConfig -Destination $targetConfig -Force
}
elseif (Test-Path -LiteralPath $targetConfig -PathType Leaf) {
    Remove-Item -LiteralPath $targetConfig -Force
}

Write-Host (
    "[V72.4.3.2.31.3] ROLLBACK COMPLETED from: " +
    $backup) `
    -ForegroundColor Green
