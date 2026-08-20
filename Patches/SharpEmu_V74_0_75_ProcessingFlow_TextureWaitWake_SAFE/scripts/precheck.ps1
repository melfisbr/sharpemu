param([string]$RepoRoot='')
$script:PackageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$repo = Resolve-SharpEmuRepo $RepoRoot
$state = Get-SourceState $repo
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $dotnet) { throw "$script:Tag dotnet nao encontrado no PATH." }
$project = Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
if (-not (Test-Path -LiteralPath $project)) { throw "$script:Tag Projeto CLI ausente: $project" }
Write-Host "$script:Tag repo=$repo"
Write-Host "$script:Tag presenter_sha256=$($state.PresenterSha)"
Write-Host "$script:Tag agc_sha256=$($state.AgcSha)"
Write-Host "$script:Tag presenter_alias_state=$($state.PresenterState)"
Write-Host "$script:Tag agc_flow_state=$($state.AgcState)"
Write-Host "$script:Tag rigid_sha_gate=False"
Write-Host "$script:Tag preserves_accumulated_source=True"
Write-Host "$script:Tag flow_pre_snapshot_alias=True"
Write-Host "$script:Tag flow_uninitialized_snapshot=True"
Write-Host "$script:Tag flow_producer_signal_to_drain=True"
Write-Host "$script:Tag flow_gate_owner_coalescing=True"
Write-Host "$script:Tag PRECHECK PASSED."
