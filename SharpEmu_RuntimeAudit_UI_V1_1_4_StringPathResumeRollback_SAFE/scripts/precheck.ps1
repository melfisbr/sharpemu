. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$frontend = Get-FrontendPath $repo
$frontendHash = Get-HashSafe $frontend
$guiProject = Get-GuiProject $repo
$partials = @(Find-RuntimeAuditPartialPaths $repo $frontend)

$projectText = Get-Content -LiteralPath $guiProject -Raw
$hasAuditReference = $projectText -match 'SharpEmu\.RuntimeAudit'

Write-Step "Repo=$repo"
Write-Step "Frontend=$frontend"
Write-Step "FrontendSHA256=$frontendHash"
Write-Step "ExpectedOriginalSHA256=$($script:OriginalFrontendHash)"
Write-Step "RuntimeAuditPartialCandidates=$($partials.Count)"
foreach ($p in $partials) { Write-Step "RuntimeAuditPartial=$([string]$p)" }
Write-Step "GuiProject=$guiProject"
Write-Step "GuiProjectReferencesRuntimeAudit=$hasAuditReference"

if ($frontendHash -ne $script:OriginalFrontendHash) {
    throw "$script:Tag MainWindow.axaml.cs is not at the confirmed pre-RuntimeAudit baseline. Current SHA256=$frontendHash"
}

Write-Step "PRECHECK PASSED. V1.1.3 frontend restore is confirmed; V1.1.4 will resume after that point."
