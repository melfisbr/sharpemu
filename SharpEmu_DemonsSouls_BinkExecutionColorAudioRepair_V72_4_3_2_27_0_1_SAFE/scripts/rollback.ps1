param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pointer = Join-Path $root ".sharpemu-hotfix-backup\BinkV27RuntimeRepair_V72_4_3_2_27_0_1_LAST.txt"

if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    throw "[V72.4.3.2.27.0.1] Last-backup pointer not found."
}

$backup = [IO.File]::ReadAllText($pointer).Trim()
if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup -PathType Container)) {
    throw "[V72.4.3.2.27.0.1] Invalid backup directory: $backup"
}

$cliProject = Join-Path $root "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
$runtimeTool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$optimizedTool = Join-Path $root ".sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe"

$projectBackup = Join-Path $backup "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
$runtimeBackup = Join-Path $backup "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$optimizedBackup = Join-Path $backup ".sharpemu-tools\bink2\optimized\nihav-tool-v27-native.exe"

Copy-Item -LiteralPath $projectBackup -Destination $cliProject -Force
Copy-Item -LiteralPath $runtimeBackup -Destination $runtimeTool -Force

if (Test-Path -LiteralPath $optimizedBackup -PathType Leaf) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $optimizedTool) | Out-Null
    Copy-Item -LiteralPath $optimizedBackup -Destination $optimizedTool -Force
}
elseif (Test-Path -LiteralPath $optimizedTool -PathType Leaf) {
    Remove-Item -LiteralPath $optimizedTool -Force
}

Write-Host ("[V72.4.3.2.27.0.1] ROLLBACK COMPLETED from: " + $backup) -ForegroundColor Green
