param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$direct = Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$sampler = Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'

foreach ($path in @($direct,$sampler)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.11] PRECHECK ERROR: missing {0}' -f $path)
    }
}

$directText = [IO.File]::ReadAllText($direct)
$samplerText = [IO.File]::ReadAllText($sampler)

$directBaseline = '054C0C4FA74F3B2D3599DCA36F0CC7F374088093DCF1ACE337B179A638EA34CD'
$samplerBaseline = 'DDB0C1FBDF353AE8922C73236FB83B186BDAC49750E47F3D814D6A0AD7495E75'

$directHash = (Get-FileHash -LiteralPath $direct -Algorithm SHA256).Hash
$samplerHash = (Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash

$installed =
    (Test-ContainsOrdinal -Text $samplerText -Pattern 'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT') -and
    (Test-ContainsOrdinal -Text $samplerText -Pattern '[V73.11][ENTRY_WAIT]') -and
    -not (Test-ContainsOrdinal -Text $directText -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE')

if (-not $installed) {
    if ($directHash -ne $directBaseline) {
        throw (
            '[V73.11] PRECHECK ERROR: DirectExecutionBackend changed. expected={0} actual={1}. No source modified.' -f
            $directBaseline,
            $directHash)
    }
    if ($samplerHash -ne $samplerBaseline) {
        throw (
            '[V73.11] PRECHECK ERROR: GuestSampler changed. expected={0} actual={1}. No source modified.' -f
            $samplerBaseline,
            $samplerHash)
    }
}

foreach ($marker in @(
    '_entryHostThreadId',
    'TryCaptureExtendedHostThreadContext(',
    'CTX_R14',
    'CTX_R15'
)) {
    if (-not (Test-ContainsOrdinal -Text $directText -Pattern $marker)) {
        throw ('[V73.11] PRECHECK ERROR: DirectExecutionBackend structural marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'SnapshotGuestThreads()',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    '[V73.9][UI_RIP] counts'
)) {
    if (-not (Test-ContainsOrdinal -Text $samplerText -Pattern $marker)) {
        throw ('[V73.11] PRECHECK ERROR: GuestSampler structural marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.11] PRECHECK PASSED.'
Write-Host ('[V73.11] DirectExecutionBackend_SHA256={0}' -f $directHash)
Write-Host ('[V73.11] GuestSampler_SHA256={0}' -f $samplerHash)
Write-Host ('[V73.11] entry_wait_probe_installed={0}' -f $installed)
Write-Host '[V73.11] V73.10 usleep HLE preference will be rolled back.'
Write-Host '[V73.11] V73.9 UI probe remains and will also observe the initial entry thread.'
