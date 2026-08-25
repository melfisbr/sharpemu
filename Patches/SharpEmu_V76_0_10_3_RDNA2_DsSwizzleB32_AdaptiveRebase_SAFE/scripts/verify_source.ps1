. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate.ps1"
$repo=Get-RepoRoot $env:SHARPEMU_REPO_ROOT
Assert-Installed $repo
Write-Host "[$PackageTag] SOURCE VERIFY PASSED" -ForegroundColor Green
