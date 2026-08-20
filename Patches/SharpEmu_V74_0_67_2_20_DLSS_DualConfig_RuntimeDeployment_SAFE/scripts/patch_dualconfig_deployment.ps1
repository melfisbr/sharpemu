. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$runtimeRoot=Join-Path $repo 'runtime\dlss'
$runtimeUpscalers=Join-Path $runtimeRoot 'upscalers'
$canonicalProvider=Join-Path $runtimeUpscalers 'SharpEmu.VulkanUpscaler.Native.dll'
$canonicalNgx=Join-Path $runtimeRoot 'nvngx_dlss.dll'

if(!(Test-Path -LiteralPath $csproj -PathType Leaf)){
    throw "SharpEmu.CLI.csproj missing: $csproj"
}

function Find-ExistingProviderV74067220 {
    param([string]$Repo,[string]$Patches)

    $candidates=New-Object System.Collections.Generic.List[string]
    foreach($candidate in @(
        (Join-Path $Repo 'artifacts\bin\Release\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll'),
        (Join-Path $Repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.VulkanUpscaler.Native.dll'),
        (Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll'),
        (Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.VulkanUpscaler.Native.dll')
    )){
        $candidates.Add($candidate)
    }

    foreach($root in @(
        (Join-Path $Patches '_native_dlss_provider'),
        (Join-Path $Patches '_native_dlss_provider_v2131'),
        (Join-Path $Patches '_native_dlss_provider_v213')
    )){
        if(Test-Path -LiteralPath $root){
            foreach($item in @(Get-ChildItem -LiteralPath $root `
                -Filter 'SharpEmu.VulkanUpscaler.Native.dll' `
                -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending)){
                $candidates.Add($item.FullName)
            }
        }
    }

    foreach($candidate in $candidates){
        if(Test-Path -LiteralPath $candidate -PathType Leaf){
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Find-ExistingNgxV74067220 {
    param([string]$Repo,[string]$Patches)

    foreach($candidate in @(
        (Join-Path $Repo 'artifacts\bin\Release\net10.0\win-x64\nvngx_dlss.dll'),
        (Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\nvngx_dlss.dll'),
        (Join-Path $Patches '_vendor\NVIDIA_DLSS_v310_7_0\lib\Windows_x86_64\rel\nvngx_dlss.dll')
    )){
        if(Test-Path -LiteralPath $candidate -PathType Leaf){
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

$providerSource=Find-ExistingProviderV74067220 -Repo $repo -Patches $patches
$ngxSource=Find-ExistingNgxV74067220 -Repo $repo -Patches $patches

if([string]::IsNullOrWhiteSpace($providerSource)){
    throw '[V74.0.67.2.20] No previously built DLSS provider was found. Run the earlier provider bootstrap package once, then retry.'
}
if([string]::IsNullOrWhiteSpace($ngxSource)){
    throw '[V74.0.67.2.20] nvngx_dlss.dll was not found in Release/Debug output or the official SDK cache.'
}

foreach($export in @(
    'sharpemu_vk_upscaler_get_instance_extensions',
    'sharpemu_vk_upscaler_get_device_extensions',
    'sharpemu_vk_upscaler_get_capabilities',
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error'))
{
    if(!(Test-NativeExport -DllPath $providerSource -ExportName $export)){
        throw "[V74.0.67.2.20] Source provider missing export: $export"
    }
}

New-Item -ItemType Directory -Force -Path $runtimeUpscalers|Out-Null
Copy-Item -LiteralPath $providerSource -Destination $canonicalProvider -Force
Copy-Item -LiteralPath $ngxSource -Destination $canonicalNgx -Force

$providerHash=(Get-FileHash -LiteralPath $canonicalProvider -Algorithm SHA256).Hash
$ngxHash=(Get-FileHash -LiteralPath $canonicalNgx -Algorithm SHA256).Hash

Write-Host "[V74.0.67.2.20] canonical_provider=$canonicalProvider"
Write-Host "[V74.0.67.2.20] canonical_provider_sha256=$providerHash"
Write-Host "[V74.0.67.2.20] canonical_ngx=$canonicalNgx"
Write-Host "[V74.0.67.2.20] canonical_ngx_sha256=$ngxHash"

$xml=Normalize-Lf ([IO.File]::ReadAllText($csproj))
$marker='V74.0.67.2.20 DLSS dual-config runtime deployment'

if(!$xml.Contains($marker)){
    $close='</Project>'
    $count=Count-Ordinal -Text $xml -Needle $close
    if($count-ne 1){
        throw "[V74.0.67.2.20] SharpEmu.CLI.csproj </Project> count=$count expected=1"
    }

    $insert=@'

  <!-- V74.0.67.2.20 DLSS dual-config runtime deployment.
       The canonical runtime is populated from the already validated local
       NGX/provider installation. Every Debug/Release build then receives the
       exact same provider and nvngx runtime automatically. -->
  <PropertyGroup>
    <SharpEmuDlssRuntimeRoot>$(MSBuildProjectDirectory)\..\..\runtime\dlss</SharpEmuDlssRuntimeRoot>
  </PropertyGroup>

  <ItemGroup Condition="Exists('$(SharpEmuDlssRuntimeRoot)\upscalers\SharpEmu.VulkanUpscaler.Native.dll')">
    <None Include="$(SharpEmuDlssRuntimeRoot)\upscalers\SharpEmu.VulkanUpscaler.Native.dll"
          Link="upscalers\SharpEmu.VulkanUpscaler.Native.dll"
          CopyToOutputDirectory="PreserveNewest"
          CopyToPublishDirectory="PreserveNewest" />
  </ItemGroup>

  <ItemGroup Condition="Exists('$(SharpEmuDlssRuntimeRoot)\nvngx_dlss.dll')">
    <None Include="$(SharpEmuDlssRuntimeRoot)\nvngx_dlss.dll"
          Link="nvngx_dlss.dll"
          CopyToOutputDirectory="PreserveNewest"
          CopyToPublishDirectory="PreserveNewest" />
  </ItemGroup>

'@
    $xml=$xml.Replace($close,$insert+$close)
    [IO.File]::WriteAllText(
        $csproj,
        (Restore-Newlines $xml),
        [Text.UTF8Encoding]::new($false))
    Write-Host '[V74.0.67.2.20] SharpEmu.CLI.csproj dual-config deployment target applied.'
}else{
    Write-Host '[V74.0.67.2.20] SharpEmu.CLI.csproj dual-config deployment already present.'
}
