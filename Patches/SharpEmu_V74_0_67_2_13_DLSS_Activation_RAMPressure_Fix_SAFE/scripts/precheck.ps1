. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
foreach($path in @($bridgePath,$presenterPath,$agcPath,$exceptionsPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing required source: $path"}
}
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$checks=[ordered]@{
    v2102_last_error=$b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')
    v2102_last_error_property=$b.Contains('public string LastError')
    v6729_source_identity=$b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v6728_extension_negotiation=$b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    v6725_depth=$b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_motion=$b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    precomposite=$b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    large_array_singleflight=$a.Contains('V74015LargeArraySnapshotKey') -and $a.Contains('[V74.0.15][ARRAY_SINGLEFLIGHT]')
    bpe_v211=$e.Contains('V74.0.67.2.11 BPE end-sentinel return repair')
}
$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.13] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$dlssAlready=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
$ramAlready=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
$bpeSecondary=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
Write-Host "[V74.0.67.2.13] dlss_activation_already=$($dlssAlready.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13] ram_pressure_already=$($ramAlready.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13] bpe_secondary_already=$($bpeSecondary.ToString().ToLowerInvariant())"

if(!$dlssAlready){
    foreach($anchor in @(
        '        private string _upscalerInitFailureReason = string.Empty;',
        '            public int LastInitializeResult { get; private set; }',
        'state=retry_size_change',
        'return _nativeUpscaler is not null;'
    )){
        $count=Count-Ordinal -Text $b -Needle $anchor
        Write-Host "[V74.0.67.2.13] bridge_anchor_count=$count token=$anchor"
        if($count-lt 1){$failed=$true}
    }
}

if(!$ramAlready){
    $keyField=Count-Ordinal -Text $a -Needle '        long WriteGeneration,'
    $ttlCount=[regex]::Matches($a,'v74015Age\s*<=\s*([A-Za-z_][A-Za-z0-9_]*)').Count
    $tiledCount=Count-Ordinal -Text $a -Needle @'
                            sourceWidth,
                            sliceBytes,
                            arrayLayers,
                            hasWriteGeneration ? writeGeneration : -1,
                            Tiled: true);
'@
    $linearCount=Count-Ordinal -Text $a -Needle @'
                        sourceWidth,
                        layerBytes,
                        arrayLayers,
                        hasWriteGeneration ? writeGeneration : -1,
                        Tiled: false);
'@
    Write-Host "[V74.0.67.2.13] ram_anchor_key_field=$keyField"
    Write-Host "[V74.0.67.2.13] ram_anchor_ttl=$ttlCount"
    Write-Host "[V74.0.67.2.13] ram_anchor_tiled=$tiledCount"
    Write-Host "[V74.0.67.2.13] ram_anchor_linear=$linearCount"
    if($keyField-ne 1 -or $ttlCount-lt 2 -or $tiledCount-ne 1 -or $linearCount-ne 1){$failed=$true}
}

Write-Host '[V74.0.67.2.13] dlss_strategy=explicit-feature-path+bounded-init-retry+provider-retention'
Write-Host '[V74.0.67.2.13] ram_strategy=sparse-content-key+60s-min-reuse-window'
Write-Host '[V74.0.67.2.13] dlss_truth=selected=dlss,state=active,dlss_dispatches>0'
Write-Host '[V74.0.67.2.13] hardcoded_guest_resource_address=false'
if($failed){throw '[V74.0.67.2.13] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.13] PRECHECK PASSED.'
