. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$backup = Get-LatestRuntimeAuditBackup $repo
$main = Find-CurrentMainWindow $repo
$mainHash = Get-HashSafe $main
$backupMain = @(Find-FileByHash $backup $script:OriginalMainWindowHash 'MainWindow.cs')

$partial = @(Find-FileByHash (Join-Path $repo 'src') $script:RuntimeAuditPartialHash '*.cs')
if ($partial.Count -eq 0) {
    $partial = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
        Where-Object {
            $t = Get-Content -LiteralPath $_.FullName -Raw
            $t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch'
        })
}

$guiProject = Get-GuiProject $repo
$projectText = Get-Content -LiteralPath $guiProject -Raw
$hasAuditReference = $projectText -match 'SharpEmu\.RuntimeAudit'

Write-Step "Repo=$repo"
Write-Step "Backup=$backup"
Write-Step "CurrentMainWindow=$main"
Write-Step "CurrentMainWindowSHA256=$mainHash"
Write-Step "OriginalMainWindowBackupMatches=$($backupMain.Count)"
Write-Step "RuntimeAuditPartialCandidates=$($partial.Count)"
Write-Step "GuiProject=$guiProject"
Write-Step "GuiProjectReferencesRuntimeAudit=$hasAuditReference"

if ($backupMain.Count -ne 1) {
    throw "$script:Tag Expected exactly one original MainWindow.cs in the V1.1 backup; found $($backupMain.Count)."
}

if ($mainHash -ne $script:PatchedMainWindowHash -and $mainHash -ne $script:OriginalMainWindowHash) {
    throw "$script:Tag Current MainWindow has changed after V1.1 (hash $mainHash). Refusing to overwrite an unknown newer edit."
}

Write-Step "PRECHECK PASSED. Rollback will touch only V1.1 frontend integration files and GUI project reference if present."
