param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$kernel = Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$ampr = Join-Path $root 'src\SharpEmu.Libs\Ampr\AmprExports.cs'

foreach ($path in @($kernel,$ampr)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.7.1] PRECHECK ERROR: missing {0}' -f $path)
    }
}

$kernelText = [IO.File]::ReadAllText($kernel)
$amprText = [IO.File]::ReadAllText($ampr)

$currentKernelBaseline = '61D151DF2DDD8E9B1E7AF9451F1BDE3A7D109DB0B92F37F04D5BB60B4AD74103'
$kernelHash = (Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash

$installed =
    (Test-ContainsOrdinal -Text $kernelText -Pattern 'SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7_1') -and
    (Test-ContainsOrdinal -Text $kernelText -Pattern 'Monitor.Enter(stream);') -and
    (Test-ContainsOrdinal -Text $kernelText -Pattern 'Monitor.Exit(stream);')

if (-not $installed -and $kernelHash -ne $currentKernelBaseline) {
    throw (
        '[V73.7.1] PRECHECK ERROR: KernelMemoryCompatExports changed again after V73.0.13.1. expected={0} actual={1}. No source was modified.' -f
        $currentKernelBaseline,
        $kernelHash)
}

foreach ($marker in @(
    'SHARPEMU_TITLE_SCOPED_COMPAT_V73_0_13',
    'TryAcquireOpenFileStreamV59(',
    'KernelReadUnderscore(',
    'sceKernelAprResolveFilepathsToIdsAndFileSizes',
    'sceKernelAprResolveFilepathsWithPrefixToIdsAndFileSizes',
    'sceKernelAprResolveFilepathsToIds',
    'sceKernelAprGetFileStat',
    'TryResolveAprFilepath('
)) {
    if (-not (Test-ContainsOrdinal -Text $kernelText -Pattern $marker)) {
        throw ('[V73.7.1] PRECHECK ERROR: kernel IO marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'sceAmprAprCommandBufferReadFile',
    'TryReadFileToGuestMemory(',
    'TraceAmprRead('
)) {
    if (-not (Test-ContainsOrdinal -Text $amprText -Pattern $marker)) {
        throw ('[V73.7.1] PRECHECK ERROR: AMPR marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.7.1] PRECHECK PASSED.'
Write-Host ('[V73.7.1] KernelMemoryCompatExports_SHA256={0}' -f $kernelHash)
Write-Host ('[V73.7.1] read_serialization_installed={0}' -f $installed)
Write-Host '[V73.7.1] Current V73.0.13.1 title-isolation source is preserved.'
Write-Host '[V73.7.1] AmprExports.cs will not be modified.'
