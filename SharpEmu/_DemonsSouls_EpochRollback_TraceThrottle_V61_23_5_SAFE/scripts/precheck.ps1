param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot
$target = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "PRECHECK ERROR: missing $target"
}

$text = [IO.File]::ReadAllText($target)
$methodAnchor = 'public static void Register(ulong address, WaitingDcb waiter)'
$methodStart = $text.IndexOf($methodAnchor, [StringComparison]::Ordinal)
if ($methodStart -lt 0) { throw 'PRECHECK ERROR: Register waiter method missing.' }

$lockPos = $text.IndexOf('lock (_gate)', $methodStart, [StringComparison]::Ordinal)
if ($lockPos -lt 0 -or ($lockPos - $methodStart) -gt 3000) {
    throw 'PRECHECK ERROR: Register lock missing.'
}

$nextOriginal = 'if (!_waiters.TryGetValue(address, out var list))'
$originalPos = $text.IndexOf($nextOriginal, $lockPos, [StringComparison]::Ordinal)
if ($originalPos -lt 0 -or ($originalPos - $lockPos) -gt 6000) {
    throw 'PRECHECK ERROR: original Register waiter-list anchor missing.'
}

$markerPos = $text.IndexOf('V61.23.1 label generation reset', $lockPos, [StringComparison]::Ordinal)
$removePos = $text.IndexOf('_lastProduced.Remove((waiter.Memory, address))', $lockPos, [StringComparison]::Ordinal)

if ($markerPos -ge 0 -and $markerPos -lt $originalPos -and
    $removePos -ge 0 -and $removePos -lt $originalPos) {
    Write-Host '[V61.23.5] PRECHECK PASSED: active V61.23.1 eager epoch block located structurally.'
    exit 0
}

if (!$text.Contains('_lastProduced.Remove((waiter.Memory, address))')) {
    Write-Host '[V61.23.5] PRECHECK PASSED: eager epoch deletion already absent.'
    exit 0
}

throw 'PRECHECK ERROR: eager _lastProduced removal exists outside the supported V61.23.1 Register insertion window.'
