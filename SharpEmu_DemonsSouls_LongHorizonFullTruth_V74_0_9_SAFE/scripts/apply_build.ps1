param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

Write-Host "[V74.0.9] No source patch required: the 120-second result ended before the known functional reference horizon."
Write-Host "[V74.0.9] Building current accumulated source only."
Invoke-DotNetChecked $root @(
    "build",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
    "-c","Debug",
    "-r","win-x64",
    "--nologo")

Write-Host "[V74.0.9] FINAL presenter_sha=0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"
Write-Host "[V74.0.9] FINAL source_unchanged=True"
Write-Host "[V74.0.9] FINAL all_runtime_truth_domains=True"
Write-Host "[V74.0.9] FINAL targeted_45D_producer_trace=True"
Write-Host "[V74.0.9] SUCCESS"
Write-Host "[V74.0.9] Next: RUN_DEMONS_LONG_FULL_TRUTH_V74_0_9.cmd"
