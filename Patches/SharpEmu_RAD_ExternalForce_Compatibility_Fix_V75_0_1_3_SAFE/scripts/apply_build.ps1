param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')

$s=Assert-CompatibilityBaseline
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=Join-Path $repo ".sharpemu-hotfix-backup\V75_0_1_3_RAD_EXTERNAL_$stamp"
New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null

$hostBackup=Join-Path $backupRoot 'HostMovieBridge.cs'
Copy-Item -LiteralPath $s.Host -Destination $hostBackup -Force
Set-Content -LiteralPath (Get-BackupPointer) -Value $backupRoot -Encoding UTF8

$tmp=Join-Path ([IO.Path]::GetTempPath()) ("SharpEmu_V75013_apply_"+[Guid]::NewGuid().ToString('N')+'.cs')
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
try{
    $r=Invoke-HostPatch $s.Host $tmp
    if($r.Already -eq 2 -and $r.Applied -eq 0){
        Write-Tag 'HostMovieBridge V75.0.1.3 already patched.'
    }elseif($r.Applied -ne 2 -or $r.Already -ne 0){
        throw "$script:Tag expected applied=2/already=0 or applied=0/already=2; got applied=$($r.Applied) already=$($r.Already)"
    }

    Copy-Item -LiteralPath $tmp -Destination $s.Host -Force
    $hostAfter=Get-Sha $s.Host
    Write-Tag "HostMovieAfterSHA=$hostAfter"

    # Critical V75.0.1.3 rule: DO NOT touch MediaFramePlayback or the managed
    # ABI/decoder source files. They contain accumulated compatibility contracts
    # now referenced elsewhere in the tree.
    if((Get-Sha $s.Playback) -ne $script:ExpectedPlaybackSha){
        throw "$script:Tag playback changed unexpectedly during apply"
    }
    if((Get-Sha $s.Abi) -ne $script:ExpectedAbiSha -or (Get-Sha $s.Decoder) -ne $script:ExpectedDecoderSha){
        throw "$script:Tag managed V75 source changed unexpectedly during apply"
    }

    Backup-And-RemoveNativeAdapter $backupRoot

    $buildLog=Join-Path $patches "SharpEmu_V75_0_1_3_RAD_EXTERNAL_BUILD_$stamp.log"
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
        throw "$script:Tag build failed exit=$buildExit log=$buildLog"
    }

    # Build must not redeploy the optional native adapter.
    Backup-And-RemoveNativeAdapter ''

    [ordered]@{
        version=$script:Version
        installed_at=(Get-Date).ToString('o')
        backup=$backupRoot
        build_log=$buildLog
        host_before=$s.HostSha
        host_after=$hostAfter
        playback_preserved=$script:ExpectedPlaybackSha
        abi_preserved=$script:ExpectedAbiSha
        decoder_preserved=$script:ExpectedDecoderSha
        native_adapter_removed=$true
        mode='official-external-rad-compatible'
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8

    Write-Tag "APPLY/BUILD PASSED host_after=$hostAfter backup=$backupRoot build_log=$buildLog"
}catch{
    Write-Warning "$script:Tag apply/build failed; restoring HostMovieBridge and adapter DLL backup."
    Copy-Item -LiteralPath $hostBackup -Destination $s.Host -Force

    foreach($entry in @(
        [pscustomobject]@{Saved=(Join-Path $backupRoot 'Debug_SharpEmu.BinkNative.dll');Target=(Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')},
        [pscustomobject]@{Saved=(Join-Path $backupRoot 'Release_SharpEmu.BinkNative.dll');Target=(Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')}
    )){
        if(Test-Path -LiteralPath $entry.Saved -PathType Leaf){
            New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Target) -Force|Out-Null
            Copy-Item -LiteralPath $entry.Saved -Destination $entry.Target -Force
        }
    }
    Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
    throw
}finally{
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
