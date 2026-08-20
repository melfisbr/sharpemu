. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot;$patches=Get-PatchesRoot
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$a=Normalize-Lf ([IO.File]::ReadAllText($agc))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$releaseHost=Find-ReleaseHost -Repo $repo
$provider=if($null-ne $releaseHost){Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'}else{$null}
$ngx=if($null-ne $releaseHost){Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'}else{$null}

$checks=[ordered]@{
    dlss_retry_marker=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
    provider_is_initialized=$b.Contains('public bool IsInitialized => _initialized;')
    retry_timer=$b.Contains('V74067213ProviderRetryMs = 2000')
    provider_retained=$b.Contains('provider_loaded=1')
    active_telemetry=$b.Contains('[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active')
    last_error_preserved=$b.Contains('public string LastError')
    source_identity=$b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    ram_marker=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_content_key=$a.Contains('ulong ContentKey,')
    ram_sparse_probe=$a.Contains('const int SampleCount = 32')
    ram_tracker_exactness=$a.Contains('GuestImageWriteTracker.Enabled') -and $a.Contains('writeGeneration >= 0')
    ram_min_ttl=$a.Contains('V74067213MinimumArrayReuseTtlMs = 60000L')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    release_host_exists=$null-ne $releaseHost
    deployed_provider_exists=$null-ne $provider -and (Test-Path $provider)
    deployed_nvngx_exists=$null-ne $ngx -and (Test-Path $ngx)
}
$failed=$false;$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.13] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line;$result.Add($line);if(!$entry.Value){$failed=$true}
}
if($null-ne $provider -and (Test-Path $provider)){
    foreach($export in @(
        'sharpemu_vk_upscaler_get_instance_extensions',
        'sharpemu_vk_upscaler_get_device_extensions',
        'sharpemu_vk_upscaler_get_capabilities',
        'sharpemu_vk_upscaler_initialize',
        'sharpemu_vk_upscaler_dispatch',
        'sharpemu_vk_upscaler_shutdown',
        'sharpemu_vk_upscaler_get_last_error')){
        $ok=Test-NativeExport -DllPath $provider -ExportName $export
        $line="[V74.0.67.2.13] export_$export=$($ok.ToString().ToLowerInvariant())"
        Write-Host $line;$result.Add($line);if(!$ok){$failed=$true}
    }
}
$result.Add('[V74.0.67.2.13] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')
$result.Add('[V74.0.67.2.13] RAM_TARGET=lower alloc2s_mb and stop periodic 320MiB snapshot churn')
if($failed){throw '[V74.0.67.2.13] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}
Write-Host '[V74.0.67.2.13] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.13] DIAGNOSTIC PASSED.')
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_13_DLSS_RAM_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_13_DLSS_RAM_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.13] ResultZip=$zip"
