. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

& (Join-Path $PSScriptRoot 'validate_package.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$current=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$needs=!$current.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')

$backup=$null
if($needs){
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_67_2_12_$stamp"
    New-Item -ItemType Directory -Force -Path $backup|Out-Null
    Copy-Item -LiteralPath $exceptions `
        -Destination (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') -Force
    try{
        & (Join-Path $PSScriptRoot 'patch_bpe_secondary_caller.ps1')
    }catch{
        Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
            -Destination $exceptions -Force
        throw
    }
}else{
    Write-Host '[V74.0.67.2.12] Secondary BPE caller recovery already applied.'
}

Stop-SharpEmuForBuild

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$buildLog=Join-Path $patches "SharpEmu_V74_0_67_2_12_BPE_SECONDARY_CALLER_BUILD_$stamp.log"
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
    if($needs -and $null-ne $backup){
        Copy-Item -LiteralPath (Join-Path $backup 'DirectExecutionBackend.Exceptions.cs') `
            -Destination $exceptions -Force
    }
    throw "SharpEmu.CLI build failed: native exit $exitCode"
}

$releaseHost=Find-ReleaseHost -Repo $repo
if($null-eq $releaseHost){throw 'Release win-x64 SharpEmu.exe not found.'}

$provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'

if(!(Test-Path -LiteralPath $provider)){throw "Expected deployed provider missing: $provider"}
if(!(Test-Path -LiteralPath $ngx)){throw "Expected nvngx_dlss.dll missing: $ngx"}
if(!(Test-NativeExport -DllPath $provider -ExportName 'sharpemu_vk_upscaler_get_last_error')){
    throw 'Deployed provider is not the V2.10 NGX provider.'
}

Write-Host '[V74.0.67.2.12] APPLY + HOST BUILD PASSED.'
Write-Host '[V74.0.67.2.12] Native provider unchanged; V2.10 deployment preserved.'
Write-Host "[V74.0.67.2.12] Host=$($releaseHost.FullName)"
Write-Host "[V74.0.67.2.12] BuildLog=$buildLog"
if($null-ne $backup){Write-Host "[V74.0.67.2.12] Backup=$backup"}
