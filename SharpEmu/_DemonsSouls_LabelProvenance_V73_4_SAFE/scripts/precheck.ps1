param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$waitRegistry = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'

foreach ($path in @($agc, $presenter, $waitRegistry)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.4] PRECHECK ERROR: missing source: {0}' -f $path)
    }
}

$agcText = [IO.File]::ReadAllText($agc)
$presenterText = [IO.File]::ReadAllText($presenter)
$waitText = [IO.File]::ReadAllText($waitRegistry)

$agcHash = (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$agcBaseline = 'AED440CE2307DE6103C28889303F41919D605F64B105A0D853B9E9AF4A948679'
$instrumented =
    (Test-ContainsOrdinal -Text $agcText -Pattern 'SHARPEMU_TRACE_LABEL_PROVENANCE') -and
    (Test-ContainsOrdinal -Text $agcText -Pattern '[V73.4][LABEL]')

if (-not $instrumented -and $agcHash -ne $agcBaseline) {
    throw (
        '[V73.4] PRECHECK ERROR: AgcExports baseline changed. Expected {0}; actual {1}. Refusing blind instrumentation.' -f
        $agcBaseline,
        $agcHash)
}

foreach ($marker in @(
    'QueueComputeGlobalWritePublication(',
    'NotifyGpuMemoryWriteback(',
    'ScheduleRuntimeCorrectionWaitVisibilityProbe(',
    'SubmitGlobalOrderedGuestAction(',
    'RecordProducedLabelsInRange(',
    'RegisterLabelProducer(',
    'canonical-empty-fastpath',
    'var hasObservedProducer =',
    'eventTypeRaw & 0x3Fu'
)) {
    if (-not (Test-ContainsOrdinal -Text $agcText -Pattern $marker)) {
        throw ('[V73.4] PRECHECK ERROR: AGC semantic anchor missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'RequireGlobalVisibility: false,',
    'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)'
)) {
    if (-not (Test-ContainsOrdinal -Text $presenterText -Pattern $marker)) {
        throw ('[V73.4] PRECHECK ERROR: V73.3 presenter fix missing: {0}' -f $marker)
    }
}

$badActive = New-Object System.Collections.Generic.List[string]
foreach ($line in [IO.File]::ReadAllLines($waitRegistry)) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('//', [StringComparison]::Ordinal)) {
        continue
    }

    if ($trimmed.IndexOf(
        '_lastProduced.Remove((waiter.Memory, address))',
        [StringComparison]::Ordinal) -ge 0) {
        $badActive.Add($trimmed)
    }
}
if ($badActive.Count -gt 0) {
    throw '[V73.4] PRECHECK ERROR: bad V61.23.1 producer-history erase is active.'
}

$state = if ($instrumented) { 'already-instrumented' } else { 'baseline-ready' }

Write-Host '[V73.4] PRECHECK PASSED.'
Write-Host ('[V73.4] AgcExports_SHA256={0}' -f $agcHash)
Write-Host ('[V73.4] instrumentation_state={0}' -f $state)
Write-Host '[V73.4] V73.3 ordered-visibility fix confirmed.'
Write-Host '[V73.4] Producer history and canonical-empty-fastpath remain unchanged.'
