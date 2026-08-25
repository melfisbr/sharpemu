param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$current=Get-CurrentSourceState
$preV75=Find-PreV75Backup
Assert-PreV75Backup $preV75

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$undoRoot=Join-Path $repo (
    '.sharpemu-hotfix-backup\V75_0_1_2_RAD_EXTERNAL_RESTORE_UNDO_' +
    $stamp)

New-Item -ItemType Directory -Path $undoRoot -Force|Out-Null

# Save the exact current/native state first so this restore itself is reversible.
Copy-Item -LiteralPath $current.Host -Destination (
    Join-Path $undoRoot 'HostMovieBridge.cs') -Force
Copy-Item -LiteralPath $current.Playback -Destination (
    Join-Path $undoRoot 'MediaFramePlayback.cs') -Force

foreach($entry in @(
    [pscustomobject]@{Path=$current.Abi;Name='BinkNativeSdkAbiV7500.cs'},
    [pscustomobject]@{Path=$current.Decoder;Name='RadBinkNativeSdkDecoderV7500.cs'}
)){
    if(Test-Path -LiteralPath $entry.Path -PathType Leaf){
        Copy-Item -LiteralPath $entry.Path -Destination (
            Join-Path $undoRoot $entry.Name) -Force
    }
}

# Save deployed adapter binaries too, if they exist.
foreach($adapter in @(Get-NativeAdapterPaths)){
    if(Test-Path -LiteralPath $adapter -PathType Leaf){
        $label=if($adapter -like '*\Debug\*'){'Debug_SharpEmu.BinkNative.dll'}else{'Release_SharpEmu.BinkNative.dll'}
        Copy-Item -LiteralPath $adapter -Destination (
            Join-Path $undoRoot $label) -Force
    }
}

Set-Content -LiteralPath (Get-UndoPointerPath) -Value $undoRoot -Encoding UTF8
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

try{
    # Restore exactly the files captured immediately before V75 native-rad.
    Copy-Item -LiteralPath (
        Join-Path $preV75.FullName 'HostMovieBridge.cs') `
        -Destination $current.Host -Force
    Copy-Item -LiteralPath (
        Join-Path $preV75.FullName 'MediaFramePlayback.cs') `
        -Destination $current.Playback -Force

    foreach($entry in @(
        [pscustomobject]@{Target=$current.Abi;Name='BinkNativeSdkAbiV7500.cs'},
        [pscustomobject]@{Target=$current.Decoder;Name='RadBinkNativeSdkDecoderV7500.cs'}
    )){
        $saved=Join-Path $preV75.FullName $entry.Name
        if(Test-Path -LiteralPath $saved -PathType Leaf){
            Copy-Item -LiteralPath $saved -Destination $entry.Target -Force
        }else{
            Remove-Item -LiteralPath $entry.Target -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-V75NativeAdapter

    $restored=Get-CurrentSourceState
    Write-CurrentState $restored

    if($restored.NativeHostMarker){
        throw "$script:Tag native host marker still present after restore"
    }
    if($restored.NativePlaybackMarker){
        throw "$script:Tag native playback marker still present after restore"
    }

    $expectedHost=Get-Sha (Join-Path $preV75.FullName 'HostMovieBridge.cs')
    $expectedPlay=Get-Sha (Join-Path $preV75.FullName 'MediaFramePlayback.cs')
    if($restored.HostSha -ne $expectedHost){
        throw "$script:Tag HostMovieBridge restore SHA mismatch expected=$expectedHost actual=$($restored.HostSha)"
    }
    if($restored.PlaybackSha -ne $expectedPlay){
        throw "$script:Tag MediaFramePlayback restore SHA mismatch expected=$expectedPlay actual=$($restored.PlaybackSha)"
    }

    $buildLog=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_RESTORE_BUILD_$stamp.log"
    Push-Location $repo
    $savedErrorActionPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj `
            -c Release -r win-x64 --no-incremental *>&1 |
            Tee-Object -FilePath $buildLog
        $buildExit=$LASTEXITCODE
    }finally{
        $ErrorActionPreference=$savedErrorActionPreference
        Pop-Location
    }

    if($buildExit -ne 0){
        throw "$script:Tag restored source build failed exit=$buildExit log=$buildLog"
    }

    [ordered]@{
        version=$script:Version
        restored_at=(Get-Date).ToString('o')
        pre_v75_backup=$preV75.FullName
        undo_backup=$undoRoot
        build_log=$buildLog
        host_before=$current.HostSha
        playback_before=$current.PlaybackSha
        host_after=$restored.HostSha
        playback_after=$restored.PlaybackSha
        native_abi_after=$restored.NativeAbiExists
        native_decoder_after=$restored.NativeDecoderExists
        adapter_removed=$true
        mode='official-external-rad-pre-v75'
    }|ConvertTo-Json -Depth 8|
        Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8

    Write-Tag "RESTORE/BUILD PASSED pre_v75=$($preV75.FullName)"
    Write-Tag "UndoBackup=$undoRoot"
    Write-Tag "BuildLog=$buildLog"
}catch{
    Write-Warning "$script:Tag restore/build failed; restoring the pre-restore V75 state."

    Copy-Item -LiteralPath (
        Join-Path $undoRoot 'HostMovieBridge.cs') `
        -Destination $current.Host -Force
    Copy-Item -LiteralPath (
        Join-Path $undoRoot 'MediaFramePlayback.cs') `
        -Destination $current.Playback -Force

    foreach($entry in @(
        [pscustomobject]@{Target=$current.Abi;Name='BinkNativeSdkAbiV7500.cs'},
        [pscustomobject]@{Target=$current.Decoder;Name='RadBinkNativeSdkDecoderV7500.cs'}
    )){
        $saved=Join-Path $undoRoot $entry.Name
        if(Test-Path -LiteralPath $saved -PathType Leaf){
            Copy-Item -LiteralPath $saved -Destination $entry.Target -Force
        }else{
            Remove-Item -LiteralPath $entry.Target -Force -ErrorAction SilentlyContinue
        }
    }

    foreach($entry in @(
        [pscustomobject]@{
            Saved=(Join-Path $undoRoot 'Debug_SharpEmu.BinkNative.dll')
            Target=(Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
        },
        [pscustomobject]@{
            Saved=(Join-Path $undoRoot 'Release_SharpEmu.BinkNative.dll')
            Target=(Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
        }
    )){
        if(Test-Path -LiteralPath $entry.Saved -PathType Leaf){
            New-Item -ItemType Directory -Path (
                Split-Path -Parent $entry.Target) -Force|Out-Null
            Copy-Item -LiteralPath $entry.Saved -Destination $entry.Target -Force
        }
    }

    Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
    throw
}
