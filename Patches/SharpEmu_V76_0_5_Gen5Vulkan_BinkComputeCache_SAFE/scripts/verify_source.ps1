param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
Assert-PayloadInstalled $repo

$requiredMarkers = @(
    @{ Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Text='case "DsSwizzleB32"' },
    @{ Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs'; Text='case "VCvtPkU16U32"' },
    @{ Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs'; Text='case "VDot2cF32F16"' },
    @{ Rel='src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs'; Text='VulkanShaderBinaryCacheV7605' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'; Text='[COMPUTE-TIMING][V76.0.5]' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'; Text='VulkanPresentCadenceV7605.NoteSuccessfulPresent' }
)
foreach ($marker in $requiredMarkers) {
    $path = Join-Path $repo $marker.Rel
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.IndexOf($marker.Text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Marker ausente: $($marker.Text) em $($marker.Rel)"
    }
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_5_SOURCE_VERIFY_$stamp.txt"
Set-Content -LiteralPath $outPath -Value @(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    'PayloadHashes=PASSED',
    'RequiredMarkers=PASSED'
) -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
