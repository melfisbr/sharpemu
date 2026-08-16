param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74022 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot

$hostPath=Get-HostMovieBridgePathV74022 -Root $repoRoot
$hostHashBefore=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToUpperInvariant()

Write-Host "[V74.0.22] No source rewrite is required."
Write-Host "[V74.0.22] Building Release win-x64 with the validated V74.0.21 entry ABI corrections..."
Invoke-DotNetCheckedV74022 -Root $repoRoot -Arguments @(
    "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
Sync-ReleaseRuntimeAssetsV74022 -Root $repoRoot

$releaseDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){
    throw "[V74.0.22] Release SharpEmu.dll missing after build: $releaseDll"
}
$hostHashAfter=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToUpperInvariant()
if($hostHashAfter -ne $hostHashBefore){
    throw "[V74.0.22] HostMovieBridge changed unexpectedly during build. Before=$hostHashBefore After=$hostHashAfter"
}

Write-Host "[V74.0.22] SUCCESS - Release build verified; no source files modified by V74.0.22."
Write-Host "[V74.0.22] Next: RUN_4_DEMONS_GUEST_OWNED_BOOT.cmd"
