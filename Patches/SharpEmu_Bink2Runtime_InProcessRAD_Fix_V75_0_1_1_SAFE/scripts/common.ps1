Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:Tag='[V75.0.1.1-BINK2-RUNTIME-INPROCESS]'
$script:Version='V75.0.1.1'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:RelativeAbi='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs'
$script:RelativeDecoder='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'
$script:RelativeHostMovie='src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$script:RelativePlayback='src\SharpEmu.Libs\Media\MediaFramePlayback.cs'

function Write-Tag([string]$Message){ Write-Host "$script:Tag $Message" }

function Get-PatchesRoot { Split-Path -Parent $script:PackageRoot }

function Get-RepositoryRoot {
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src'))){
        throw "$script:Tag repository root not found: $repo"
    }
    $repo
}

function Get-Sha([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){ return '' }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-StatePath {
    Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_1_1_BINK2_RUNTIME_STATE.json'
}

function Read-RuntimeState {
    $path=Get-StatePath
    if(-not(Test-Path -LiteralPath $path)){
        return $null
    }
    try{
        Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    }catch{
        Write-Tag "StateReadWarning=$($_.Exception.Message)"
        $null
    }
}

function Write-RuntimeState([hashtable]$Values){
    $existing=Read-RuntimeState
    $state=[ordered]@{}
    if($null -ne $existing){
        foreach($property in $existing.PSObject.Properties){
            $state[$property.Name]=$property.Value
        }
    }
    foreach($key in $Values.Keys){
        $state[$key]=$Values[$key]
    }
    $state['version']=$script:Version
    $state|ConvertTo-Json -Depth 8|
        Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
    [pscustomobject]$state
}

function Get-AdapterSource {
    Join-Path $script:PackageRoot 'source\native\SharpEmu.BinkNative.Runtime.cpp'
}

function Find-VsDevCmd {
    $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if(Test-Path -LiteralPath $vswhere){
        $install=& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if(-not[string]::IsNullOrWhiteSpace($install)){
            $candidate=Join-Path $install.Trim() 'Common7\Tools\VsDevCmd.bat'
            if(Test-Path -LiteralPath $candidate){ return $candidate }
        }
    }
    return $null
}

function Get-PeMachine([string]$Path){
    $stream=[IO.File]::OpenRead($Path)
    try{
        $reader=New-Object IO.BinaryReader($stream)
        if($reader.ReadUInt16() -ne 0x5A4D){ return 0 }
        $stream.Position=0x3C
        $peOffset=$reader.ReadInt32()
        if($peOffset -lt 0 -or $peOffset -gt ($stream.Length-8)){ return 0 }
        $stream.Position=$peOffset
        if($reader.ReadUInt32() -ne 0x00004550){ return 0 }
        return [int]$reader.ReadUInt16()
    }finally{
        $stream.Dispose()
    }
}

function Get-RuntimeCandidates([string]$Explicit=''){
    $items=New-Object System.Collections.Generic.List[string]

    function Add-Candidate([string]$Value){
        if(-not[string]::IsNullOrWhiteSpace($Value)){
            $items.Add($Value.Trim().Trim('"'))
        }
    }

    Add-Candidate $Explicit
    Add-Candidate ([Environment]::GetEnvironmentVariable(
        'SHARPEMU_BINK_RUNTIME_DLL',
        'Process'))

    $repo=Get-RepositoryRoot
    foreach($candidate in @(
        (Join-Path $script:PackageRoot 'ThirdParty\BinkRuntime\bink2w64.dll'),
        (Join-Path $repo 'ThirdParty\BinkRuntime\bink2w64.dll')
    )){
        Add-Candidate $candidate
    }

    foreach($dir in @(Get-DeployDirs)){
        Add-Candidate (Join-Path $dir 'bink2w64.dll')
    }

    $radExe=[Environment]::GetEnvironmentVariable(
        'SHARPEMU_RADVIDEO64',
        'Process')
    if(-not[string]::IsNullOrWhiteSpace($radExe)){
        try{
            Add-Candidate (
                Join-Path (
                    Split-Path -Parent $radExe.Trim().Trim('"')
                ) 'bink2w64.dll')
        }catch{}
    }

    $pf86=${env:ProgramFiles(x86)}
    $pf64=$env:ProgramFiles
    if(-not[string]::IsNullOrWhiteSpace($pf86)){
        Add-Candidate (Join-Path $pf86 'RADVideo\bink2w64.dll')
    }
    if(-not[string]::IsNullOrWhiteSpace($pf64)){
        Add-Candidate (Join-Path $pf64 'RADVideo\bink2w64.dll')
    }

    try{
        $pathHit=Get-Command bink2w64.dll -CommandType Application -ErrorAction SilentlyContinue
        if($null -ne $pathHit){
            Add-Candidate $pathHit.Source
        }
    }catch{}

    $seen=@{}
    foreach($item in $items){
        if([string]::IsNullOrWhiteSpace($item)){ continue }
        try{
            $full=[IO.Path]::GetFullPath($item)
        }catch{
            continue
        }
        if($seen.ContainsKey($full)){ continue }
        $seen[$full]=$true
        if(Test-Path -LiteralPath $full -PathType Leaf){
            $full
        }
    }
}

function Find-DumpBin {
    $vsDev=Find-VsDevCmd
    if([string]::IsNullOrWhiteSpace($vsDev)){ return $null }

    $install=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $vsDev))
    $tools=Get-ChildItem -LiteralPath (Join-Path $install 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach($tool in $tools){
        $candidate=Join-Path $tool.FullName 'bin\Hostx64\x64\dumpbin.exe'
        if(Test-Path -LiteralPath $candidate){ return $candidate }
    }
    return $null
}

function Test-BinkRuntime([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){
        return [pscustomobject]@{Path=$Path;Exists=$false;Machine=0;IsX64=$false;ExportsOk=$false;Exports=''}
    }

    $machine=Get-PeMachine $Path
    $isX64=$machine -eq 0x8664
    $required=@('BinkOpen','BinkClose','BinkWait','BinkDoFrame','BinkCopyToBuffer','BinkNextFrame')
    $exportsOk=$false
    $found=@()

    $dumpbin=Find-DumpBin
    if($isX64 -and -not[string]::IsNullOrWhiteSpace($dumpbin)){
        $output=@(& $dumpbin /nologo /exports $Path 2>&1 | ForEach-Object { $_.ToString() })
        foreach($name in $required){
            if(@($output|Select-String -SimpleMatch $name).Count -gt 0){ $found += $name }
        }
        $exportsOk=$found.Count -eq $required.Count
    }

    [pscustomobject]@{
        Path=$Path
        Exists=$true
        Machine=$machine
        IsX64=$isX64
        ExportsOk=$exportsOk
        Exports=($found -join ',')
    }
}

function Assert-ManagedNativeBackend {
    $repo=Get-RepositoryRoot
    $abi=Join-Path $repo $script:RelativeAbi
    $decoder=Join-Path $repo $script:RelativeDecoder
    $hostMovie=Join-Path $repo $script:RelativeHostMovie
    $playback=Join-Path $repo $script:RelativePlayback

    foreach($path in @($abi,$decoder,$hostMovie,$playback)){
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "$script:Tag managed native backend file missing: $path"
        }
    }

    $abiText=[IO.File]::ReadAllText($abi)
    $decoderText=[IO.File]::ReadAllText($decoder)
    $hostText=[IO.File]::ReadAllText($hostMovie)
    $playText=[IO.File]::ReadAllText($playback)

    foreach($pair in @(
        [pscustomobject]@{Name='ABI';Text=$abiText;Marker='ExpectedAbiVersion = 0x0001_0000'},
        [pscustomobject]@{Name='ABI';Text=$abiText;Marker='plugins'},
        [pscustomobject]@{Name='ABI';Text=$abiText;Marker='SharpEmu.BinkNative.dll'},
        [pscustomobject]@{Name='Decoder';Text=$decoderText;Marker='RadBinkNativeSdkDecoderV7500'},
        [pscustomobject]@{Name='HostMovie';Text=$hostText;Marker='MovieMode.NativeRad'},
        [pscustomobject]@{Name='HostMovie';Text=$hostText;Marker='AttachRadNativeMovieLocked'},
        [pscustomobject]@{Name='HostMovie';Text=$hostText;Marker='auto_selected'},
        [pscustomobject]@{Name='Playback';Text=$playText;Marker='IMediaFrameBufferPolicy'},
        [pscustomobject]@{Name='Playback';Text=$playText;Marker='PrimeFirstFrameSynchronously'}
    )){
        if(-not$pair.Text.Contains($pair.Marker)){
            throw "$script:Tag managed native backend prerequisite missing: $($pair.Name)/$($pair.Marker)"
        }
    }

    Write-Tag "ManagedABI_SHA=$(Get-Sha $abi)"
    Write-Tag "ManagedDecoder_SHA=$(Get-Sha $decoder)"
    Write-Tag "HostMovie_SHA=$(Get-Sha $hostMovie)"
    Write-Tag "MediaPlayback_SHA=$(Get-Sha $playback)"
    Write-Tag 'ManagedNativeBackend=READY'
}

function Get-DeployDirs {
    $repo=Get-RepositoryRoot
    @(
        (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2'),
        (Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2')
    )
}
