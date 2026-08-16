param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_2_LAST.txt"
if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.31.7.2] No rollback pointer found: $pointer"
}
$backup = [IO.File]::ReadAllText($pointer).Trim()
if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup -PathType Container)) {
    throw "[V72.4.3.2.31.7.2] Backup directory is invalid: $backup"
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$apiRel = "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

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

$savedConfig = Join-Path $backup $configRel
$configFile = Join-Path $root $configRel
if (Test-Path -LiteralPath $savedConfig -PathType Leaf) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
    Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
}

Write-Host ("[V72.4.3.2.31.7.2] Rollback restored: " + $backup) -ForegroundColor Green
