param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\RADMediaClock_V72_4_3_2_31_7_7_LAST.txt"
if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.7] No rollback pointer found: $pointer"
}
$backup = [IO.File]::ReadAllText($pointer).Trim()
if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup -PathType Container)) {
    throw "[V72.4.3.2.31.7.7] Backup directory is invalid: $backup"
}
foreach ($rel in @(
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs"
)) {
    $saved = Join-Path $backup $rel
    $target = Join-Path $root $rel
    if (Test-Path -LiteralPath $saved -PathType Leaf) {
        Copy-Item -LiteralPath $saved -Destination $target -Force
    }
}
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"
$savedConfig = Join-Path $backup $configRel
$configFile = Join-Path $root $configRel
if (Test-Path -LiteralPath $savedConfig -PathType Leaf) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
    Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
}
Write-Host ("[V72.4.3.2.31.7.7] Rollback restored: " + $backup) -ForegroundColor Green
