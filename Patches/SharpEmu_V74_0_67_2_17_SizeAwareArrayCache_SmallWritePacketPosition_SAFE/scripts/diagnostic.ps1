. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$source=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontend=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

$a=Normalize-Lf ([IO.File]::ReadAllText($source))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontend))

$storeStart=$a.IndexOf(
    '    private static void StoreLargeArraySnapshotV74064(',
    [StringComparison]::Ordinal)
$storeEnd=if($storeStart-ge 0){
    $a.IndexOf(
        '    private static readonly object _softwarePresenterGate = new();',
        $storeStart,
        [StringComparison]::Ordinal)
}else{-1}
$store=if($storeStart-ge 0 -and $storeEnd-gt $storeStart){
    $a.Substring($storeStart,$storeEnd-$storeStart)
}else{''}

$submitStart=$a.IndexOf(
    '    private static void SubmitOrderedGpuSideEffect(',
    [StringComparison]::Ordinal)
$submitEnd=if($submitStart-ge 0){
    $a.IndexOf(
        '    // V74.0.71:',
        $submitStart,
        [StringComparison]::Ordinal)
}else{-1}
$submit=if($submitStart-ge 0 -and $submitEnd-gt $submitStart){
    $a.Substring($submitStart,$submitEnd-$submitStart)
}else{''}

$checks=[ordered]@{
    cache_marker=$a.Contains('V74.0.67.2.17 size-aware large-array admission')
    cache_same_resource=$a.Contains('SameLargeArrayResourceIgnoringContentV74067217')
    cache_bypass_trace=$store.Contains('[V74.0.67.2.17][ARRAY_CACHE_ADMISSION]')
    cache_bypass_guard=$store.Contains('data.LongLength <= smallestBytes')
    cache_entry_bound_preserved=$store.Contains('_v74064LargeArraySnapshotCacheEntries')
    cache_v215_ttl_preserved=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    cache_v213_key_preserved=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    small_write_marker=$a.Contains('V74.0.67.2.17 small WRITE_DATA packet position')
    small_write_max16=$submit.Contains('producerLength <= 16')
    small_write_no_readback=$submit.Contains('!requiresGpuBufferReadback')
    small_write_no_defer=$submit.Contains('!deferLabelCompletion')
    small_write_packet_path=$submit.Contains('smallWritePacketPositionV74067217')
    small_write_trace=$submit.Contains('[V74.0.67.2.17][SMALL_WRITE_PACKET_POSITION]')
    wait_latency_marker=$a.Contains('V74.0.67.2.17 producer completion latency')
    wait_complete_metric=$a.Contains('producer_complete_ms=')
    wait_post_complete_metric=$a.Contains('post_complete_wait_ms=')
    gate_owner_preserved=$a.Contains('[V74.0.72][GATE_OWNER_WAIT_DRAIN]')
    dlss_v214_preserved=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    frontend_v215_preserved=$f.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.17] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

$releaseHost=Find-ReleaseHost -Repo $repo
$hostOk=$null-ne $releaseHost
$line="[V74.0.67.2.17] release_host_exists=$($hostOk.ToString().ToLowerInvariant())"
Write-Host $line
$result.Add($line)
if(!$hostOk){$failed=$true}

$result.Add('[V74.0.67.2.17] EXPECTED_RAM=ARRAY_CACHE_ADMISSION bypass-smaller/replace-smaller; fewer 256/320MiB owner rematerializations')
$result.Add('[V74.0.67.2.17] EXPECTED_WAIT=SMALL_WRITE_PACKET_POSITION followed by reduced SLOW_WAIT_PRODUCER incidence')
$result.Add('[V74.0.67.2.17] WAIT_DIAG=producer_complete_ms vs post_complete_wait_ms')
$result.Add('[V74.0.67.2.17] SUBMISSION_HARD_CAP=unchanged')
$result.Add('[V74.0.67.2.17] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')

if($failed){throw '[V74.0.67.2.17] STRUCTURAL DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.17] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.17] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_17_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_17_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.17] ResultZip=$zip"
