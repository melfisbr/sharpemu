. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$backup = Get-LatestRuntimeAuditBackup $repo
$currentFrontend = Find-PatchedFrontendSource $repo
$currentHash = Get-HashSafe $currentFrontend
$originalBackup = Find-OriginalFrontendBackup $backup
$backupHash = Get-HashSafe $originalBackup
$guiProject = Get-GuiProject $repo

$partials = @(Find-FileByHash (Join-Path $repo 'src') $script:RuntimeAuditPartialHash '*.cs')
if ($partials.Count -eq 0) {
    $partials = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.FullName -eq $currentFrontend) { return $false }
            $t = Get-Content -LiteralPath $_.FullName -Raw
            $t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch'
        })
}

$projectText = Get-Content -LiteralPath $guiProject -Raw
$hasAuditReference = $projectText -match 'SharpEmu\.RuntimeAudit'

Write-Step "Repo=$repo"
Write-Step "Backup=$backup"
Write-Step "CurrentFrontend=$currentFrontend"
Write-Step "CurrentFrontendSHA256=$currentHash"
Write-Step "OriginalFrontendBackup=$originalBackup"
Write-Step "OriginalFrontendBackupSHA256=$backupHash"
Write-Step "RuntimeAuditPartialCandidates=$($partials.Count)"
Write-Step "GuiProject=$guiProject"
Write-Step "GuiProjectReferencesRuntimeAudit=$hasAuditReference"

if ($backupHash -ne $script:OriginalFrontendHash) {
    throw "$script:Tag Backup frontend hash is not the expected pre-V1.1 hash."
}
if ($currentHash -ne $script:PatchedFrontendHash -and $currentHash -ne $script:OriginalFrontendHash) {
    $text = Get-Content -LiteralPath $currentFrontend -Raw
    if ($text -notmatch 'InstallRuntimeAuditButton' -and $text -notmatch 'Audit\s*&\s*Launch') {
        throw "$script:Tag Current frontend source has an unknown hash and no RuntimeAudit marker. Refusing unsafe overwrite."
    }
}

Write-Step "PRECHECK PASSED. Locator is filename-independent."
