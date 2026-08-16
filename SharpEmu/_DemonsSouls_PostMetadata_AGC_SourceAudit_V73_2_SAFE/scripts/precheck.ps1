param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$waitRegistry = Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

$required = @($selfLoader, $agc, $waitRegistry, $presenter)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.2] PRECHECK ERROR: missing source file: {0}' -f $path)
    }
}

$selfText = [IO.File]::ReadAllText($selfLoader)
$agcText = [IO.File]::ReadAllText($agc)
$waitText = [IO.File]::ReadAllText($waitRegistry)

foreach ($marker in @(
    'DtSceNeededModuleGen5 = 0x61000045',
    'DtSceImportLibGen5 = 0x61000049',
    'case DtSceNeededModuleGen5:',
    'case DtSceImportLibGen5:'
)) {
    if (-not (Test-ContainsOrdinal -Text $selfText -Pattern $marker)) {
        throw ('[V73.2] PRECHECK ERROR: V73.1.1 metadata integration missing: {0}' -f $marker)
    }
}

$producerMarkers = @(
    'RecordProducedLabelsInRange',
    'producerCompletionAction',
    'RecordProduced('
)
foreach ($marker in $producerMarkers) {
    if (-not (Test-ContainsOrdinal -Text $agcText -Pattern $marker)) {
        throw ('[V73.2] PRECHECK ERROR: expected AGC producer lineage marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'RecordProduced(',
    'Canonicalize('
)) {
    if (-not (Test-ContainsOrdinal -Text $waitText -Pattern $marker)) {
        throw ('[V73.2] PRECHECK ERROR: expected GpuWaitRegistry marker missing: {0}' -f $marker)
    }
}

# V61.23.5 rollback invariant: the bad eager erase must never be active code.
$badActiveLines = New-Object System.Collections.Generic.List[string]
$waitLines = [IO.File]::ReadAllLines($waitRegistry)
for ($i = 0; $i -lt $waitLines.Length; $i++) {
    $trimmed = $waitLines[$i].Trim()
    if ($trimmed.StartsWith('//', [StringComparison]::Ordinal)) {
        continue
    }

    if ($trimmed.IndexOf(
        '_lastProduced.Remove((waiter.Memory, address))',
        [StringComparison]::Ordinal) -ge 0) {
        $badActiveLines.Add(('{0}: {1}' -f ($i + 1), $trimmed))
    }
}

if ($badActiveLines.Count -gt 0) {
    throw (
        '[V73.2] PRECHECK ERROR: V61.23.1 eager producer-history erase is active: {0}' -f
        ($badActiveLines -join ' | '))
}

$canonicalFastpath = Test-ContainsOrdinal -Text $agcText -Pattern 'canonical-empty-fastpath'

Write-Host '[V73.2] PRECHECK PASSED.'
Write-Host ('[V73.2] SelfLoader_SHA256={0}' -f (Get-FileHash -LiteralPath $selfLoader -Algorithm SHA256).Hash)
Write-Host ('[V73.2] AgcExports_SHA256={0}' -f (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)
Write-Host ('[V73.2] GpuWaitRegistry_SHA256={0}' -f (Get-FileHash -LiteralPath $waitRegistry -Algorithm SHA256).Hash)
Write-Host ('[V73.2] canonical_empty_fastpath_source={0}' -f $canonicalFastpath)
Write-Host '[V73.2] V61.23.5 producer-history rollback invariant confirmed.'
Write-Host '[V73.2] This package is evidence-only and will not modify repository source.'
