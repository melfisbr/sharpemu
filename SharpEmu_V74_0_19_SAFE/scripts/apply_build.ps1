param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74018 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

Write-Host "[V74.0.19] No source patch is being applied."
Write-Host "[V74.0.19] Building Release win-x64 to verify the accumulated checkout..."
Invoke-DotNetCheckedV74018 -Root $root -Arguments @(
    "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
    "-c","Release","-r","win-x64","--nologo")
Sync-ReleaseRuntimeAssetsV74018 -Root $root

$releaseDll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){
    throw "[V74.0.19] Release SharpEmu.dll missing after successful build: $releaseDll"
}

$direct=Get-DirectExecutionBackendPathV74018 -Root $root
$directText=[System.IO.File]::ReadAllText($direct)
$memcpyState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $directText
if($memcpyState.State -ne "Applied"){
    throw "[V74.0.19] Native memcpy cumulative state changed during build: $($memcpyState.State)"
}

Write-Host "[V74.0.19] SUCCESS - accumulated source verified and Release build passed."
Write-Host "[V74.0.19] Next: RUN_4_DEMONS_BOOT_SEQUENCE_RESTORE.cmd"
