param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$kernel = Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$ampr = Join-Path $root 'src\SharpEmu.Libs\Ampr\AmprExports.cs'
foreach ($path in @($kernel,$ampr)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.7] PRECHECK ERROR: missing {0}' -f $path)
    }
}

$kernelText = [IO.File]::ReadAllText($kernel)
$amprText = [IO.File]::ReadAllText($ampr)

$kernelBase = '18D17309F550368C3A41B0EC9DB833E22A74DB59D7373B3DC4FBAB94879EB191'
$amprBase = 'A2AB94FACEFCB214AC6D39F0696BC8401AFF84559230C4E9770A0A48D95DD795'

$kernelInstalled = Test-ContainsOrdinal -Text $kernelText -Pattern 'SHARPEMU_DEMONSSOULS_UI_READ_SERIALIZATION_V73_7'
$amprInstalled = Test-ContainsOrdinal -Text $amprText -Pattern 'SHARPEMU_DEMONSSOULS_UI_AMPR_READ_FILTER_V73_7'

$kernelHash = (Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash
$amprHash = (Get-FileHash -LiteralPath $ampr -Algorithm SHA256).Hash

if (-not $kernelInstalled -and $kernelHash -ne $kernelBase) {
    throw ('[V73.7] PRECHECK ERROR: KernelMemoryCompatExports baseline changed. expected={0} actual={1}. Refusing full-file patch.' -f $kernelBase,$kernelHash)
}
if (-not $amprInstalled -and $amprHash -ne $amprBase) {
    throw ('[V73.7] PRECHECK ERROR: AmprExports baseline changed. expected={0} actual={1}. Refusing full-file patch.' -f $amprBase,$amprHash)
}

foreach ($marker in @(
    'sceKernelAprResolveFilepathsToIdsAndFileSizes',
    'sceKernelAprResolveFilepathsWithPrefixToIdsAndFileSizes',
    'sceKernelAprResolveFilepathsToIds',
    'sceKernelAprGetFileStat',
    'TryResolveAprFilepath(',
    'TryAcquireOpenFileStreamV59(',
    'KernelReadUnderscore('
)) {
    if (-not (Test-ContainsOrdinal -Text $kernelText -Pattern $marker)) {
        throw ('[V73.7] PRECHECK ERROR: kernel IO marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'sceAmprAprCommandBufferReadFile',
    'TryReadFileToGuestMemory(',
    'TraceAmprRead('
)) {
    if (-not (Test-ContainsOrdinal -Text $amprText -Pattern $marker)) {
        throw ('[V73.7] PRECHECK ERROR: AMPR marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.7] PRECHECK PASSED.'
Write-Host ('[V73.7] KernelMemoryCompatExports_SHA256={0}' -f $kernelHash)
Write-Host ('[V73.7] AmprExports_SHA256={0}' -f $amprHash)
Write-Host ('[V73.7] read_serialization_installed={0}' -f $kernelInstalled)
Write-Host ('[V73.7] ampr_filter_installed={0}' -f $amprInstalled)
Write-Host '[V73.7] EBOOT ABI audit says APR/AMPR register layout is already matched; no ABI stubs will be invented.'
