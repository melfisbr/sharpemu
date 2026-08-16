param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $packageRoot

$files = @{
    'AgcExports.cs' = Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
    'VulkanVideoPresenter.cs' = Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
    'VulkanGuestGpuBackend.cs' = Join-Path $root 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'
    'IGuestGpuBackend.cs' = Join-Path $root 'src\SharpEmu.Libs\Gpu\IGuestGpuBackend.cs'
}

$expected = @{
    'AgcExports.cs' = '3F2B5FD1ECF4F7D3715C57E15393190615A1E8EC6FF62F2236FC712FF2D1B4B5'
    'VulkanVideoPresenter.cs' = 'F5FDDAAB23E192C90A14FA3B88C335903B60A2FFB6960716AEE746A0200B82AA'
    'VulkanGuestGpuBackend.cs' = '33E6A4E2424E3FED838C80F884D6EEE527F053A9361F1D0EECF9F3D64427A704'
    'IGuestGpuBackend.cs' = '28B49D708282E95F24080478B39D9EDC6183906757F0C473FEFB8E41E4AE45F6'
}

foreach ($name in $files.Keys) {
    $path = $files[$name]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('[V73.5] PRECHECK ERROR: missing {0}' -f $path)
    }

    $text = [IO.File]::ReadAllText($path)
    $already = Test-ContainsOrdinal -Text $text -Pattern 'SubmitOrderedGuestActionAfterQueueCompletion'
    if ($name -eq 'AgcExports.cs') {
        $already = Test-ContainsOrdinal -Text $text -Pattern 'requiresGpuBufferReadback: false'
    }
    elseif ($name -eq 'VulkanVideoPresenter.cs') {
        $already = Test-ContainsOrdinal -Text $text -Pattern 'RequiresQueueCompletionOnly'
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if (-not $already -and $hash -ne $expected[$name]) {
        throw (
            '[V73.5] PRECHECK ERROR: baseline changed for {0}. expected={1} actual={2}' -f
            $name,
            $expected[$name],
            $hash)
    }
}

$agcText = [IO.File]::ReadAllText($files['AgcExports.cs'])
$presenterText = [IO.File]::ReadAllText($files['VulkanVideoPresenter.cs'])

foreach ($marker in @(
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'pm4_producer_registered',
    'RecordProducedLabelsInRange(',
    'canonical-empty-fastpath'
)) {
    if (-not (Test-ContainsOrdinal -Text $agcText -Pattern $marker)) {
        throw ('[V73.5] PRECHECK ERROR: V73.4 AGC marker missing: {0}' -f $marker)
    }
}

foreach ($marker in @(
    'RequireGlobalVisibility: false,',
    'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)'
)) {
    if (-not (Test-ContainsOrdinal -Text $presenterText -Pattern $marker)) {
        throw ('[V73.5] PRECHECK ERROR: V73.3 presenter marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.5] PRECHECK PASSED.'
foreach ($name in @('AgcExports.cs','VulkanVideoPresenter.cs','VulkanGuestGpuBackend.cs','IGuestGpuBackend.cs')) {
    Write-Host (
        '[V73.5] {0}_SHA256={1}' -f
        $name,
        (Get-FileHash -LiteralPath $files[$name] -Algorithm SHA256).Hash)
}
Write-Host '[V73.5] V73.3 visibility fix and V73.4 provenance state confirmed.'
Write-Host '[V73.5] WRITE_DATA will keep queue completion; only dirty-buffer readback is removed.'
