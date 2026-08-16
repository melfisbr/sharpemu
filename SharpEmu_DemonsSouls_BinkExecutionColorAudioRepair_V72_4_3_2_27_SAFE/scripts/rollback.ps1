param(
    [string]$RepositoryRoot=(Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$pointer =
    Join-Path $root (
        ".sharpemu-hotfix-backup\" +
        "BinkExecutionColorAudio_V72_4_3_2_27_LAST.txt")

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.27] Last-backup pointer not found: $pointer"
}

$backup =
    [IO.File]::ReadAllText($pointer).Trim()

if ([string]::IsNullOrWhiteSpace($backup) -or
    -not (Test-Path -LiteralPath $backup -PathType Container)) {
    throw "[V72.4.3.2.27] Backup directory is invalid: $backup"
}

$required = @(
    "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs",
    "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
)

foreach ($rel in $required) {
    $saved = Join-Path $backup $rel

    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
        throw "[V72.4.3.2.27] Backup file missing: $saved"
    }
}

foreach ($rel in $required) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Split-Path -Parent $target) |
        Out-Null

    Copy-Item `
        -LiteralPath $saved `
        -Destination $target `
        -Force
}

foreach ($rel in @(
    "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
)) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel

    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        Copy-Item `
            -LiteralPath $saved `
            -Destination $target `
            -Force
    }
    elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}

Write-Host (
    "[V72.4.3.2.27] ROLLBACK COMPLETED from: " +
    $backup) `
    -ForegroundColor Green
