param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot

$exe=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$libs=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.Libs.dll'
$game='F:\JOGOSPS5\PPSA01341\eboot.bin'
$movie='F:\JOGOSPS5\PPSA01341\movies\ps_studios_logo.bk2'

foreach($p in @($exe,$libs,$game,$movie)) {
    if (!(Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "PRECHECK ERROR: required file missing: $p"
    }
}

# Confirm the known runtime deadline control exists in the currently built Libs.
$bytes=[IO.File]::ReadAllBytes($libs)
$ascii=[Text.Encoding]::ASCII.GetString($bytes)
$unicode=[Text.Encoding]::Unicode.GetString($bytes)
$hasDeadline=(Test-ContainsOrdinal $ascii 'SHARPEMU_BINK_REALTIME_DEADLINE') -or
             (Test-ContainsOrdinal $unicode 'SHARPEMU_BINK_REALTIME_DEADLINE')
if (!$hasDeadline) {
    throw 'PRECHECK ERROR: current SharpEmu.Libs.dll does not contain SHARPEMU_BINK_REALTIME_DEADLINE.'
}

$wait=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if (Test-Path -LiteralPath $wait) {
    $wt=[IO.File]::ReadAllText($wait)
    if ((Test-ContainsOrdinal $wt 'V61.23.1 label generation reset') -or
        (Test-ContainsOrdinal $wt '_lastProduced.Remove((waiter.Memory, address))')) {
        throw 'PRECHECK ERROR: obsolete V61.23.1 eager epoch logic is active.'
    }
}

Write-Host '[V61.24.0] PRECHECK PASSED.'
Write-Host '[V61.24.0] Known Bink realtime-deadline control detected in current runtime.'
Write-Host '[V61.24.0] This package does not guess a UV swap or fabricate AJM/PCM audio.'
