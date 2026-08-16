param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\BinkAttractSyncChroma_V72_4_3_2_28_LAST.txt"

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.28.0.1] Last-backup pointer missing."
}

$backup = [IO.File]::ReadAllText($pointer).Trim()

$files = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
)

foreach ($rel in $files) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel

    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
        throw "[V72.4.3.2.28.0.1] Backup file missing: $saved"
    }

    Copy-Item -LiteralPath $saved -Destination $target -Force
}

Write-Host ("[V72.4.3.2.28.0.1] ROLLBACK COMPLETED from: " + $backup) -ForegroundColor Green
