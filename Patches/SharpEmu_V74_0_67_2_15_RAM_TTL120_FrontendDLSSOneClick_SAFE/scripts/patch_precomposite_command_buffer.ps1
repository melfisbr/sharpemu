. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

$marker='V74.0.67.2.14 pre-composite command-buffer ownership'
if($b.Contains($marker)){
    Write-Host '[V74.0.67.2.14] Pre-composite command-buffer ownership already applied.'
    return
}

$methodSignature=@'
        private bool TryPrepareUpscalerPreCompositeForConsumer(
'@
$methodEndSignature=@'
        private void EndUpscalerPreCompositeConsumer()
'@

$methodStart=$b.IndexOf($methodSignature,[StringComparison]::Ordinal)
$methodEnd=if($methodStart-ge 0){
    $b.IndexOf($methodEndSignature,$methodStart,[StringComparison]::Ordinal)
}else{-1}
if($methodStart-lt 0 -or $methodEnd-le $methodStart){
    throw '[V74.0.67.2.14] Unable to isolate TryPrepareUpscalerPreCompositeForConsumer.'
}
$method=$b.Substring($methodStart,$methodEnd-$methodStart)

$anchor=@'
            RecordGuestImageForSampling(
                candidate.Source,
                PipelineStageFlags.ComputeShaderBit);
'@

$count=Count-Ordinal -Text $method -Needle $anchor
if($count-ne 1){
    throw "[V74.0.67.2.14] Command-recording anchor count=$count expected=1"
}
if($method.Contains('BeginBatchedGuestCommands()')){
    throw '[V74.0.67.2.14] Existing batch acquisition found inside TryPrepare; refusing duplicate/unknown layout.'
}

$insertion=@'
            // V74.0.67.2.14 pre-composite command-buffer ownership.
            //
            // TryPrepareUpscalerPreCompositeForConsumer is invoked before the
            // normal ExecuteOffscreenDrawCore BeginBatchedGuestCommands call so
            // the DLSS output can participate in texture descriptor translation.
            // Therefore _commandBuffer may still refer to the presentation
            // command buffer or another non-recording handle at this point.
            //
            // Acquire/reuse the shared guest batch and rebind _commandBuffer
            // before ANY RecordGuest* call, VkCmdPipelineBarrier, or NGX
            // Create/Evaluate operation.
            var preCompositeBatchWasOpen = _batchOpen;
            var preCompositeCommandBuffer = BeginBatchedGuestCommands();
            _commandBuffer = preCompositeCommandBuffer;
            CloseOpenTranslatedRenderPass();

            if (!_batchOpen || preCompositeCommandBuffer.Handle == 0)
            {
                _upscalerOutputReset = true;
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_command_buffer_unavailable");
                return false;
            }

            if (_upscalerPreCompositeDispatches < 8)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.14][UPSCALER][COMMAND_BUFFER] " +
                    $"state=recording handle=0x{(ulong)preCompositeCommandBuffer.Handle:X16} " +
                    $"batch_was_open={(preCompositeBatchWasOpen ? 1 : 0)} " +
                    $"batch_open={(_batchOpen ? 1 : 0)}");
            }

'@

$method=$method.Replace($anchor,$insertion+$anchor)
$b=$b.Substring(0,$methodStart)+$method+$b.Substring($methodEnd)

[IO.File]::WriteAllText(
    $bridgePath,
    (Restore-Newlines $b),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.14] PRE-COMPOSITE COMMAND-BUFFER OWNERSHIP PATCH APPLIED.'
