param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$presenter = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$agc = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'

foreach ($path in @($presenter, $agc, $selfLoader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.3] PRECHECK ERROR: missing source: {0}' -f $path)
    }
}

$presenterText = [IO.File]::ReadAllText($presenter)
$agcText = [IO.File]::ReadAllText($agc)
$selfText = [IO.File]::ReadAllText($selfLoader)

foreach ($marker in @(
    'internal sealed record VulkanOrderedGuestAction(',
    'bool RequireGlobalVisibility = false,',
    'bool RequiresGpuToCpuVisibility = true);',
    'public static long SubmitOrderedGuestActionWithVisibility('
)) {
    if (-not (Test-ContainsOrdinal -Text $presenterText -Pattern $marker)) {
        throw ('[V73.3] PRECHECK ERROR: presenter contract marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'requiresGpuToCpuVisibility: false',
    'requiresGpuToCpuVisibility: true'
)) {
    if (-not (Test-ContainsOrdinal -Text $agcText -Pattern $marker)) {
        throw ('[V73.3] PRECHECK ERROR: AGC visibility-direction marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'DtSceNeededModuleGen5 = 0x61000045',
    'DtSceImportLibGen5 = 0x61000049'
)) {
    if (-not (Test-ContainsOrdinal -Text $selfText -Pattern $marker)) {
        throw ('[V73.3] PRECHECK ERROR: V73.1.1 loader marker missing: {0}' -f $marker)
    }
}

$bugPattern =
    'new VulkanOrderedGuestAction\(\s*action,\s*debugName,\s*requiresGpuToCpuVisibility\)'
$buggy = [regex]::IsMatch(
    $presenterText,
    $bugPattern,
    [Text.RegularExpressions.RegexOptions]::Singleline)

$fixed =
    (Test-ContainsOrdinal -Text $presenterText -Pattern 'RequireGlobalVisibility: false,') -and
    (Test-ContainsOrdinal -Text $presenterText -Pattern 'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)')

$hash = (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$baselineHash = '534EB79448DF504500D1B018DA98714778FB13D06EC2FF887AC9544C2A1A6364'

if ($buggy -and $hash -ne $baselineHash) {
    throw (
        '[V73.3] PRECHECK ERROR: audited bug is present but presenter baseline changed. Expected {0}; actual {1}.' -f
        $baselineHash,
        $hash)
}

if (-not $buggy -and -not $fixed) {
    throw '[V73.3] PRECHECK ERROR: constructor is neither audited-bug form nor V73.3 fixed form.'
}

$state = 'audited-bug-present'
if ($fixed -and -not $buggy) {
    $state = 'already-fixed'
}

Write-Host '[V73.3] PRECHECK PASSED.'
Write-Host ('[V73.3] presenter_sha256={0}' -f $hash)
Write-Host ('[V73.3] visibility_binding_state={0}' -f $state)
Write-Host '[V73.3] arg3=RequireGlobalVisibility; arg4=RequiresGpuToCpuVisibility.'
Write-Host '[V73.3] ACQUIRE_MEM(false) will preserve queue order without GPU->CPU readback.'
