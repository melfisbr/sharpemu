param()
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$pointer=Get-UndoPointerPath

if(-not(Test-Path -LiteralPath $pointer -PathType Leaf)){
    throw "$script:Tag undo pointer missing"
}

$undoRoot=(Get-Content -LiteralPath $pointer -Raw).Trim()
if(-not(Test-Path -LiteralPath $undoRoot -PathType Container)){
    throw "$script:Tag undo backup missing: $undoRoot"
}

$current=Get-CurrentSourceState
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

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
Write-Tag "UNDO RESTORE PASSED source=$undoRoot"
