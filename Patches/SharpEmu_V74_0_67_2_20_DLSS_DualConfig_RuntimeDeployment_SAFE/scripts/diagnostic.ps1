. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$c=Normalize-Lf ([IO.File]::ReadAllText($csproj))

$runtimeRoot=Join-Path $repo 'runtime\dlss'
$canonicalProvider=Join-Path $runtimeRoot 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$canonicalNgx=Join-Path $runtimeRoot 'nvngx_dlss.dll'

$checks=[ordered]@{
    csproj_marker=$c.Contains('V74.0.67.2.20 DLSS dual-config runtime deployment')
    runtime_root=$c.Contains('<SharpEmuDlssRuntimeRoot>')
    provider_link=$c.Contains('Link="upscalers\SharpEmu.VulkanUpscaler.Native.dll"')
    ngx_link=$c.Contains('Link="nvngx_dlss.dll"')
    copy_output=$c.Contains('CopyToOutputDirectory="PreserveNewest"')
    copy_publish=$c.Contains('CopyToPublishDirectory="PreserveNewest"')
    canonical_provider=Test-Path -LiteralPath $canonicalProvider -PathType Leaf
    canonical_ngx=Test-Path -LiteralPath $canonicalNgx -PathType Leaf
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.20] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

$canonicalProviderHash=if(Test-Path -LiteralPath $canonicalProvider){
    (Get-FileHash -LiteralPath $canonicalProvider -Algorithm SHA256).Hash
}else{''}
$canonicalNgxHash=if(Test-Path -LiteralPath $canonicalNgx){
    (Get-FileHash -LiteralPath $canonicalNgx -Algorithm SHA256).Hash
}else{''}

foreach($config in @('Release','Debug')){
    $configHost=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\SharpEmu.exe"
    $provider=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll"
    $ngx=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\nvngx_dlss.dll"

    $hostOk=Test-Path -LiteralPath $configHost -PathType Leaf
    $providerOk=Test-Path -LiteralPath $provider -PathType Leaf
    $ngxOk=Test-Path -LiteralPath $ngx -PathType Leaf

    $providerHashOk=$false
    $ngxHashOk=$false
    if($providerOk -and ![string]::IsNullOrWhiteSpace($canonicalProviderHash)){
        $providerHashOk=((Get-FileHash -LiteralPath $provider -Algorithm SHA256).Hash -eq $canonicalProviderHash)
    }
    if($ngxOk -and ![string]::IsNullOrWhiteSpace($canonicalNgxHash)){
        $ngxHashOk=((Get-FileHash -LiteralPath $ngx -Algorithm SHA256).Hash -eq $canonicalNgxHash)
    }

    foreach($pair in @(
        @('host',$hostOk),
        @('provider',$providerOk),
        @('ngx',$ngxOk),
        @('provider_hash',$providerHashOk),
        @('ngx_hash',$ngxHashOk)))
    {
        $line="[V74.0.67.2.20] $($config.ToLowerInvariant())_$($pair[0])=$($pair[1].ToString().ToLowerInvariant())"
        Write-Host $line
        $result.Add($line)
        if(!$pair[1]){$failed=$true}
    }

    if($providerOk){
        foreach($export in @(
            'sharpemu_vk_upscaler_get_instance_extensions',
            'sharpemu_vk_upscaler_get_device_extensions',
            'sharpemu_vk_upscaler_get_capabilities',
            'sharpemu_vk_upscaler_initialize',
            'sharpemu_vk_upscaler_dispatch',
            'sharpemu_vk_upscaler_shutdown',
            'sharpemu_vk_upscaler_get_last_error'))
        {
            $ok=Test-NativeExport -DllPath $provider -ExportName $export
            $line="[V74.0.67.2.20] $($config.ToLowerInvariant())_export_$export=$($ok.ToString().ToLowerInvariant())"
            Write-Host $line
            $result.Add($line)
            if(!$ok){$failed=$true}
        }
    }
}

$result.Add('[V74.0.67.2.20] EXPECTED_DEBUG_LOAD=exists=1 loaded=1')
$result.Add('[V74.0.67.2.20] EXPECTED_RUNTIME=provider=1 caps=0x9 selected=dlss state=active dlss_dispatches>0')
$result.Add('[V74.0.67.2.20] PROFILE_EXPECTED=requested_quality=ultraperformance effective_quality=ultraperformance')

if($failed){throw '[V74.0.67.2.20] DUAL-CONFIG DEPLOYMENT DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.20] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.20] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_20_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_20_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.20] ResultZip=$zip"
