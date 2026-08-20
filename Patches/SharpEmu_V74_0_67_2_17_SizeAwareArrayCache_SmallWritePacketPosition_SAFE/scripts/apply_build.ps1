. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$source=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$current=Normalize-Lf ([IO.File]::ReadAllText($source))
$complete=
    $current.Contains('V74.0.67.2.17 size-aware large-array admission') -and
    $current.Contains('V74.0.67.2.17 small WRITE_DATA packet position') -and
    $current.Contains('V74.0.67.2.17 producer completion latency')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_17_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $backup 'AgcExports.cs') -Force

try{
    if(!$complete){
        & (Join-Path $PSScriptRoot 'patch_v217.ps1')
    }else{
        Write-Host '[V74.0.67.2.17] Source already patched.'
    }
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $source -Force
    throw
}

Stop-SharpEmuForBuild

$buildStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_17_BUILD_$buildStamp.log"
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
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $source -Force
    throw "SharpEmu.CLI Release build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "nvngx_dlss.dll missing: $ngx"}

foreach($export in @(
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error')){
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "Provider export missing: $export"
    }
}

Write-Host '[V74.0.67.2.17] APPLY + RELEASE BUILD PASSED.'
Write-Host "[V74.0.67.2.17] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.17] BuildLog=$buildLog"
Write-Host "[V74.0.67.2.17] Backup=$backup"
