param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$agc=Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$wait=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $agc)) { throw 'PRECHECK ERROR: AgcExports.cs missing.' }
if (!(Test-Path -LiteralPath $wait)) { throw 'PRECHECK ERROR: GpuWaitRegistry.cs missing.' }
$wt=[IO.File]::ReadAllText($wait)
if ($wt.Contains('V61.23.1 label generation reset') -or $wt.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'PRECHECK ERROR: V61.23.1 eager epoch logic is active; V61.23.5 rollback did not persist.'
}
Write-Host '[V61.23.6.1.1] PRECHECK PASSED.'
Write-Host '[V61.23.6.1.1] V61.23.5 rollback confirmed; collecting exact source lineage for remaining post-video stall.'
