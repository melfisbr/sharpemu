param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer =
    Join-Path $root (
        ".sharpemu-hotfix-backup\" +
        "BinkSpeedRestoreBlockChroma_V72_4_3_2_29_0_2_LAST.txt")

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.29.0.2] Last-backup pointer missing."
}

$backup = [IO.File]::ReadAllText($pointer).Trim()
$rel = "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$saved = Join-Path $backup $rel
$target = Join-Path $root $rel

if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
    throw "[V72.4.3.2.29.0.2] Backup decoder missing: $saved"
}

Copy-Item -LiteralPath $saved -Destination $target -Force

Write-Host (
    "[V72.4.3.2.29.0.2] ROLLBACK COMPLETED from: " +
    $backup) `
    -ForegroundColor Green
