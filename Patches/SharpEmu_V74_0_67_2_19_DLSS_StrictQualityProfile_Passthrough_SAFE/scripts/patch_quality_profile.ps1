. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

$marker='V74.0.67.2.19 strict requested quality profile passthrough'
if($b.Contains($marker)){
    Write-Host '[V74.0.67.2.19] Strict quality-profile passthrough already applied.'
    return
}

foreach($required in @(
    'private static HostUpscalerQuality RequestedUpscalerQuality()',
    '"balanced" => HostUpscalerQuality.Balanced',
    '"performance" => HostUpscalerQuality.Performance',
    'HostUpscalerQuality.UltraPerformance',
    'private bool TryPrepareUpscalerPreCompositeForConsumer(',
    'var requestedQuality = RequestedUpscalerQuality();',
    'var effectiveQuality =',
    'Quality = (int)effectiveQuality,',
    'V74.0.67.2.14 pre-composite command-buffer ownership'))
{
    if(!$b.Contains($required)){
        throw "[V74.0.67.2.19] Required accumulated quality marker missing: $required"
    }
}

$methodStartToken=@'
        private bool TryPrepareUpscalerPreCompositeForConsumer(
'@
$methodEndToken=@'
        private void EndUpscalerPreCompositeConsumer()
'@
$start=$b.IndexOf($methodStartToken,[StringComparison]::Ordinal)
$end=if($start-ge 0){
    $b.IndexOf($methodEndToken,$start,[StringComparison]::Ordinal)
}else{-1}

if($start-lt 0 -or $end-le $start){
    throw '[V74.0.67.2.19] Unable to isolate pre-composite method.'
}

$method=$b.Substring($start,$end-$start)
$requestedNeedle='var requestedQuality = RequestedUpscalerQuality();'
$requestedCount=Count-Ordinal -Text $method -Needle $requestedNeedle
$effectiveNeedle='var effectiveQuality ='
$effectiveCount=Count-Ordinal -Text $method -Needle $effectiveNeedle
$dispatchNeedle='Quality = (int)effectiveQuality,'
$dispatchCount=Count-Ordinal -Text $method -Needle $dispatchNeedle

if($requestedCount-ne 1 -or $effectiveCount-ne 1 -or $dispatchCount-ne 1){
    throw "[V74.0.67.2.19] Quality method shape mismatch requested=$requestedCount effective=$effectiveCount dispatch=$dispatchCount"
}

$effectiveIndex=$method.IndexOf($effectiveNeedle,[StringComparison]::Ordinal)
$lineStart=$method.LastIndexOf("`n",$effectiveIndex)
if($lineStart-lt 0){$lineStart=0}else{$lineStart++}
$semicolon=$method.IndexOf(';',$effectiveIndex)
if($semicolon-lt 0 -or $semicolon-$effectiveIndex-gt 4096){
    throw '[V74.0.67.2.19] Could not safely isolate effectiveQuality assignment.'
}

$oldAssignment=$method.Substring(
    $lineStart,
    $semicolon-$lineStart+1)

$equals=$oldAssignment.IndexOf('=')
if($equals-lt 0){
    throw '[V74.0.67.2.19] effectiveQuality assignment has no initializer.'
}

$expression=$oldAssignment.Substring(
    $equals+1,
    $oldAssignment.Length-$equals-2).Trim()

if([string]::IsNullOrWhiteSpace($expression)){
    throw '[V74.0.67.2.19] effectiveQuality initializer is empty.'
}

# Preserve the old auto-resolution decision only as telemetry. The actual
# provider quality becomes exactly the profile requested by the frontend/env.
$replacement=@"
            // V74.0.67.2.19 strict requested quality profile passthrough.
            //
            // The old pre-composite logic derived an "effective" preset from
            // the observed render/output ratio. That silently changed user
            // selections (for example UltraPerformance -> Quality at
            // 2560x1440 -> 3840x2160). Keep the inferred value only for
            // diagnostics, but send the requested enum unchanged to NGX/FSR.
            var autoResolvedQualityV74067219 = $expression;
            var effectiveQuality = requestedQuality;

            if (requestedQuality != autoResolvedQualityV74067219 &&
                (_upscalerPreCompositeDispatches < 16 ||
                 (_upscalerPreCompositeDispatches & 255) == 0))
            {
                Console.Error.WriteLine(
                    `$"[V74.0.67.2.19][UPSCALER][QUALITY_PROFILE] " +
                    `$"requested={requestedQuality.ToString().ToLowerInvariant()} " +
                    `$"previous_auto={autoResolvedQualityV74067219.ToString().ToLowerInvariant()} " +
                    `$"effective={effectiveQuality.ToString().ToLowerInvariant()} " +
                    `$"action=strict-requested-passthrough");
            }
"@

$method=$method.Substring(0,$lineStart)+$replacement+$method.Substring($semicolon+1)
$b=$b.Substring(0,$start)+$method+$b.Substring($end)

# Post-transform proof.
foreach($proof in @(
    'V74.0.67.2.19 strict requested quality profile passthrough',
    'var autoResolvedQualityV74067219 =',
    'var effectiveQuality = requestedQuality;',
    '[V74.0.67.2.19][UPSCALER][QUALITY_PROFILE]',
    'action=strict-requested-passthrough',
    'Quality = (int)effectiveQuality,',
    'V74.0.67.2.14 pre-composite command-buffer ownership'))
{
    if(!$b.Contains($proof)){
        throw "[V74.0.67.2.19] Post-transform proof missing: $proof"
    }
}

[IO.File]::WriteAllText(
    $bridgePath,
    (Restore-Newlines $b),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.19] STRICT REQUESTED QUALITY PROFILE PASSTHROUGH APPLIED.'
Write-Host '[V74.0.67.2.19] Quality/Balanced/Performance/UltraPerformance/DLAA will no longer be silently remapped by source ratio.'
