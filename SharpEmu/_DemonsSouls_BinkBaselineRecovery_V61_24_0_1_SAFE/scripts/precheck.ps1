param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot

$required=@(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    'F:\JOGOSPS5\PPSA01341\eboot.bin',
    'F:\JOGOSPS5\PPSA01341\movies\ps_studios_logo.bk2'
)
foreach($p in $required) {
    if (!(Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "PRECHECK ERROR: required file missing: $p"
    }
}

$agc=Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$wait=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
if(!(Test-Path -LiteralPath $agc -PathType Leaf)){throw "PRECHECK ERROR: missing $agc"}
if(!(Test-Path -LiteralPath $wait -PathType Leaf)){throw "PRECHECK ERROR: missing $wait"}

$agcHash=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$waitHash=(Get-FileHash -LiteralPath $wait -Algorithm SHA256).Hash

# Exact V61.23.6.1.1 audit baseline supplied by the user.
if($agcHash -ne '4809CECC89E500B23B2993557BBF55FE9BF1F7022B1FAD97251A893141D8B083'){
    Write-Host "[V61.24.0.1] NOTE: AgcExports.cs moved since V61.23.6.1.1: $agcHash"
}
if($waitHash -ne '3D13C08D3627DD2D8B922F641C2AB9D9B1637B190C9F7C95CC8A50EFDEA17636'){
    Write-Host "[V61.24.0.1] NOTE: GpuWaitRegistry.cs moved since V61.23.6.1.1: $waitHash"
}

$wt=[IO.File]::ReadAllText($wait)
if ((Has-OrdinalIgnoreCase $wt 'V61.23.1 label generation reset') -or
    (Has-OrdinalIgnoreCase $wt '_lastProduced.Remove((waiter.Memory, address))')) {
    throw 'PRECHECK ERROR: obsolete V61.23.1 eager epoch deletion is active.'
}

# Critical correction vs V61.24.0:
# SHARPEMU_BINK_REALTIME_DEADLINE is OPTIONAL. The current rollback baseline
# is valid even when that compiled marker is absent.
$libs=Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.Libs.dll'
$hasDeadline=$false
if(Test-Path -LiteralPath $libs -PathType Leaf){
    foreach($s in (Read-BinaryStrings $libs)){
        if(Has-OrdinalIgnoreCase $s 'SHARPEMU_BINK_REALTIME_DEADLINE'){$hasDeadline=$true;break}
    }
}

Write-Host '[V61.24.0.1] PRECHECK PASSED.'
Write-Host "[V61.24.0.1] optional_runtime_deadline_marker=$hasDeadline"
Write-Host '[V61.24.0.1] V61.24.0 false prerequisite removed.'
