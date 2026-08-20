. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$package=Get-PackageRoot

$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontend=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$settings=Join-Path $repo 'src\SharpEmu.GUI\GuiSettings.cs'
$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$native=Join-Path $package 'native\src\provider_dlss_ngx_vk.cpp'

$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontend))
$s=Normalize-Lf ([IO.File]::ReadAllText($settings))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$n=Normalize-Lf ([IO.File]::ReadAllText($native))

$start=$b.IndexOf(
    '        private bool TryPrepareUpscalerPreCompositeForConsumer(',
    [StringComparison]::Ordinal)
$end=if($start-ge 0){
    $b.IndexOf(
        '        private void EndUpscalerPreCompositeConsumer()',
        $start,
        [StringComparison]::Ordinal)
}else{-1}
$method=if($start-ge 0 -and $end-gt $start){$b.Substring($start,$end-$start)}else{''}

$checks=[ordered]@{
    strict_marker=$b.Contains('V74.0.67.2.19 strict requested quality profile passthrough')
    old_auto_preserved_for_diag=$method.Contains('var autoResolvedQualityV74067219 =')
    effective_equals_requested=$method.Contains('var effectiveQuality = requestedQuality;')
    dispatch_uses_effective=$method.Contains('Quality = (int)effectiveQuality,')
    quality_telemetry=$method.Contains('[V74.0.67.2.19][UPSCALER][QUALITY_PROFILE]')
    parser_balanced=$b.Contains('"balanced" => HostUpscalerQuality.Balanced')
    parser_performance=$b.Contains('"performance" => HostUpscalerQuality.Performance')
    parser_ultraperformance=$b.Contains('HostUpscalerQuality.UltraPerformance')
    frontend_quality_env=$f.Contains('"SHARPEMU_VK_UPSCALER_QUALITY"')
    frontend_quality_setting=$s.Contains('public string UpscalerQuality')
    ngx_quality_dlaa=$n.Contains('case 0: return NVSDK_NGX_PerfQuality_Value_DLAA;')
    ngx_quality_quality=$n.Contains('default: return NVSDK_NGX_PerfQuality_Value_MaxQuality;')
    ngx_quality_balanced=$n.Contains('case 2: return NVSDK_NGX_PerfQuality_Value_Balanced;')
    ngx_quality_performance=$n.Contains('case 3: return NVSDK_NGX_PerfQuality_Value_MaxPerf;')
    ngx_quality_ultra=$n.Contains('case 4: return NVSDK_NGX_PerfQuality_Value_UltraPerformance;')
    ngx_recreates_on_quality_change=$n.Contains('g_quality == d->quality')
    v214_dlss=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    v212_bpe=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    v218_bpe=$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.19] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

$releaseHost=Find-ReleaseHost -Repo $repo
$hostOk=$null-ne $releaseHost
$line="[V74.0.67.2.19] release_host_exists=$($hostOk.ToString().ToLowerInvariant())"
Write-Host $line
$result.Add($line)
if(!$hostOk){$failed=$true}

$result.Add('[V74.0.67.2.19] PROFILE_CONTRACT=NativeAA->0 Quality->1 Balanced->2 Performance->3 UltraPerformance->4')
$result.Add('[V74.0.67.2.19] MANAGED_CONTRACT=effectiveQuality=requestedQuality')
$result.Add('[V74.0.67.2.19] NATIVE_CONTRACT=0:DLAA 1:MaxQuality 2:Balanced 3:MaxPerf 4:UltraPerformance')
$result.Add('[V74.0.67.2.19] INPUT_SOURCE_POLICY=unchanged-best-valid-temporal-source')
$result.Add('[V74.0.67.2.19] EXPECTED_RUNTIME=requested_quality=X effective_quality=X and RUNTIME quality=X')
$result.Add('[V74.0.67.2.19] DLSS_TRUTH=selected=dlss state=active dlss_dispatches>0 dispatch_failures=0')

if($failed){throw '[V74.0.67.2.19] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.19] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.19] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_19_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_19_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.19] ResultZip=$zip"
