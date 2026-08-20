. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach($path in @($bridgePath,$presenterPath,$agcPath,$exceptionsPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$checks=[ordered]@{
    v213_dlss_retry=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
    v213_provider_active_telemetry=$b.Contains('[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active')
    v213_provider_retention=$b.Contains('provider_loaded=1')
    v213_provider_initialized_property=$b.Contains('public bool IsInitialized => _initialized;')
    v6729_source_identity=$b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v213_ram_identity=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    v74064_multicache=$a.Contains('TryGetLargeArraySnapshotV74064') -and $a.Contains('StoreLargeArraySnapshotV74064')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    presenter_precomposite_context=$p.Contains('V74.0.67.2.1 pre-composite consumer context')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.14] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$marker='V74.0.67.2.14 pre-composite command-buffer ownership'
$already=$b.Contains($marker)

$methodSignature="        private bool TryPrepareUpscalerPreCompositeForConsumer(`n"
$methodEndSignature="        private void EndUpscalerPreCompositeConsumer()`n"
$methodStart=$b.IndexOf($methodSignature,[StringComparison]::Ordinal)
$methodEnd=if($methodStart-ge 0){$b.IndexOf($methodEndSignature,$methodStart,[StringComparison]::Ordinal)}else{-1}
$methodOk=$methodStart-ge 0 -and $methodEnd-gt $methodStart
Write-Host "[V74.0.67.2.14] precheck_method_isolated=$($methodOk.ToString().ToLowerInvariant())"
if(!$methodOk){$failed=$true}

if($methodOk){
    $method=$b.Substring($methodStart,$methodEnd-$methodStart)
    $recordNeedle=@'
            RecordGuestImageForSampling(
                candidate.Source,
                PipelineStageFlags.ComputeShaderBit);
'@
    $recordCount=Count-Ordinal -Text $method -Needle $recordNeedle
    $batchInside=$method.Contains('BeginBatchedGuestCommands()')
    Write-Host "[V74.0.67.2.14] precheck_record_source_anchor_count=$recordCount"
    Write-Host "[V74.0.67.2.14] precheck_batch_acquire_inside_method=$($batchInside.ToString().ToLowerInvariant())"

    if($already){
        $beginIndex=$method.IndexOf('BeginBatchedGuestCommands()',[StringComparison]::Ordinal)
        $bindIndex=$method.IndexOf('_commandBuffer = preCompositeCommandBuffer;',[StringComparison]::Ordinal)
        $closeIndex=$method.IndexOf('CloseOpenTranslatedRenderPass();',[StringComparison]::Ordinal)
        $recordIndex=$method.IndexOf('RecordGuestImageForSampling(',[StringComparison]::Ordinal)
        $ordering=
            $beginIndex-ge 0 -and
            $bindIndex-gt $beginIndex -and
            $closeIndex-gt $bindIndex -and
            $recordIndex-gt $closeIndex
        Write-Host "[V74.0.67.2.14] precheck_patched_command_order=$($ordering.ToString().ToLowerInvariant())"
        if(!$ordering){$failed=$true}
    }else{
        if($recordCount-ne 1 -or $batchInside){$failed=$true}

        # Dry-run the essential insertion in memory before RUN_3 is allowed.
        $simulatedInsertion=@'
            // V74.0.67.2.14 pre-composite command-buffer ownership.
            var preCompositeBatchWasOpen = _batchOpen;
            var preCompositeCommandBuffer = BeginBatchedGuestCommands();
            _commandBuffer = preCompositeCommandBuffer;
            CloseOpenTranslatedRenderPass();

'@
        $simulated=$method.Replace($recordNeedle,$simulatedInsertion+$recordNeedle)
        $beginIndex=$simulated.IndexOf('BeginBatchedGuestCommands()',[StringComparison]::Ordinal)
        $bindIndex=$simulated.IndexOf('_commandBuffer = preCompositeCommandBuffer;',[StringComparison]::Ordinal)
        $closeIndex=$simulated.IndexOf('CloseOpenTranslatedRenderPass();',[StringComparison]::Ordinal)
        $recordIndex=$simulated.IndexOf('RecordGuestImageForSampling(',[StringComparison]::Ordinal)
        $ordering=
            $beginIndex-ge 0 -and
            $bindIndex-gt $beginIndex -and
            $closeIndex-gt $bindIndex -and
            $recordIndex-gt $closeIndex
        Write-Host "[V74.0.67.2.14] precheck_simulated_command_order=$($ordering.ToString().ToLowerInvariant())"
        if(!$ordering){$failed=$true}
    }
}

$executeSignature='        private void ExecuteOffscreenDrawCore(VulkanOffscreenGuestDraw work)'
$executeStart=$p.IndexOf($executeSignature,[StringComparison]::Ordinal)
$executeEnd=if($executeStart-ge 0){
    $p.IndexOf('        [MethodImpl(MethodImplOptions.NoInlining)]',$executeStart,[StringComparison]::Ordinal)
}else{-1}

$outerOrderOk=$false
if($executeStart-ge 0 -and $executeEnd-gt $executeStart){
    $execute=$p.Substring($executeStart,$executeEnd-$executeStart)
    $prepareIndex=$execute.IndexOf(
        'TryPrepareUpscalerPreCompositeForConsumer(work, targets)',
        [StringComparison]::Ordinal)
    $normalBegin=$execute.IndexOf(
        'commandBuffer = BeginBatchedGuestCommands();',
        [StringComparison]::Ordinal)
    $outerOrderOk=$prepareIndex-ge 0 -and $normalBegin-gt $prepareIndex
}
Write-Host "[V74.0.67.2.14] precheck_outer_prepare_before_normal_batch_begin=$($outerOrderOk.ToString().ToLowerInvariant())"
if(!$outerOrderOk){$failed=$true}

Write-Host "[V74.0.67.2.14] already_applied=$($already.ToString().ToLowerInvariant())"
Write-Host '[V74.0.67.2.14] crash_signature=provider-init-success_then_CmdPipelineBarrier_0xC0000005'
Write-Host '[V74.0.67.2.14] fix_strategy=bind-recording-batch-before-first-precomposite-vulkan-command'
Write-Host '[V74.0.67.2.14] native_provider_change=false'
Write-Host '[V74.0.67.2.14] ram_source_change=false'
Write-Host '[V74.0.67.2.14] hardcoded_guest_resource_address=false'

if($failed){throw '[V74.0.67.2.14] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.14] PRECHECK PASSED.'
