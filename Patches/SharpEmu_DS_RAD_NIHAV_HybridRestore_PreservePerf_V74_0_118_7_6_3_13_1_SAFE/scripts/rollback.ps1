param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$pointer=Get-BackupPointer
if(-not(Test-Path -LiteralPath $pointer)) {
    throw "$script:Tag backup pointer missing"
}

$backupRoot=
    (Get-Content -LiteralPath $pointer -Raw).Trim()
$source=
    Join-Path $backupRoot $script:RelativeHostMovieBridge
$target=
    Join-Path $repo $script:RelativeHostMovieBridge

if(-not(Test-Path -LiteralPath $source)) {
    throw "$script:Tag backup HostMovieBridge missing: $source"
}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force

Copy-Item -LiteralPath $source -Destination $target -Force
Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue

Write-Tag (
    "ROLLBACK PASSED backup=$backupRoot " +
    "host_movie_bridge_sha=$(Get-Sha $target)")
