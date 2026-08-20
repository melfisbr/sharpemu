. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$package=Get-PackageRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$methodSignature="        private bool TryPrepareUpscalerPreCompositeForConsumer(`n"
$methodEndSignature="        private void EndUpscalerPreCompositeConsumer()`n"
$methodStart=$b.IndexOf($methodSignature,[StringComparison]::Ordinal)
$methodEnd=if($methodStart-ge 0){$b.IndexOf($methodEndSignature,$methodStart,[StringComparison]::Ordinal)}else{-1}
$method=if($methodStart-ge 0 -and $methodEnd-gt $methodStart){$b.Substring($methodStart,$methodEnd-$methodStart)}else{''}

$beginIndex=$method.IndexOf('BeginBatchedGuestCommands()',[StringComparison]::Ordinal)
$bindIndex=$method.IndexOf('_commandBuffer = preCompositeCommandBuffer;',[StringComparison]::Ordinal)
$closeIndex=$method.IndexOf('CloseOpenTranslatedRenderPass();',[StringComparison]::Ordinal)
$recordIndex=$method.IndexOf('RecordGuestImageForSampling(',[StringComparison]::Ordinal)
$commandOrder=
    $beginIndex-ge 0 -and
    $bindIndex-gt $beginIndex -and
    $closeIndex-gt $bindIndex -and
    $recordIndex-gt $closeIndex

$executeSignature='        private void ExecuteOffscreenDrawCore(VulkanOffscreenGuestDraw work)'
$executeStart=$p.IndexOf($executeSignature,[StringComparison]::Ordinal)
$executeEnd=if($executeStart-ge 0){
    $p.IndexOf('        [MethodImpl(MethodImplOptions.NoInlining)]',$executeStart,[StringComparison]::Ordinal)
}else{-1}
$outerOrder=$false
if($executeStart-ge 0 -and $executeEnd-gt $executeStart){
    $execute=$p.Substring($executeStart,$executeEnd-$executeStart)
    $prepareIndex=$execute.IndexOf('TryPrepareUpscalerPreCompositeForConsumer(work, targets)',[StringComparison]::Ordinal)
    $normalBegin=$execute.IndexOf('commandBuffer = BeginBatchedGuestCommands();',[StringComparison]::Ordinal)
    $outerOrder=$prepareIndex-ge 0 -and $normalBegin-gt $prepareIndex
}

$launcher=Normalize-Lf ([IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1')))

$releaseHost=Find-ReleaseHost -Repo $repo
$provider=$null;$ngx=$null
if($null-ne $releaseHost){
    $provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
    $ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
}

$checks=[ordered]@{
    command_buffer_marker=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    command_buffer_batch_acquire=$method.Contains('var preCompositeCommandBuffer = BeginBatchedGuestCommands();')
    command_buffer_rebind=$method.Contains('_commandBuffer = preCompositeCommandBuffer;')
    command_buffer_renderpass_close=$method.Contains('CloseOpenTranslatedRenderPass();')
    command_buffer_nonzero_guard=$method.Contains('preCompositeCommandBuffer.Handle == 0')
    command_buffer_runtime_telemetry=$method.Contains('[V74.0.67.2.14][UPSCALER][COMMAND_BUFFER]')
    command_buffer_before_first_sampling_record=$commandOrder
    outer_prepare_still_before_normal_batch_begin=$outerOrder
    v213_dlss_retry=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
    v213_ram_identity=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    launcher_dlss=$launcher.Contains("$env:SHARPEMU_VK_UPSCALER='dlss'")
    launcher_array_ttl_120s=$launcher.Contains("$env:SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS='120000'")
    launcher_texture_ttl_120s=$launcher.Contains("$env:SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS='120000'")
    release_host_exists=$null-ne $releaseHost
    deployed_provider_exists=$null-ne $provider -and (Test-Path -LiteralPath $provider)
    deployed_nvngx_exists=$null-ne $ngx -and (Test-Path -LiteralPath $ngx)
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.14] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

if($null-ne $provider -and (Test-Path -LiteralPath $provider)){
    foreach($export in @(
        'sharpemu_vk_upscaler_get_instance_extensions',
        'sharpemu_vk_upscaler_get_device_extensions',
        'sharpemu_vk_upscaler_get_capabilities',
        'sharpemu_vk_upscaler_initialize',
        'sharpemu_vk_upscaler_dispatch',
        'sharpemu_vk_upscaler_shutdown',
        'sharpemu_vk_upscaler_get_last_error')){
        $ok=Test-NativeExport -DllPath $provider -ExportName $export
        $line="[V74.0.67.2.14] export_$export=$($ok.ToString().ToLowerInvariant())"
        Write-Host $line
        $result.Add($line)
        if(!$ok){$failed=$true}
    }
}

$result.Add('[V74.0.67.2.14] CRASH_ROOT_CAUSE=pre-composite ran before outer batch command-buffer assignment')
$result.Add('[V74.0.67.2.14] EXPECTED_RUNTIME_1=COMMAND_BUFFER state=recording')
$result.Add('[V74.0.67.2.14] EXPECTED_RUNTIME_2=create_dlss_feature then evaluate_dlss without CmdPipelineBarrier host AV')
$result.Add('[V74.0.67.2.14] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')
$result.Add('[V74.0.67.2.14] RAM_TTL_TARGET=ARRAY_CACHE_OWNER ttl_ms=120000')

if($failed){throw '[V74.0.67.2.14] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.14] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.14] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_14_DLSS_COMMAND_BUFFER_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_14_DLSS_COMMAND_BUFFER_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.14] ResultZip=$zip"
