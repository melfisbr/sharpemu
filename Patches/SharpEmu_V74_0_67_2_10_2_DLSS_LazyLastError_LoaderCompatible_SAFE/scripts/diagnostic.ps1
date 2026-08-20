. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$presenterPath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$p=Normalize-Lf ([IO.File]::ReadAllText($presenterPath))

$releaseHost=Find-ReleaseHost -Repo $repo
$provider=$null;$ngx=$null
if($null-ne $releaseHost){
    $provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
    $ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
}

$checks=[ordered]@{
    lazy_last_error_retry_marker=
        $b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')
    last_error_delegate=
        $b.Contains('private delegate nint GetLastErrorDelegate();')
    lazy_last_error_export_lookup=
        $b.Contains('NativeLibrary.TryGetExport(') -and
        $b.Contains('"sharpemu_vk_upscaler_get_last_error"')
    last_error_property=
        $b.Contains('public string LastError')
    last_error_export_property=
        $b.Contains('public bool HasLastErrorExport')
    initialize_result_capture=
        $b.Contains('LastInitializeResult = result;')
    failed_width_state=
        $b.Contains('_upscalerInitFailedWidth')
    failed_height_state=
        $b.Contains('_upscalerInitFailedHeight')
    retry_only_on_size_change=
        $b.Contains('state=retry_size_change') -and
        $b.Contains('_nativeUpscaler is null')
    same_dimension_retry_loop_absent=
        !$b.Contains('state=retry_same_size')
    v671_loader_preserved=
        $b.Contains('[V74.0.67.1][UPSCALER][LOAD]') -or
        $b.Contains('V74.0.67.1 provider bootstrap/load diagnostics')
    provider_init_telemetry=
        $b.Contains('[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT]')
    old_v210_loader_rewrite_absent=
        !$b.Contains('[V74.0.67.2.10][UPSCALER][PROVIDER_LOAD]')
    v6729_preserved=
        $b.Contains('V74.0.67.2.9 distinct source-identity disambiguation')
    v6728_preserved=
        $b.Contains('V74.0.67.2.8 strict provider extension negotiation')
    v6725_preserved=
        $b.Contains('V74.0.67.2.5 per-source content-generation confidence')
    v6726_preserved=
        $b.Contains('V74.0.67.2.6 global same-extent motion provenance')
    precomposite_preserved=
        $b.Contains('V74.0.67.2.1 pre-composite DLSS redirect')
    runtime_counters_preserved=
        $b.Contains('_upscalerRuntimeDlssDispatches')
    invalid_direction_guard_preserved=
        $b.Contains('invalid_upscale_direction')
    instance_extension_hook=
        $p.Contains('AppendUpscalerInstanceExtensions(')
    device_extension_hook=
        $p.Contains('AppendUpscalerDeviceExtensions(')
    release_host_exists=
        $null-ne $releaseHost
    deployed_provider_exists=
        $null-ne $provider -and (Test-Path -LiteralPath $provider)
    deployed_nvngx_exists=
        $null-ne $ngx -and (Test-Path -LiteralPath $ngx)
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.10.2] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

if($null-ne $provider -and (Test-Path -LiteralPath $provider)){
    foreach($export in @(
        'sharpemu_vk_upscaler_get_instance_extensions',
        'sharpemu_vk_upscaler_get_device_extensions',
        'sharpemu_vk_upscaler_get_capabilities',
        'sharpemu_vk_upscaler_initialize',
        'sharpemu_vk_upscaler_dispatch',
        'sharpemu_vk_upscaler_shutdown',
        'sharpemu_vk_upscaler_get_last_error'
    )){
        $ok=Test-NativeExport -DllPath $provider -ExportName $export
        $line="[V74.0.67.2.10.2] export_$export=$($ok.ToString().ToLowerInvariant())"
        Write-Host $line
        $result.Add($line)
        if(!$ok){$failed=$true}
    }
    $result.Add(
        "[V74.0.67.2.10.2] ProviderSHA256=$((Get-FileHash -LiteralPath $provider -Algorithm SHA256).Hash)")
}

if($null-ne $ngx -and (Test-Path -LiteralPath $ngx)){
    $result.Add(
        "[V74.0.67.2.10.2] NvngxDlssSHA256=$((Get-FileHash -LiteralPath $ngx -Algorithm SHA256).Hash)")
}

$result.Add('[V74.0.67.2.10.2] EXPECTED_RUNTIME_1=V74.0.67.1 LOAD candidate exists=1 loaded=1')
$result.Add('[V74.0.67.2.10.2] EXPECTED_RUNTIME_2=PROVIDER_INIT state=active OR exact native last_error')
$result.Add('[V74.0.67.2.10.2] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')

if($failed){
    throw '[V74.0.67.2.10.2] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'
}

Write-Host '[V74.0.67.2.10.2] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.10.2] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_10_2_DLSS_PROVIDER_INIT_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_10_2_DLSS_PROVIDER_INIT_RESULT_$stamp.zip"

[IO.File]::WriteAllLines(
    $txt,
    $result,
    [Text.UTF8Encoding]::new($false))

Compress-Archive `
    -LiteralPath $txt `
    -DestinationPath $zip `
    -Force

Write-Host "[V74.0.67.2.10.2] ResultZip=$zip"
