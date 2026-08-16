param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot "common.ps1")

& (Join-Path $PSScriptRoot "validate_package.ps1")
$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

Write-Host "[V61.22.3] V61.22.x diagnostic repair: no duplicate WRITE_DATA patch is required." -ForegroundColor Yellow
Write-Host "[V61.22.3] Building the current repository exactly as-is..." -ForegroundColor Cyan
$buildExit = 0
Push-Location $root
try {
    $global:LASTEXITCODE = 0
    & dotnet build ".\SharpEmu.slnx" -c Debug --nologo
    $buildExit = [int]$global:LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExit -ne 0) { throw "dotnet build failed with exit code $buildExit." }

Write-Host "[V61.22.3] SUCCESS" -ForegroundColor Green
Write-Host "[V61.22.3] Existing PM4 producer tracking preserved; no source duplication performed."
Write-Host "[V61.22.3] Next: RUN_DEMONS_DIAGNOSTIC_V61_22_3.cmd"
