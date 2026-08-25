. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate.ps1"
$repo = Get-RepoRoot $env:SHARPEMU_REPO_ROOT
Assert-Installed $repo
$cacheHash = Get-Sha256 (Join-Path $repo $CacheRel)
Write-Host "[$PackageTag] SOURCE VERIFY PASSED cache_hash=$cacheHash cache_version=$CacheVersionAfter" -ForegroundColor Green
