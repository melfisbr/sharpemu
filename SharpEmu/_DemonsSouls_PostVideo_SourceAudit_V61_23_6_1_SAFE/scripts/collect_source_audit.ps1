param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $root "SharpEmu_V61_23_6_POSTVIDEO_SOURCE_AUDIT_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$agc=Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$wait=Join-Path $root 'src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs'
$vkCandidates=@(
    (Join-Path $root 'src\SharpEmu.Libs\Agc\VulkanBackendEmit.cs'),
    (Join-Path $root 'src\SharpEmu.Libs\Agc\VulkanVideoPresenter.cs'),
    (Join-Path $root 'src\SharpEmu.Core\Gpu\VulkanBackendEmit.cs'),
    (Join-Path $root 'src\SharpEmu.Core\Gpu\VulkanVideoPresenter.cs')
)

$e=[Collections.Generic.List[string]]::new()
$e.Add('SharpEmu V61.23.6.1.1 post-video source audit')
$e.Add("AgcExports_SHA256=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)")
$e.Add("GpuWaitRegistry_SHA256=$((Get-FileHash -LiteralPath $wait -Algorithm SHA256).Hash)")

Add-Matches $e $agc @(
    'agc.wait_suspended',
    'agc.wait_visibility_probe_satisfied',
    'agc.dispatch_noop',
    'agc.rt_sampled',
    'vk.ordered_action_fence_wait',
    'EVENT_FASTPATH',
    'zero-dimension',
    'gpu_resident',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'CollectDeadlockBroken',
    'RegisterLabelProducer',
    'CompleteLabelProducer'
) 14
Add-Matches $e $wait @(
    'CollectDeadlockBroken',
    'RecordProduced',
    'Register(ulong address',
    '_lastProduced',
    'SnapshotWatchedLabelsInRange'
) 18
foreach($vk in $vkCandidates) {
    if (Test-Path -LiteralPath $vk) {
        Add-Matches $e $vk @('ordered_action_fence_wait','gpu_resident','rt_sampled','VideoOut presented guest frame') 14
    }
}
$e | Set-Content -LiteralPath (Join-Path $out 'SOURCE_EVIDENCE.txt') -Encoding UTF8

# Inventory likely GPU/AGC source files for next patch.
Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Include '*.cs' |
    Where-Object {
        $_.FullName -match 'Agc|Gpu|Vulkan|VideoOut|Shader'
    } |
    ForEach-Object {
        '{0}`t{1}`t{2}' -f $_.FullName,$_.Length,(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Set-Content -LiteralPath (Join-Path $out 'GPU_SOURCE_INVENTORY.txt') -Encoding UTF8

# Git diff is evidence only; warnings must not fail collection.
Push-Location $root
try {
    (& git diff -- 'src/SharpEmu.Libs/Agc/GpuWaitRegistry.cs' 'src/SharpEmu.Libs/Agc/AgcExports.cs' 2>&1 | Out-String) |
        Set-Content -LiteralPath (Join-Path $out 'AGC_GIT_DIFF.txt') -Encoding UTF8
} finally { Pop-Location }

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V61.23.6.1.1] RESULT: $zip"
