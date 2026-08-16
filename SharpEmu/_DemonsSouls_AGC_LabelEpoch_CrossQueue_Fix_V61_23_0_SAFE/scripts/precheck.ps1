param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$target=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $target)) { throw "PRECHECK ERROR: missing $target" }
$text=[IO.File]::ReadAllText($target)
$hash=Get-Sha256 $target
$expected='02FEE34B01BF2E12DCB391731F3F7FC3284351E4909363C0016D51BE25EDB3D6'
if ($text.Contains('V61.23.0 label generation reset')) {
    Write-Host '[V61.23.0] PRECHECK PASSED: correction already present (idempotent mode).'
    exit 0
}
if ($hash -ne $expected) {
    throw "PRECHECK ERROR: GpuWaitRegistry.cs baseline hash differs. Expected=$expected Actual=$hash. Refusing unsafe transform."
}
if (!$text.Contains('private static readonly Dictionary<(object, ulong), ulong> _lastProduced')) {
    throw 'PRECHECK ERROR: _lastProduced registry anchor not found.'
}
if (!$text.Contains('public static void Register(ulong address, WaitingDcb waiter)')) {
    throw 'PRECHECK ERROR: Register waiter method anchor not found.'
}
if (!$text.Contains('lock (_gate)')) { throw 'PRECHECK ERROR: lock anchor not found.' }
Write-Host '[V61.23.0] PRECHECK PASSED: exact V61.22.3 GpuWaitRegistry baseline recognized.'
