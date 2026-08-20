. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$host = Find-UniqueSourceFile $repo 'HostMovieBridge.cs'
$playback = Find-UniqueSourceFile $repo 'MediaFramePlayback.cs'
$libsProject = Join-Path $repo 'src\SharpEmu.Libs\SharpEmu.Libs.csproj'

$hostText = Get-Content -LiteralPath $host -Raw
$playbackText = Get-Content -LiteralPath $playback -Raw

$checks = [ordered]@{
    HostMovieBridge = [bool]($hostText -match 'AttachMovieLocked')
    ExternalRadPath = [bool]($hostText -match 'RadBinkExternalPlaybackV7243231')
    ResolveMode = [bool]($hostText -match 'private\s+static\s+MovieMode\s+ResolveMode')
    MediaFramePlayback = [bool]($playbackText -match 'internal\s+sealed\s+class\s+MediaFramePlayback')
    DecoderInterface = [bool]($playbackText -match 'IMediaFrameDecoder')
    LibsProject = [bool](Test-Path -LiteralPath $libsProject -PathType Leaf)
}

foreach ($key in $checks.Keys) {
    Write-Step ("{0}={1}" -f $key, $checks[$key])
    if (-not $checks[$key]) {
        throw "$script:Tag PRECHECK failed: $key"
    }
}

foreach ($marker in @(
    'SHARPEMU_BINK_NATIVE_RAD_MODE_V75_0_0',
    'SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0'
)) {
    if ($hostText -match [regex]::Escape($marker) -or
        $playbackText -match [regex]::Escape($marker)) {
        throw "$script:Tag V75.0.0 appears already/partially installed: $marker"
    }
}

$existingAbi = Join-Path $repo 'src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs'
$existingDecoder = Join-Path $repo 'src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'
if ((Test-Path -LiteralPath $existingAbi -PathType Leaf) -or
    (Test-Path -LiteralPath $existingDecoder -PathType Leaf)) {
    throw "$script:Tag V75.0.0 managed source already exists."
}

$sdkRoot = Environment.GetEnvironmentVariable('SHARPEMU_BINK_SDK_ROOT')
if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    Write-Step "NativeSdkRoot=NOT_CONFIGURED"
    Write-Step "OperationalState=MANAGED_BRIDGE_INSTALLABLE_NATIVE_DLL_BUILD_SKIPPED_UNTIL_LICENSED_SDK_IS_SUPPLIED"
}
else {
    Write-Step "NativeSdkRoot=$sdkRoot"
    Write-Step "OperationalState=NATIVE_ADAPTER_BUILD_WILL_BE_ATTEMPTED_DURING_RUN_3"
}

Write-Step "DefaultSafety=existing mode=rad remains valid; native-rad auto-preference occurs only when SharpEmu.BinkNative.dll ABI validates."
Write-Step "PRECHECK PASSED."
