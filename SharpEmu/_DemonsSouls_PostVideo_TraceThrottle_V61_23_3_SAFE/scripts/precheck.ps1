param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

$waitRegistry = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
if (!(Test-Path -LiteralPath $waitRegistry)) { throw 'PRECHECK ERROR: GpuWaitRegistry.cs missing.' }
if (!(Test-Path -LiteralPath $agc)) { throw 'PRECHECK ERROR: AgcExports.cs missing.' }

$waitText = [IO.File]::ReadAllText($waitRegistry)
if ($waitText.Contains('V61.23.1 label generation reset') -and
    !$waitText.Contains('V61.23.2 rollback of eager label generation reset')) {
    throw 'PRECHECK ERROR: V61.23.1 eager epoch deletion is still active. Apply V61.23.2 first.'
}

$agcText = [IO.File]::ReadAllText($agc)
if (!$agcText.Contains('SHARPEMU_LOG_AGC')) {
    throw 'PRECHECK ERROR: AGC diagnostic toggle not found.'
}

Write-Host '[V61.23.3] PRECHECK PASSED.'
Write-Host '[V61.23.3] V61.23.2 rollback state accepted; destructive full AGC tracing will be disabled for runtime test.'
