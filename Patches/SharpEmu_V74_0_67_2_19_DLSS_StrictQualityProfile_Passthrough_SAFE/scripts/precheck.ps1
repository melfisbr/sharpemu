. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontendPath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$settingsPath=Join-Path $repo 'src\SharpEmu.GUI\GuiSettings.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'

foreach($path in @($bridgePath,$frontendPath,$settingsPath,$exceptionsPath,$agcPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing source: $path"
    }
}

$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontendPath))
$s=Normalize-Lf ([IO.File]::ReadAllText($settingsPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))

$checks=[ordered]@{
    requested_quality_parser=$b.Contains('private static HostUpscalerQuality RequestedUpscalerQuality()')
    parser_quality=$b.Contains('HostUpscalerQuality.Quality')
    parser_balanced=$b.Contains('"balanced" => HostUpscalerQuality.Balanced')
    parser_performance=$b.Contains('"performance" => HostUpscalerQuality.Performance')
    parser_ultra=$b.Contains('HostUpscalerQuality.UltraPerformance')
    precomposite_method=$b.Contains('private bool TryPrepareUpscalerPreCompositeForConsumer(')
    requested_assignment=$b.Contains('var requestedQuality = RequestedUpscalerQuality();')
    effective_assignment=$b.Contains('var effectiveQuality =')
    dispatch_uses_effective=$b.Contains('Quality = (int)effectiveQuality,')
    v214_command_buffer=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    frontend_quality_env=$f.Contains('"SHARPEMU_VK_UPSCALER_QUALITY"')
    frontend_quality_setting=$s.Contains('public string UpscalerQuality')
    v215_ttl=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.19] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$already=$b.Contains('V74.0.67.2.19 strict requested quality profile passthrough')
Write-Host "[V74.0.67.2.19] quality_profile_already=$($already.ToString().ToLowerInvariant())"

$methodStartToken="        private bool TryPrepareUpscalerPreCompositeForConsumer(`n"
$methodEndToken="        private void EndUpscalerPreCompositeConsumer()`n"
$start=$b.IndexOf($methodStartToken,[StringComparison]::Ordinal)
$end=if($start-ge 0){$b.IndexOf($methodEndToken,$start,[StringComparison]::Ordinal)}else{-1}
$methodOk=$start-ge 0 -and $end-gt $start
Write-Host "[V74.0.67.2.19] precheck_method_isolated=$($methodOk.ToString().ToLowerInvariant())"
if(!$methodOk){$failed=$true}

if($methodOk){
    $method=$b.Substring($start,$end-$start)
    $requestedCount=Count-Ordinal -Text $method -Needle 'var requestedQuality = RequestedUpscalerQuality();'
    $effectiveCount=Count-Ordinal -Text $method -Needle 'var effectiveQuality ='
    $dispatchCount=Count-Ordinal -Text $method -Needle 'Quality = (int)effectiveQuality,'

    Write-Host "[V74.0.67.2.19] precheck_requested_count=$requestedCount"
    Write-Host "[V74.0.67.2.19] precheck_effective_count=$effectiveCount"
    Write-Host "[V74.0.67.2.19] precheck_dispatch_count=$dispatchCount"

    if($requestedCount-ne 1 -or $effectiveCount-ne 1 -or $dispatchCount-ne 1){
        $failed=$true
    }

    if($already){
        $strict=$method.Contains('var effectiveQuality = requestedQuality;')
        Write-Host "[V74.0.67.2.19] precheck_strict_passthrough=$($strict.ToString().ToLowerInvariant())"
        if(!$strict){$failed=$true}
    }else{
        $effectiveIndex=$method.IndexOf('var effectiveQuality =',[StringComparison]::Ordinal)
        $semicolon=if($effectiveIndex-ge 0){$method.IndexOf(';',$effectiveIndex)}else{-1}
        $safe=$effectiveIndex-ge 0 -and $semicolon-gt $effectiveIndex -and $semicolon-$effectiveIndex-le 4096
        Write-Host "[V74.0.67.2.19] precheck_effective_assignment_safe=$($safe.ToString().ToLowerInvariant())"
        if(!$safe){$failed=$true}
    }
}

# Cumulative V2.18 state can be Ready or Applied, never partial.
$v218Markers=@(
    'V74.0.67.2.18 BPE head2 end-sentinel recovery',
    'TryRecoverDemonBpeHead2EndSentinelFaultV74067218')
$v218Present=0
foreach($m in $v218Markers){if($e.Contains($m)){$v218Present++}}
$v218State=if($v218Present-eq 0){'Ready'}elseif($v218Present-eq $v218Markers.Count){'Applied'}else{'Partial'}
Write-Host "[V74.0.67.2.19] v218_state=$v218State"
if($v218State-eq 'Partial'){$failed=$true}

Write-Host '[V74.0.67.2.19] quality_contract=frontend-requested-profile-is-provider-profile'
Write-Host '[V74.0.67.2.19] input_source_policy=best-valid-temporal-source-unchanged'
Write-Host '[V74.0.67.2.19] silent_profile_remap=false'
Write-Host '[V74.0.67.2.19] native_provider_mapping_change=false'

if($failed){throw '[V74.0.67.2.19] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.19] PRECHECK PASSED.'
