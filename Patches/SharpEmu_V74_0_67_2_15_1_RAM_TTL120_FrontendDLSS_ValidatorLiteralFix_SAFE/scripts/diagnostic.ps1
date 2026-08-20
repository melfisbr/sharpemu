. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$code=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$settings=Join-Path $repo 'src\SharpEmu.GUI\GuiSettings.cs'

$a=Normalize-Lf ([IO.File]::ReadAllText($agc))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$c=Normalize-Lf ([IO.File]::ReadAllText($code))
$s=Normalize-Lf ([IO.File]::ReadAllText($settings))

$token='_v74064LargeArraySnapshotTtlMs'
$rawTokenCount=Count-Ordinal -Text $a -Needle $token

$lookupStart=$a.IndexOf('TryGetLargeArraySnapshotV74064',[StringComparison]::Ordinal)
$storeStart=$a.IndexOf('StoreLargeArraySnapshotV74064',[StringComparison]::Ordinal)
$lookupUsesEffective=$false
if($lookupStart-ge 0 -and $storeStart-gt $lookupStart){
    $lookup=$a.Substring($lookupStart,$storeStart-$lookupStart)
    $lookupUsesEffective=$lookup.Contains('V74067215LargeArraySnapshotTtlMs')
}

$releaseHost=Find-ReleaseHost -Repo $repo
$provider=$null;$ngx=$null
if($null-ne $releaseHost){
    $provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
    $ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
}

$checks=[ordered]@{
    ram_ttl_marker=$a.Contains('V74.0.67.2.15 effective large-array TTL')
    ram_effective_ttl_property=$a.Contains('V74067215LargeArraySnapshotTtlMs')
    ram_effective_ttl_upper_120000=$a.Contains('120000')
    ram_lookup_uses_effective_ttl=$lookupUsesEffective
    ram_content_identity_preserved=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_multicache_preserved=$a.Contains('TryGetLargeArraySnapshotV74064') -and $a.Contains('StoreLargeArraySnapshotV74064')
    frontend_oneclick_marker=$c.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
    frontend_master_setting=$s.Contains('public bool UpscalerEnabled')
    frontend_backend_setting=$s.Contains('public string UpscalerBackend')
    frontend_quality_setting=$s.Contains('public string UpscalerQuality')
    frontend_backend_env=$c.Contains('"SHARPEMU_VK_UPSCALER"')
    frontend_quality_env=$c.Contains('"SHARPEMU_VK_UPSCALER_QUALITY"')
    frontend_precomposite_env=$c.Contains('"SHARPEMU_VK_UPSCALER_PRECOMPOSITE"')
    frontend_ram_cache_2=$c.Contains('"SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES"') -and $c.Contains('"2"')
    frontend_ram_ttl_120000=$c.Contains('"SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS"') -and $c.Contains('"120000"')
    frontend_detile_pool_64=$c.Contains('"SHARPEMU_VK_DETILE_POOL_MB"') -and $c.Contains('"64"')
    dlss_precomposite_default_true=$b.Contains('ReadUpscalerBool("SHARPEMU_VK_UPSCALER_PRECOMPOSITE", true)')
    dlss_provider_autodiscovery=$b.Contains('Path.Combine(AppContext.BaseDirectory, "upscalers", "SharpEmu.VulkanUpscaler.Native.dll")')
    dlss_command_buffer_fix=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    release_host_exists=$null-ne $releaseHost
    deployed_provider_exists=$null-ne $provider -and (Test-Path -LiteralPath $provider)
    deployed_nvngx_exists=$null-ne $ngx -and (Test-Path -LiteralPath $ngx)
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.15.1] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

Write-Host "[V74.0.67.2.15.1] ram_raw_v74064_ttl_token_count=$rawTokenCount"
$result.Add("[V74.0.67.2.15.1] ram_raw_v74064_ttl_token_count=$rawTokenCount")

if($null-ne $provider -and (Test-Path -LiteralPath $provider)){
    foreach($export in @(
        'sharpemu_vk_upscaler_get_instance_extensions',
        'sharpemu_vk_upscaler_get_device_extensions',
        'sharpemu_vk_upscaler_get_capabilities',
        'sharpemu_vk_upscaler_initialize',
        'sharpemu_vk_upscaler_dispatch',
        'sharpemu_vk_upscaler_shutdown',
        'sharpemu_vk_upscaler_get_last_error')){
        $ok=Test-NativeExport -DllPath $provider -ExportName $export
        $line="[V74.0.67.2.15.1] export_$export=$($ok.ToString().ToLowerInvariant())"
        Write-Host $line
        $result.Add($line)
        if(!$ok){$failed=$true}
    }
}

$result.Add('[V74.0.67.2.15.1] FRONTEND_DLSS=enable Rendering upscaler + select DLSS + select quality; no RUN_5/env shell required')
$result.Add('[V74.0.67.2.15.1] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')
$result.Add('[V74.0.67.2.15.1] RAM_RUNTIME_PROOF=ARRAY_CACHE_OWNER/ARRAY_SINGLEFLIGHT ttl_ms=120000')
$result.Add('[V74.0.67.2.15.1] RAM_TARGET=lower alloc2s_mb and fewer 320MiB rematerializations')

if($failed){throw '[V74.0.67.2.15.1] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.15.1] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.15.1] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_15_1_RAM_FRONTEND_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_15_1_RAM_FRONTEND_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.15.1] ResultZip=$zip"
