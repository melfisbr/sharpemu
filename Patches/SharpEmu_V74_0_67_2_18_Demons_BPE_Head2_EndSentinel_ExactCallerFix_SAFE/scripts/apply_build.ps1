. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$agc=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'

$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$a=Normalize-Lf ([IO.File]::ReadAllText($agc))

$v217Markers=@(
    'V74.0.67.2.17 size-aware large-array admission',
    'V74.0.67.2.17 small WRITE_DATA packet position',
    'V74.0.67.2.17 producer completion latency')
$v217Present=0
foreach($marker in $v217Markers){
    if($a.Contains($marker)){$v217Present++}
}

if($v217Present-ne 0 -and $v217Present-ne $v217Markers.Count){
    throw '[V74.0.67.2.18] Refusing partial V2.17 source state.'
}

$needV217=$v217Present-eq 0
$needBpe=!$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_18_$stamp"
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $exceptions -Destination (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Force
Copy-Item -LiteralPath $agc -Destination (Join-Path $backup 'AgcExports.cs') -Force

try{
    if($needV217){
        Write-Host '[V74.0.67.2.18] V2.17 source markers absent; applying cumulative V2.17 first.'
        & (Join-Path $PSScriptRoot 'patch_v217.ps1')
    }else{
        Write-Host '[V74.0.67.2.18] V2.17 source already applied; preserving it.'
    }

    if($needBpe){
        & (Join-Path $PSScriptRoot 'patch_bpe_head2_sentinel.ps1')
    }else{
        Write-Host '[V74.0.67.2.18] BPE head2 source already applied.'
    }
}catch{
    Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Destination $exceptions -Force
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $agc -Force
    throw
}

Stop-SharpEmuForBuild

$buildStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_18_BUILD_$buildStamp.log"
$cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$oldPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $output=@(& dotnet build $cli -c Release -r win-x64 2>&1)
    $exitCode=$LASTEXITCODE
}finally{
    $ErrorActionPreference=$oldPreference
}

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
    Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Destination $exceptions -Force
    Copy-Item -LiteralPath (Join-Path $backup 'AgcExports.cs') -Destination $agc -Force
    throw "SharpEmu.CLI Release build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
if(!(Test-Path -LiteralPath $provider -PathType Leaf)){throw "Provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx -PathType Leaf)){throw "nvngx_dlss.dll missing: $ngx"}

foreach($export in @(
    'sharpemu_vk_upscaler_initialize',
    'sharpemu_vk_upscaler_dispatch',
    'sharpemu_vk_upscaler_shutdown',
    'sharpemu_vk_upscaler_get_last_error')){
    if(!(Test-NativeExport -DllPath $provider -ExportName $export)){
        throw "Provider export missing: $export"
    }
}

Write-Host '[V74.0.67.2.18] APPLY + RELEASE BUILD PASSED.'
Write-Host "[V74.0.67.2.18] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.18] BuildLog=$buildLog"
Write-Host "[V74.0.67.2.18] Backup=$backup"
