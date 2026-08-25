Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:Tag='[V75.0.1.2-RAD-EXTERNAL-RESTORE]'
$script:Version='V75.0.1.2'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:RelativeHostMovie='src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$script:RelativePlayback='src\SharpEmu.Libs\Media\MediaFramePlayback.cs'
$script:RelativeAbi='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs'
$script:RelativeDecoder='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'

function Write-Tag([string]$Message){
    Write-Host "$script:Tag $Message"
}

function Get-PatchesRoot {
    Split-Path -Parent $script:PackageRoot
}

function Get-RepositoryRoot {
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src'))){
        throw "$script:Tag repository root not found: $repo"
    }
    $repo
}

function Get-Sha([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){
        return ''
    }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-StatePath {
    Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_1_2_RAD_RESTORE_STATE.json'
}

function Get-UndoPointerPath {
    Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_1_2_RAD_RESTORE_LAST_UNDO.txt'
}

function Get-V75RuntimeStatePaths {
    $patches=Get-PatchesRoot
    @(
        (Join-Path $patches 'SharpEmu_V75_0_1_1_BINK2_RUNTIME_STATE.json'),
        (Join-Path $patches 'SharpEmu_V75_0_1_BINK2_RUNTIME_STATE.json')
    )
}

function Find-PreV75Backup {
    $repo=Get-RepositoryRoot
    $backupRoot=Join-Path $repo '.sharpemu-hotfix-backup'
    if(-not(Test-Path -LiteralPath $backupRoot -PathType Container)){
        return $null
    }

    $candidates=@(
        Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'BinkNativeSdkV75_0_0_*' } |
            Sort-Object LastWriteTime -Descending
    )

    foreach($candidate in $candidates){
        $hostMoviePath=Join-Path $candidate.FullName 'HostMovieBridge.cs'
        $play=Join-Path $candidate.FullName 'MediaFramePlayback.cs'
        if(-not(Test-Path -LiteralPath $hostMoviePath -PathType Leaf) -or
           -not(Test-Path -LiteralPath $play -PathType Leaf)){
            continue
        }

        $hostText=[IO.File]::ReadAllText($hostMoviePath)
        $playText=[IO.File]::ReadAllText($play)

        # Do not choose a backup that was already taken after the native V75
        # source patch. We want the exact source state from immediately before
        # V75 native-rad was introduced.
        if($hostText.Contains('SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0')){
            continue
        }
        if($playText.Contains('SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0')){
            continue
        }

        return $candidate
    }

    $null
}

function Get-InstalledRadVideo64 {
    $configured=[Environment]::GetEnvironmentVariable(
        'SHARPEMU_RADVIDEO64',
        'Process')
    if(-not[string]::IsNullOrWhiteSpace($configured) -and
       (Test-Path -LiteralPath $configured -PathType Leaf)){
        return (Resolve-Path -LiteralPath $configured).Path
    }

    $pf86=${env:ProgramFiles(x86)}
    if(-not[string]::IsNullOrWhiteSpace($pf86)){
        $candidate=Join-Path $pf86 'RADVideo\radvideo64.exe'
        if(Test-Path -LiteralPath $candidate -PathType Leaf){
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $null
}

function Get-NativeAdapterPaths {
    $repo=Get-RepositoryRoot
    @(
        (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'),
        (Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
    )
}

function Get-CurrentSourceState {
    $repo=Get-RepositoryRoot
    $hostMoviePath=Join-Path $repo $script:RelativeHostMovie
    $play=Join-Path $repo $script:RelativePlayback
    $abi=Join-Path $repo $script:RelativeAbi
    $decoder=Join-Path $repo $script:RelativeDecoder

    foreach($path in @($hostMoviePath,$play)){
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "$script:Tag required source missing: $path"
        }
    }

    $hostText=[IO.File]::ReadAllText($hostMoviePath)
    $playText=[IO.File]::ReadAllText($play)

    [pscustomobject]@{
        Host=$hostMoviePath
        Playback=$play
        Abi=$abi
        Decoder=$decoder
        HostSha=(Get-Sha $hostMoviePath)
        PlaybackSha=(Get-Sha $play)
        AbiSha=(Get-Sha $abi)
        DecoderSha=(Get-Sha $decoder)
        NativeHostMarker=$hostText.Contains(
            'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0')
        NativePlaybackMarker=$playText.Contains(
            'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0')
        NativeAbiExists=(Test-Path -LiteralPath $abi -PathType Leaf)
        NativeDecoderExists=(Test-Path -LiteralPath $decoder -PathType Leaf)
    }
}

function Write-CurrentState([object]$state){
    Write-Tag "CurrentHostMovieSHA=$($state.HostSha)"
    Write-Tag "CurrentPlaybackSHA=$($state.PlaybackSha)"
    Write-Tag "CurrentAbiSHA=$($state.AbiSha)"
    Write-Tag "CurrentDecoderSHA=$($state.DecoderSha)"
    Write-Tag "NativeHostMarker=$($state.NativeHostMarker)"
    Write-Tag "NativePlaybackMarker=$($state.NativePlaybackMarker)"
    Write-Tag "NativeAbiExists=$($state.NativeAbiExists)"
    Write-Tag "NativeDecoderExists=$($state.NativeDecoderExists)"
}

function Assert-PreV75Backup([IO.DirectoryInfo]$Backup){
    if($null -eq $Backup){
        throw "$script:Tag no clean pre-V75 backup found under .sharpemu-hotfix-backup\BinkNativeSdkV75_0_0_*"
    }

    $hostMoviePath=Join-Path $Backup.FullName 'HostMovieBridge.cs'
    $play=Join-Path $Backup.FullName 'MediaFramePlayback.cs'
    $hostText=[IO.File]::ReadAllText($hostMoviePath)
    $playText=[IO.File]::ReadAllText($play)

    if($hostText.Contains('SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0')){
        throw "$script:Tag selected backup already contains V75 native host marker: $($Backup.FullName)"
    }
    if($playText.Contains('SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0')){
        throw "$script:Tag selected backup already contains V75 native playback marker: $($Backup.FullName)"
    }

    # The external RAD route must exist in the backup. This marker predates V75
    # and is the route that was working before the native adapter experiment.
    if(-not$hostText.Contains('Bink RAD bridge attached')){
        throw "$script:Tag selected backup does not contain external RAD bridge logging"
    }

    Write-Tag "PreV75Backup=$($Backup.FullName)"
    Write-Tag "PreV75HostMovieSHA=$(Get-Sha $hostMoviePath)"
    Write-Tag "PreV75PlaybackSHA=$(Get-Sha $play)"
}

function Remove-V75NativeAdapter {
    foreach($adapter in @(Get-NativeAdapterPaths)){
        if(Test-Path -LiteralPath $adapter -PathType Leaf){
            Remove-Item -LiteralPath $adapter -Force
            Write-Tag "RemovedNativeAdapter=$adapter"
        }
    }

    # V75.0.1.x only copied a runtime DLL when a compatible runtime was found.
    # Remove only paths recorded by its state and only when the hash still
    # matches the recorded deployment, so unrelated DLLs are never deleted.
    foreach($statePath in @(Get-V75RuntimeStatePaths)){
        if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){
            continue
        }
        try{
            $runtimeState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
            if($runtimeState.PSObject.Properties.Name -contains 'runtime_deployed_paths'){
                foreach($deployed in @($runtimeState.runtime_deployed_paths)){
                    $path=[string]$deployed
                    if([string]::IsNullOrWhiteSpace($path) -or
                       -not(Test-Path -LiteralPath $path -PathType Leaf)){
                        continue
                    }

                    $canDelete=$true
                    if($runtimeState.PSObject.Properties.Name -contains 'runtime_sha256' -and
                       -not[string]::IsNullOrWhiteSpace([string]$runtimeState.runtime_sha256)){
                        $canDelete=(Get-Sha $path) -eq
                            ([string]$runtimeState.runtime_sha256).ToUpperInvariant()
                    }

                    if($canDelete){
                        Remove-Item -LiteralPath $path -Force
                        Write-Tag "RemovedDeployedNativeRuntime=$path"
                    }
                }
            }
        }catch{
            Write-Tag "RuntimeStateReadWarning=$statePath :: $($_.Exception.Message)"
        }
    }
}

function Set-ExternalRadTestEnvironment {
    $rad=Get-InstalledRadVideo64
    if($null -eq $rad){
        throw "$script:Tag official RAD executable not found at Program Files (x86)\RADVideo\radvideo64.exe"
    }

    Remove-Item Env:SHARPEMU_BINK_NATIVE_DLL -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_BINK_RUNTIME_DLL -ErrorAction SilentlyContinue

    $env:SHARPEMU_RADVIDEO64=$rad
    $env:SHARPEMU_BINK_MODE='rad'
    $env:SHARPEMU_BINK_NATIVE_PREFER='0'
    $env:SHARPEMU_BINK_NATIVE_FALLBACK='1'
    $env:SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE='1'
    $env:SHARPEMU_DS_UI_BINK_INTERNAL='0'
    $env:SHARPEMU_LOG_AUDIO_OUT2='1'
    $env:SHARPEMU_LOG_AMPR_READS='1'

    Write-Tag "ExternalRAD=$rad"
}
