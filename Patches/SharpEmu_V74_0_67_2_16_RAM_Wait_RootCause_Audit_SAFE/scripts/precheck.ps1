. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$codePath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

foreach($path in @($agcPath,$presenterPath,$bridgePath,$codePath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Missing required source: $path"
    }
}

$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$c=Normalize-Lf ([IO.File]::ReadAllText($codePath))

$checks=[ordered]@{
    ram_v215_ttl=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    ram_v215_effective=$a.Contains('V74067215LargeArraySnapshotTtlMs')
    ram_v213_content_key=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_v74064_lookup=$a.Contains('TryGetLargeArraySnapshotV74064')
    ram_v74064_store=$a.Contains('StoreLargeArraySnapshotV74064')
    ram_v74064_evict=$a.Contains('[V74.0.64][ARRAY_CACHE_EVICT]')
    ram_v74064_owner=$a.Contains('[V74.0.64][ARRAY_CACHE_OWNER]')
    wait_slow_producer=$a.Contains('[V74.0.27][SLOW_WAIT_PRODUCER]')
    wait_dedicated=$a.Contains('[V74.0.71][DEDICATED_WAIT_DRAIN]')
    wait_gate_owner=$a.Contains('[V74.0.72][GATE_OWNER_WAIT_DRAIN]')
    wait_resumable_dcb=$a.Contains('RequestResumableDcbDrain')
    wait_pump=$a.Contains('PumpSubmittedQueuesV74030')
    presenter_capacity=$p.Contains('[V74.0.33][SUBMISSION_CAPACITY_YIELD]')
    presenter_hard_cap_probe=$p.Contains('[V74.0.46][INLINE_HARD_CAP_FENCE_PROBE]')
    dlss_v214_command_buffer=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    frontend_v215=$c.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.16] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

# Source-shape facts used to determine whether the next behavioral patch can
# safely be cache-admission or completed-producer wake logic.
$agcNewByte=[regex]::Matches($a,'new\s+byte\s*\[').Count
$agcGcByte=[regex]::Matches($a,'GC\.AllocateUninitializedArray\s*<\s*byte\s*>').Count
$agcToArray=[regex]::Matches($a,'\.ToArray\s*\(\s*\)').Count
$vkNewByte=[regex]::Matches($p,'new\s+byte\s*\[').Count
$vkGcByte=[regex]::Matches($p,'GC\.AllocateUninitializedArray\s*<\s*byte\s*>').Count
$vkToArray=[regex]::Matches($p,'\.ToArray\s*\(\s*\)').Count

Write-Host "[V74.0.67.2.16] source_agc_new_byte_sites=$agcNewByte"
Write-Host "[V74.0.67.2.16] source_agc_gc_byte_sites=$agcGcByte"
Write-Host "[V74.0.67.2.16] source_agc_toarray_sites=$agcToArray"
Write-Host "[V74.0.67.2.16] source_vk_new_byte_sites=$vkNewByte"
Write-Host "[V74.0.67.2.16] source_vk_gc_byte_sites=$vkGcByte"
Write-Host "[V74.0.67.2.16] source_vk_toarray_sites=$vkToArray"
Write-Host '[V74.0.67.2.16] runtime_source_change=false'
Write-Host '[V74.0.67.2.16] purpose=exact-allocation-and-completed-producer-wake-attribution'

if($failed){throw '[V74.0.67.2.16] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.16] PRECHECK PASSED.'
