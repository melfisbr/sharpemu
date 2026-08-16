param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

$required = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\SharpEmu.Libs.csproj",
    "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
)

foreach ($rel in $required) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.31.7.2] Required file missing: $path"
    }
}

$hostText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs")
$audioText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs")
$bootstrapText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs")
$radText = Read-Normalized -Path (Join-Path $root "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs")

foreach ($marker in @(
    "RAD_EXTERNAL_BACKEND",
    "MovieMode.Rad",
    "AttachRadMovieLocked",
    "Bink RAD bridge attached",
    "Bink RAD bridge completed"
)) {
    if (-not $hostText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.2] RAD HostMovieBridge prerequisite missing: '$marker'."
    }
}

foreach ($marker in @(
    "BinkDemonSoulsIntroAudioV7243227",
    "pr_demons_souls_intro_music.at9",
    "pr_demons_souls_intro_sfx.at9",
    "pr_demons_souls_intro_vo.at9",
    "AttractOffsetSeconds",
    "public static bool NotifyPresentationStarted",
    "public static void StopForMovie"
)) {
    if (-not $audioText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.2] V31.6 intro-audio prerequisite missing: '$marker'."
    }
}

if (-not $bootstrapText.Contains('SetDefault("SHARPEMU_BINK_MODE", "rad");')) {
    throw "[V72.4.3.2.31.7.2] RAD default is not installed in BinkRuntimeBootstrapV6113166.cs."
}

foreach ($marker in @(
    "TryReadBinkAudioTrackIds",
    "bink2.rad_audio_header",
    "bink2.rad_attract_audio_sidecar"
)) {
    if (-not $radText.Contains($marker)) {
        throw "[V72.4.3.2.31.7.2] V31.6 RAD source prerequisite missing: '$marker'."
    }
}

$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
$report = Write-RadDiscoveryReport -RepositoryRoot $root -RadPath $radPath
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7.2] RAD REQUIRED: radvideo64.exe not found. Discovery report: $report"
}

$radItem = Get-Item -LiteralPath $radPath
$radVersion = $radItem.VersionInfo.FileVersion
$radHash = (Get-FileHash -LiteralPath $radPath -Algorithm SHA256).Hash

# RAD Video Tools and the licensed Bink SDK are different products.  Search for
# a real SDK runtime DLL only to report whether true same-process decoding is
# currently possible; V31.7.2 does not invent an ABI when that DLL is absent.
$sdkCandidates = @(
    (Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\bink2w64.dll"),
    (Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\bink2w64.dll"),
    (Join-Path (Split-Path -Parent $radPath) "bink2w64.dll"),
    (Join-Path (Split-Path -Parent $radPath) "binkw64.dll")
)
$sdkDll = $sdkCandidates | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and
    (Test-Path -LiteralPath $_ -PathType Leaf)
} | Select-Object -First 1

Write-Host "[V72.4.3.2.31.7.2] PRECHECK PASSED."
Write-Host ("[V72.4.3.2.31.7.2] RAD_PLAYER=" + $radPath)
Write-Host ("[V72.4.3.2.31.7.2] RAD_VERSION=" + $radVersion)
Write-Host ("[V72.4.3.2.31.7.2] RAD_SHA256=" + $radHash)
Write-Host "[V72.4.3.2.31.7.2] INTEGRATION_MODE=SharpEmu child-window host API (strict: no independent RAD top-level window)."
Write-Host "[V72.4.3.2.31.7.2] AUDIO_SYNC=attract audio starts only after RAD HWND embedding + playback anchor."
if ($null -ne $sdkDll) {
    Write-Host ("[V72.4.3.2.31.7.2] BINK_SDK_RUNTIME_CANDIDATE=" + $sdkDll) -ForegroundColor Yellow
    Write-Host "[V72.4.3.2.31.7.2] NOTE: candidate is not called until an exact matching licensed SDK ABI/header is supplied."
}
else {
    Write-Host "[V72.4.3.2.31.7.2] BINK_SDK_RUNTIME_CANDIDATE=not-found"
    Write-Host "[V72.4.3.2.31.7.2] TRUE_IN_PROCESS_DECODER=False (RAD Video Tools install contains the player, not the licensed Bink SDK DLL)." -ForegroundColor Yellow
}
Write-Host ("[V72.4.3.2.31.7.2] Discovery report: " + $report)
