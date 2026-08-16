param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$target=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $target)) { throw 'PRECHECK ERROR: GpuWaitRegistry.cs missing.' }
$text=[IO.File]::ReadAllText($target)
$marker='V61.23.1 label generation reset'
if (!$text.Contains($marker)) {
    if ($text.Contains('V61.23.2 rollback of eager label generation reset')) {
        Write-Host '[V61.23.2] PRECHECK PASSED: rollback already applied.'
        exit 0
    }
    throw 'PRECHECK ERROR: V61.23.1 epoch block not found; refusing unrelated source modification.'
}
if (!$text.Contains('public static void Register(ulong address, WaitingDcb waiter)')) {
    throw 'PRECHECK ERROR: Register method missing.'
}
if (!$text.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'PRECHECK ERROR: expected V61.23.1 removal statement missing.'
}
Write-Host '[V61.23.2] PRECHECK PASSED: exact V61.23.1 eager epoch block detected.'
