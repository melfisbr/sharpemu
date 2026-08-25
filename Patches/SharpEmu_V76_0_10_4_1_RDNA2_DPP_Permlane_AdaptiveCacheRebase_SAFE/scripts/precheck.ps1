. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate.ps1"
$repo = Get-RepoRoot $env:SHARPEMU_REPO_ROOT
$state = Get-PackageState $repo
Write-Host "[$PackageTag] PRECHECK PASSED state=$state repo=$repo" -ForegroundColor Green
if ($state -eq 'Ready') {
    Write-Host "[$PackageTag] AdaptiveCacheBaseline=$CacheBeforeHash" -ForegroundColor DarkGray
}
