. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot
$bridgePath = Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b = Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

$changed = $false

# ---------------------------------------------------------------------------
# 1) Preserve provider extension-query failures as real failures.
# ---------------------------------------------------------------------------
if (!$b.Contains('V74.0.67.2.8 strict provider extension negotiation')) {
    $oldRead = @'
                var length = getter(instance, physicalDevice, buffer, capacity);
                if (length <= 0 || length >= capacity)
                {
                    return [];
                }

                var text = Encoding.UTF8.GetString(new ReadOnlySpan<byte>(buffer, length));
'@

    $newRead = @'
                // V74.0.67.2.8 strict provider extension negotiation
                //
                // Native providers use negative values to report a failed NGX
                // extension/support query. Treating every <=0 result as "no
                // extensions" silently allowed VkInstance/VkDevice creation to
                // continue without a valid provider contract.
                var length = getter(instance, physicalDevice, buffer, capacity);
                if (length < 0)
                {
                    throw new InvalidOperationException(
                        $"native Vulkan upscaler extension query failed: result={length}");
                }
                if (length == 0)
                {
                    return [];
                }
                if (length >= capacity)
                {
                    throw new InvalidOperationException(
                        $"native Vulkan upscaler extension list exceeds capacity: result={length} capacity={capacity}");
                }

                var text = Encoding.UTF8.GetString(new ReadOnlySpan<byte>(buffer, length));
'@

    $count = Count-Ordinal -Text $b -Needle $oldRead
    if ($count -ne 1) {
        throw "[V74.0.67.2.8.2] Strict extension negotiation anchor count=$count; expected 1."
    }
    $b = $b.Replace($oldRead, $newRead)
    $changed = $true
}

# ---------------------------------------------------------------------------
# 2) Consolidate V74.0.67.2.7 source disambiguation.
# ---------------------------------------------------------------------------
if (!$b.Contains('V74.0.67.2.7 stable temporal source disambiguation')) {
    $oldBlock = @'
            var bestCount = ordered.Count(item =>
                (ulong)item.Source.Width * item.Source.Height == bestArea);
            if (bestCount > 1 && explicitSource == 0)
            {
                reason = "ambiguous_precomposite_source";
                return false;
            }

            candidate = ordered[0];
            reason = "ready";
            return true;
'@

    $newBlock = @'
            var bestCount = ordered.Count(item =>
                (ulong)item.Source.Width * item.Source.Height == bestArea);

            // V74.0.67.2.7 stable temporal source disambiguation
            //
            // Same-area scene candidates are no longer rejected merely because
            // more than one exists. V74.0.67.2.5 and V74.0.67.2.6 maintain
            // independent depth and motion confidence per source. Use those
            // proven temporal states while preserving the explicit-source
            // override and conservative ambiguity fallback.
            if (bestCount > 1 && explicitSource == 0)
            {
                const int minTemporalConfidence = 3;
                const int minConfidenceAdvantage = 2;
                const int minSumAdvantage = 4;

                var largest = ordered
                    .Where(item =>
                        (ulong)item.Source.Width * item.Source.Height == bestArea)
                    .Select(item =>
                    {
                        var depthConfidence =
                            _upscalerDepthStableBySourceV7406725.TryGetValue(
                                item.Source.Address,
                                out var depthState)
                                ? depthState.Confidence
                                : 0;
                        var motionConfidence =
                            _upscalerGlobalMotionStateV7406726.TryGetValue(
                                item.Source.Address,
                                out var motionState)
                                ? motionState.Confidence
                                : 0;
                        var temporalConfidence =
                            Math.Min(depthConfidence, motionConfidence);
                        var confidenceSum =
                            depthConfidence + motionConfidence;

                        return new
                        {
                            Candidate = item,
                            DepthConfidence = depthConfidence,
                            MotionConfidence = motionConfidence,
                            TemporalConfidence = temporalConfidence,
                            ConfidenceSum = confidenceSum
                        };
                    })
                    .OrderByDescending(static item => item.TemporalConfidence)
                    .ThenByDescending(static item => item.ConfidenceSum)
                    .ThenByDescending(static item =>
                        item.Candidate.Source.ContentGeneration)
                    .ThenByDescending(static item => item.Candidate.Binding.Serial)
                    .ToArray();

                var winner = largest[0];
                var runnerUp = largest.Length > 1 ? largest[1] : null;

                var confidenceAdvantage = runnerUp is null
                    ? winner.TemporalConfidence
                    : winner.TemporalConfidence - runnerUp.TemporalConfidence;
                var sumAdvantage = runnerUp is null
                    ? winner.ConfidenceSum
                    : winner.ConfidenceSum - runnerUp.ConfidenceSum;

                if (winner.TemporalConfidence < minTemporalConfidence ||
                    runnerUp is not null &&
                    confidenceAdvantage < minConfidenceAdvantage &&
                    sumAdvantage < minSumAdvantage)
                {
                    var runnerSource = runnerUp is null
                        ? 0UL
                        : runnerUp.Candidate.Source.Address;
                    var runnerDepth = runnerUp is null
                        ? 0
                        : runnerUp.DepthConfidence;
                    var runnerMotion = runnerUp is null
                        ? 0
                        : runnerUp.MotionConfidence;
                    var runnerTemporal = runnerUp is null
                        ? 0
                        : runnerUp.TemporalConfidence;

                    Console.Error.WriteLine(
                        $"[V74.0.67.2.7][UPSCALER][SOURCE_RESOLVE] " +
                        $"state=ambiguous area={bestArea} candidates={bestCount} " +
                        $"winner=0x{winner.Candidate.Source.Address:X16} " +
                        $"depth_conf={winner.DepthConfidence} " +
                        $"motion_conf={winner.MotionConfidence} " +
                        $"temporal_conf={winner.TemporalConfidence} " +
                        $"runner=0x{runnerSource:X16} " +
                        $"runner_depth_conf={runnerDepth} " +
                        $"runner_motion_conf={runnerMotion} " +
                        $"runner_temporal_conf={runnerTemporal} " +
                        $"confidence_advantage={confidenceAdvantage} " +
                        $"sum_advantage={sumAdvantage}");

                    reason = "ambiguous_precomposite_source";
                    return false;
                }

                candidate = winner.Candidate;
                Console.Error.WriteLine(
                    $"[V74.0.67.2.7][UPSCALER][SOURCE_RESOLVE] " +
                    $"state=selected source=0x{candidate.Source.Address:X16} " +
                    $"size={candidate.Source.Width}x{candidate.Source.Height} " +
                    $"content_gen={candidate.Source.ContentGeneration} " +
                    $"depth=0x{candidate.Depth.Address:X16} " +
                    $"motion=0x{candidate.Motion.Address:X16} " +
                    $"depth_conf={winner.DepthConfidence} " +
                    $"motion_conf={winner.MotionConfidence} " +
                    $"temporal_conf={winner.TemporalConfidence} " +
                    $"confidence_advantage={confidenceAdvantage} " +
                    $"sum_advantage={sumAdvantage} " +
                    $"candidates={bestCount}");
                reason = "ready";
                return true;
            }

            candidate = ordered[0];
            reason = "ready";
            return true;
'@

    $count = Count-Ordinal -Text $b -Needle $oldBlock
    if ($count -ne 1) {
        throw "[V74.0.67.2.8.2] V74.0.67.2.7 ambiguity anchor count=$count; expected 1."
    }
    $b = $b.Replace($oldBlock, $newBlock)
    $changed = $true
}

if (!$changed) {
    Write-Host '[V74.0.67.2.8.2] Managed Vulkan bridge already contains all consolidated corrections.'
    return
}

[IO.File]::WriteAllText(
    $bridgePath,
    (Restore-Newlines $b),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.8.2] Managed Vulkan/DLSS integration corrections applied.'
