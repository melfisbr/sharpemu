param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_LAST.txt"
if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.31.7] No rollback pointer found: $pointer"
}
$backup = [IO.File]::ReadAllText($pointer).Trim()
if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup -PathType Container)) {
    throw "[V72.4.3.2.31.7] Backup directory is invalid: $backup"
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$apiRel = "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV72432317.cs"
foreach ($rel in @($radRel,$apiRel)) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel
    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $saved -Destination $target -Force
    }
    elseif ($rel -eq $apiRel -and (Test-Path -LiteralPath $target -PathType Leaf)) {
        Remove-Item -LiteralPath $target -Force
    }
}
Write-Host ("[V72.4.3.2.31.7] Rollback restored: " + $backup) -ForegroundColor Green
