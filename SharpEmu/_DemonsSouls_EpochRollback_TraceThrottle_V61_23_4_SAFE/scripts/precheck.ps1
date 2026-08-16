param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot
$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $target)) {
    throw 'PRECHECK ERROR: GpuWaitRegistry.cs missing.'
}
$text = [IO.File]::ReadAllText($target)

$hasOldMarker = $text.Contains('V61.23.1 label generation reset')
$hasOldRemoval = $text.Contains('_lastProduced.Remove((waiter.Memory, address))')
$hasRollback = $text.Contains('V61.23.4 rollback of eager label generation reset') -or
               $text.Contains('V61.23.2 rollback of eager label generation reset')

if ($hasOldMarker -xor $hasOldRemoval) {
    throw 'PRECHECK ERROR: partial/unknown V61.23.1 epoch block detected; refusing unsafe edit.'
}
if (!$text.Contains('public static void Register(ulong address, WaitingDcb waiter)')) {
    throw 'PRECHECK ERROR: Register(ulong, WaitingDcb) missing.'
}
if (!$text.Contains('public static bool RecordProduced(object memory, ulong address, ulong value)')) {
    throw 'PRECHECK ERROR: RecordProduced(...) missing.'
}

if ($hasOldMarker -and $hasOldRemoval) {
    Write-Host '[V61.23.4] PRECHECK PASSED: active V61.23.1 eager epoch block detected; exact rollback required.'
} elseif ($hasRollback) {
    Write-Host '[V61.23.4] PRECHECK PASSED: epoch rollback already present.'
} else {
    Write-Host '[V61.23.4] PRECHECK PASSED: no V61.23.1 eager epoch block present; source semantics already safe.'
}
