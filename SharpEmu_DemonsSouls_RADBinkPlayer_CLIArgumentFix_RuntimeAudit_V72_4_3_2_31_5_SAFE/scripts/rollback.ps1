param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\RADBinkPlayerCLIArgumentFix_V72_4_3_2_31_5_LAST.txt"

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.31.5] No V31.5 rollback pointer found."
}

$backup = [IO.File]::ReadAllText($pointer).Trim()
$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

foreach ($rel in @($radRel,$configRel)) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel
    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $saved -Destination $target -Force
    }
}

Write-Host ("[V72.4.3.2.31.5] Rollback restored from: " + $backup)
