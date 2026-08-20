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
    Write-Host "[V74.0.67.2.13.1] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$dlssAlready=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
$ramAlready=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
$bpeSecondary=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
Write-Host "[V74.0.67.2.13.1] dlss_activation_already=$($dlssAlready.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13.1] ram_pressure_already=$($ramAlready.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.13.1] bpe_secondary_already=$($bpeSecondary.ToString().ToLowerInvariant())"

if(!$dlssAlready){
    foreach($anchor in @(
        '        private string _upscalerInitFailureReason = string.Empty;',
        '            public int LastInitializeResult { get; private set; }',
        'state=retry_size_change',
        'return _nativeUpscaler is not null;'
    )){
        $count=Count-Ordinal -Text $b -Needle $anchor
        Write-Host "[V74.0.67.2.13.1] bridge_anchor_count=$count token=$anchor"
        if($count-lt 1){$failed=$true}
    }
}

if(!$ramAlready){
    $keyField=Count-Ordinal -Text $a -Needle '        long WriteGeneration,'
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

    $v74064TtlField =
        $a.Contains('_v74064LargeArraySnapshotTtlMs')
    $v74064TtlEnv =
        $a.Contains('SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS')
    $v74064CacheEnv =
        $a.Contains('SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES')
    $v74064Lookup =
        $a.Contains('TryGetLargeArraySnapshotV74064')
    $v74064Store =
        $a.Contains('StoreLargeArraySnapshotV74064')
    $v74064OwnerTrace =
        $a.Contains('[V74.0.64][ARRAY_CACHE_OWNER]')

    Write-Host "[V74.0.67.2.13.1] ram_anchor_key_field=$keyField"
    Write-Host "[V74.0.67.2.13.1] ram_anchor_tiled=$tiledCount"
    Write-Host "[V74.0.67.2.13.1] ram_anchor_linear=$linearCount"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_ttl_field=$($v74064TtlField.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_ttl_env=$($v74064TtlEnv.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_cache_env=$($v74064CacheEnv.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_lookup=$($v74064Lookup.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_store=$($v74064Store.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.13.1] ram_v74064_owner_trace=$($v74064OwnerTrace.ToString().ToLowerInvariant())"
    Write-Host '[V74.0.67.2.13.1] ram_ttl_owner=V74.0.64-multicache'

    if($keyField-ne 1 -or
       $tiledCount-ne 1 -or
       $linearCount-ne 1 -or
       !$v74064TtlField -or
       !$v74064TtlEnv -or
       !$v74064CacheEnv -or
       !$v74064Lookup -or
       !$v74064Store -or
       !$v74064OwnerTrace){
        $failed=$true
    }
}

Write-Host '[V74.0.67.2.13.1] dlss_strategy=explicit-feature-path+bounded-init-retry+provider-retention'
Write-Host '[V74.0.67.2.13.1] ram_strategy=sparse-content-key+existing-v74064-multicache-ttl-env'
Write-Host '[V74.0.67.2.13.1] dlss_truth=selected=dlss,state=active,dlss_dispatches>0'
Write-Host '[V74.0.67.2.13.1] hardcoded_guest_resource_address=false'
if($failed){throw '[V74.0.67.2.13.1] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.13.1] PRECHECK PASSED.'
