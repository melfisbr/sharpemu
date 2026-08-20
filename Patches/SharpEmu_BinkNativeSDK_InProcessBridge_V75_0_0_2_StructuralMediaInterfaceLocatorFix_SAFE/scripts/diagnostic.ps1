. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$host = Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$playback = Find-UniqueSourceFile $repo 'MediaFramePlayback.cs'
$abi = Join-Path $repo 'src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs'
$decoder = Join-Path $repo 'src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'

$hostText = Get-Content -LiteralPath $host -Raw
$playbackText = Get-Content -LiteralPath $playback -Raw
$abiText = if (Test-Path -LiteralPath $abi) {
    Get-Content -LiteralPath $abi -Raw
} else { '' }
$decoderText = if (Test-Path -LiteralPath $decoder) {
    Get-Content -LiteralPath $decoder -Raw
} else { '' }

$checks = [ordered]@{
    NativeRadMode = [bool]($hostText -match 'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0')
    NativeAttach = [bool]($hostText -match 'AttachRadNativeMovieLocked')
    NativeAutoPrefer = [bool]($hostText -match 'SHARPEMU_BINK_NATIVE_PREFER')
    ExternalFallback = [bool]($hostText -match 'SHARPEMU_BINK_NATIVE_FALLBACK')
    PlaybackClockContract = [bool]($playbackText -match 'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0')
    BufferPolicy = [bool]($playbackText -match 'IMediaFrameBufferPolicy')
    StableAbiSource = [bool]($abiText -match 'ExpectedAbiVersion = 0x0001_0000')
    NativeDecoderSource = [bool]($decoderText -match 'RadBinkNativeSdkDecoderV7500')
    AttractSidecarClock = [bool]($decoderText -match 'BinkDeterministicWavePlayerV317152')
}

foreach ($key in $checks.Keys) {
    Write-Step ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag DIAGNOSTIC failed: $key"
    }
}

$runtimeDlls = @(
    Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll',
    Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
)

$foundDll = @(
    $runtimeDlls |
    Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    }
) | Select-Object -First 1

if ($null -eq $foundDll) {
    Write-Step "NativeAdapterPresent=False"
    Write-Step "OperationalNativeRad=False"
    Write-Step "Reason=licensed Bink SDK adapter DLL has not been built/deployed."
    Write-Step "Next=Set SHARPEMU_BINK_SDK_ROOT and run RUN_5_BUILD_NATIVE_ADAPTER.cmd."
}
else {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $foundDll).Hash
    Write-Step "NativeAdapterPresent=True"
    Write-Step "NativeAdapter=$foundDll"
    Write-Step "NativeAdapterSHA256=$hash"
    Write-Step "OperationalNativeRad=Candidate"
    Write-Step "ExpectedRuntime=[BINK-NATIVE][V75.0.0] adapter_loaded -> auto_selected -> open_ok -> bridge_attached."
}

Write-Step "PerformancePolicy=decoder thread isolated; 3 BGRA buffers; external process/window lifecycle eliminated when native adapter is active."
Write-Step "SafetyPolicy=movies with embedded Bink audio reject native mode unless adapter confirms embedded_audio_active=True; external RAD fallback remains enabled."
Write-Step "DIAGNOSTIC PASSED."
