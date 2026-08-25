param()
. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'precheck.ps1')
$media=Assert-CurrentMediaStructure
Assert-PerfMarkers

if($media.State -eq 'patched') {
    Write-Tag 'V3.13 hybrid restore already installed; source write skipped.'
    if(-not(Test-Path -LiteralPath (Get-StatePath))) {
        $perf=Get-PerfSnapshot
        [ordered]@{
            version=$script:Version
            installed_at=(Get-Date).ToString('o')
            already_installed=$true
            host_movie_bridge_after=(Get-Sha $media.Path)
            perf_native_worker=$perf.NativeWorker
            perf_presenter=$perf.Presenter
            perf_agc=$perf.Agc
            perf_nihav=$perf.Nihav
            perf_playback=$perf.Playback
        } | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
    }
    exit 0
}

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$target=$media.Path
$perfBefore=Get-PerfSnapshot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'

$backupRoot=
    Join-Path $repo (
        ".sharpemu-hotfix-backup\V74_0_118_7_6_3_13_$stamp")
$backup=Join-Path $backupRoot $script:RelativeHostMovieBridge
New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force |
    Out-Null
Copy-Item -LiteralPath $target -Destination $backup -Force
Set-Content -LiteralPath (Get-BackupPointer) -Value $backupRoot -Encoding UTF8

$temp=
    Join-Path ([IO.Path]::GetTempPath()) (
        'SharpEmu_V11876313_apply_' +
        [Guid]::NewGuid().ToString('N') +
        '.cs')

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force

try {
    $result=Invoke-HybridTransform $target $temp
    if($result.Status -ne 'applied') {
        throw "$script:Tag expected a new HostMovieBridge apply; status=$($result.Status)"
    }

    Invoke-SyntaxProbe $temp 'HostMovieBridgeHybridRestore'
    Copy-Item -LiteralPath $temp -Destination $target -Force

    $installedText=[IO.File]::ReadAllText($target)
    if(-not$installedText.Contains(
        'SHARPEMU_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_RESTORE')) {
        throw "$script:Tag installed hybrid marker missing"
    }

    # The requested performance fixes must remain byte-for-byte unchanged.
    Assert-PerfSnapshotUnchanged $perfBefore

    $buildLog=
        Join-Path $patches (
            "SharpEmu_V74_0_118_7_6_3_13_BUILD_$stamp.log")

    Push-Location $repo
    $savedErrorAction=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & dotnet build `
            .\src\SharpEmu.CLI\SharpEmu.CLI.csproj `
            -c Release `
            -r win-x64 `
            --no-incremental *>&1 |
            Tee-Object -FilePath $buildLog
        $exitCode=$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference=$savedErrorAction
        Pop-Location
    }

    if($exitCode -ne 0) {
        throw "$script:Tag build failed exit=$exitCode log=$buildLog"
    }

    Assert-PerfSnapshotUnchanged $perfBefore
    $perfAfter=Get-PerfSnapshot

    [ordered]@{
        version=$script:Version
        installed_at=(Get-Date).ToString('o')
        backup=$backupRoot
        build_log=$buildLog
        host_movie_bridge_before=$result.Before
        host_movie_bridge_after=(Get-Sha $target)
        historical_media_baseline='V74.0.88.6.2'
        media_route='RAD one-shots -> NIHAV persistent UI Binks'
        performance_sources_touched=0
        perf_native_worker=$perfAfter.NativeWorker
        perf_presenter=$perfAfter.Presenter
        perf_agc=$perfAfter.Agc
        perf_nihav=$perfAfter.Nihav
        perf_playback=$perfAfter.Playback
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8

    Write-Tag (
        "APPLY/BUILD PASSED host_movie_bridge_after=$(Get-Sha $target) " +
        "backup=$backupRoot build_log=$buildLog performance_sources_unchanged=True")
}
catch {
    if(Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
    }
    Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
    throw "$script:Tag APPLY/BUILD failed; HostMovieBridge restored. $($_.Exception.Message)"
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
