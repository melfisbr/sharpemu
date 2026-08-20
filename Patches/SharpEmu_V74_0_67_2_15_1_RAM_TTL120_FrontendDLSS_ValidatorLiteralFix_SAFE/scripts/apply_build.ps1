. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$code=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

$a=Normalize-Lf ([IO.File]::ReadAllText($agc))
$c=Normalize-Lf ([IO.File]::ReadAllText($code))
$needRam=!$a.Contains('V74.0.67.2.15 effective large-array TTL')
$needFront=!$c.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_15_1_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $agc -Destination (Join-Path $backup 'AgcExports.cs') -Force
Copy-Item -LiteralPath $code -Destination (Join-Path $backup 'MainWindow.axaml.cs') -Force

try{
    if($needRam){& (Join-Path $PSScriptRoot 'patch_ram_ttl.ps1')}
    else{Write-Host '[V74.0.67.2.15.1] RAM TTL source already patched.'}

    if($needFront){& (Join-Path $PSScriptRoot 'patch_frontend_oneclick.ps1')}
    else{Write-Host '[V74.0.67.2.15.1] Frontend launch bridge already patched.'}
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $agc -Force
    Copy-Item -LiteralPath (Join-Path $backup 'MainWindow.axaml.cs') -Destination $code -Force
    throw
}

Stop-SharpEmuForBuild

$buildStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_15_1_RAM_FRONTEND_BUILD_$buildStamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$oldPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $output=@(& dotnet build $cli -c Release -r win-x64 2>&1)
    $exitCode=$LASTEXITCODE
}finally{$ErrorActionPreference=$oldPreference}

$lines=@(
    foreach($item in $output){
        if($null-eq $item){continue}
        $line=$item.ToString()
        Write-Host $line
        $line
    }
)
$lines|Set-Content -LiteralPath $buildLog -Encoding UTF8

if($exitCode-ne 0){
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $agc -Force
    Copy-Item -LiteralPath (Join-Path $backup 'MainWindow.axaml.cs') -Destination $code -Force
    throw "SharpEmu.CLI Release build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider -PathType Leaf)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx -PathType Leaf)){throw "nvngx_dlss.dll missing: $ngx"}

foreach($export in @(
    'sharpemu_vk_upscaler_get_instance_extensions',
    'sharpemu_vk_upscaler_get_device_extensions',
    'sharpemu_vk_upscaler_get_capabilities',
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error')){
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "Provider export missing: $export"
    }
}

Write-Host '[V74.0.67.2.15.1] APPLY + RELEASE BUILD PASSED.'
Write-Host '[V74.0.67.2.15.1] DLSS native provider unchanged; deployed provider/NGX revalidated.'
Write-Host "[V74.0.67.2.15.1] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.15.1] BuildLog=$buildLog"
Write-Host "[V74.0.67.2.15.1] Backup=$backup"
