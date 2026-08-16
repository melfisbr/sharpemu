param(
    [string]$RepositoryRoot=(Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$root =
    Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$pointer =
    Join-Path $root (
        ".sharpemu-hotfix-backup\" +
        "BinkDedicatedDecoderDirectChroma_V72_4_3_2_29_LAST.txt")

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.29.0.1] Last-backup pointer missing."
}

$backup =
    [IO.File]::ReadAllText($pointer).Trim()

foreach ($rel in @(
    "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
)) {
    $saved =
        Join-Path $backup $rel
    $target =
        Join-Path $root $rel

    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
        throw "[V72.4.3.2.29.0.1] Backup file missing: $saved"
    }

    Copy-Item `
        -LiteralPath $saved `
        -Destination $target `
        -Force
}

Write-Host (
    "[V72.4.3.2.29.0.1] ROLLBACK COMPLETED from: " +
    $backup) `
    -ForegroundColor Green
