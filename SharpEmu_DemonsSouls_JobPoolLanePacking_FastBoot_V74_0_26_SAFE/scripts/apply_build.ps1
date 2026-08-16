param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74026 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot

$sourcePaths=@(
    (Get-AgcPathV74026 -Root $repoRoot),
    (Get-PresenterPathV74026 -Root $repoRoot),
    (Get-CpuPathV74026 -Root $repoRoot),
    (Get-DirectPathV74026 -Root $repoRoot),
    (Get-KernelPathV74026 -Root $repoRoot),
    (Get-HostMoviePathV74026 -Root $repoRoot)
)
$hashesBefore=@{}
foreach($sourcePath in $sourcePaths){$hashesBefore[$sourcePath]=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash}

Write-Host "[V74.0.26] No source rewrite is required. Building accumulated Release win-x64..."
Invoke-DotNetCheckedV74026 -Root $repoRoot -Arguments @("build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
Sync-ReleaseRuntimeAssetsV74026 -Root $repoRoot

foreach($sourcePath in $sourcePaths){
    $hashAfter=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    if($hashAfter -ne $hashesBefore[$sourcePath]){throw "[V74.0.26] Source changed unexpectedly during RUN_3: $sourcePath"}
}
$releaseDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){throw "[V74.0.26] Release SharpEmu.dll missing after build."}

Write-Host "[V74.0.26] SUCCESS - accumulated source verified and Release build passed."
Write-Host "[V74.0.26] Source hashes unchanged; this revision is runtime-profile only."
Write-Host "[V74.0.26] Next: RUN_4_DEMONS_JOBPOOL_LANE_PACKING.cmd"
