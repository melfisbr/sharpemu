param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot
$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $target -PathType Leaf)) { throw "PRECHECK ERROR: missing $target" }
$text = [IO.File]::ReadAllText($target)
$hash = Get-Sha256 $target
$expected = '02FEE34B01BF2E12DCB391731F3F7FC3284351E4909363C0016D51BE25EDB3D6'

if ($text.Contains('V61.23.1 label generation reset')) {
    Write-Host '[V61.23.1] PRECHECK PASSED: correction already present (idempotent mode).'
    exit 0
}
if ($hash -ne $expected) {
    throw "PRECHECK ERROR: GpuWaitRegistry.cs baseline hash differs. Expected=$expected Actual=$hash. Refusing unsafe transform."
}
# The exact hash already identifies the supported source. These checks only make
# sure the semantic insertion site remains present; do not depend on the concrete
# value type used by _lastProduced.
if (!$text.Contains('_lastProduced')) {
    throw 'PRECHECK ERROR: _lastProduced registry usage not found.'
}
$methodAnchor = 'public static void Register(ulong address, WaitingDcb waiter)'
$methodStart = $text.IndexOf($methodAnchor, [StringComparison]::Ordinal)
if ($methodStart -lt 0) { throw 'PRECHECK ERROR: Register waiter method not found.' }
$lockPos = $text.IndexOf('lock (_gate)', $methodStart, [StringComparison]::Ordinal)
if ($lockPos -lt 0 -or ($lockPos - $methodStart) -gt 3000) {
    throw 'PRECHECK ERROR: Register waiter lock not found in expected method window.'
}
Write-Host "[V61.23.1] PRECHECK PASSED: exact baseline recognized (SHA256=$hash)."
