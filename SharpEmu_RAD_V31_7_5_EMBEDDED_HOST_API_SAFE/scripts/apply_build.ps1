param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.7.5] RAD player disappeared after precheck."
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$apiRel = "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

$radSource = Join-Path $root $radRel
$apiSource = Join-Path $root $apiRel
$audioSource = Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_5_" + $stamp)

$tracked = @($radRel,$apiRel)
$existed = @{}
foreach ($rel in $tracked) {
    $source = Join-Path $root $rel
    $existed[$rel] = Test-Path -LiteralPath $source -PathType Leaf
    if ($existed[$rel]) {
        $dest = Join-Path $backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}

$configPreviouslyExisted = Test-Path -LiteralPath $configFile -PathType Leaf
if ($configPreviouslyExisted) {
    $destConfig = Join-Path $backup $configRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destConfig) | Out-Null
    Copy-Item -LiteralPath $configFile -Destination $destConfig -Force
}

try {
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") -Destination $radSource -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\RadBinkEmbeddedHostApiV724323171.cs") -Destination $apiSource -Force

    $radText = Read-Normalized -Path $radSource
    $apiText = Read-Normalized -Path $apiSource
    $audioText = Read-Normalized -Path $audioSource

    foreach ($marker in @(
        "V72.4.3.2.31.7.5",
        "RadBinkEmbeddedHostApiV724323171.TryAttach",
        "CaptureRadProcessSnapshot",
        "KillSpawnedRadProcesses",
        "TryReadBinkHeaderMetadata",
        'start.ArgumentList.Add("/I2");',
        'start.ArgumentList.Add("/Z0");',
        "bink2.rad_audio_track_select",
        "external_window_forbidden=True",
        "bink2.rad_renderer_bound",
        "BinkHostPlaybackAssist.OnMovieFrame(moviePath)",
        "BinkHostPlaybackAssist.EndMovieSession(MoviePath)",
        "bink2.rad_guest_work_throttle_begin",
        "bink2.rad_guest_work_throttle_heartbeat",
        "bink2.rad_guest_work_throttle_end",
        "anchor=rad-embedded-playback-ready+guest-throttle-active",
        "BinkDemonSoulsIntroAudioV7243227",
        ".NotifyPresentationStarted(moviePath)"
    )) {
        if (-not $radText.Contains($marker)) {
            throw "[V72.4.3.2.31.7.5] RAD source marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "internal interface IRadBinkHostApi",
        "class RadBinkEmbeddedHostApiV724323171",
        "process.MainWindowHandle",
        "CaptureRadProcessSnapshot",
        "bink2.rad_host_attach_begin",
        "bink2.rad_renderer_window_ready",
        "discovery=pid-mainwindow-no-windowtext",
        "SetParent",
        "GetParent",
        "IsChild",
        "WsChild",
        "bink2.rad_host_attached",
        "verified_parent=True",
        "render_location=sharpemu-child-window",
        "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS",
        "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
        "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
        "bink2.rad_visual_cutoff",
        "postroll_logo_visible=False",
        "bink2.rad_renderer_priority",
        "bink2.rad_renderer_revealed",
        "bink2.rad_nominal_end",
        "postroll_logo_suppressed=True",
        "SwpNoZOrder"
    )) {
        if (-not $apiText.Contains($marker)) {
            throw "[V72.4.3.2.31.7.5] Embedded host API marker missing: $marker"
        }
    }


    foreach ($marker in @(
        "internal static class BinkDemonSoulsIntroAudioV7243227",
        "public static AttachDisposition PrepareAttach",
        "public static bool NotifyPresentationStarted",
        "public static void StopForMovie"
    )) {
        if (-not $audioText.Contains($marker)) {
            throw "[V72.4.3.2.31.7.5] Intro-audio runtime prerequisite missing: $marker"
        }
    }

    if ($radText.Contains('start.ArgumentList.Add("/#");')) {
        throw "[V72.4.3.2.31.7.5] Historical invalid BinkPlay '/#' argument returned."
    }

    if ($apiText.Contains("GetWindowTextW(") -or
        $apiText.Contains("GetWindowTextLengthW(") -or
        $apiText.Contains("GetWindowTitle(")) {
        throw "[V72.4.3.2.31.7.5] Blocking title-based HWND discovery regression returned."
    }

    if ($apiText.Contains("SwpFrameChanged") -or
        $apiText.Contains("period: 100")) {
        throw "[V72.4.3.2.31.7.5] Continuous 100 ms FRAMECHANGED resize churn regression returned."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.7.5] Building SharpEmu.Libs..."
        & dotnet.exe build "src\SharpEmu.Libs\SharpEmu.Libs.csproj" -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7.5] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.7.5] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.7.5] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "[V72.4.3.2.31.7.5] Rebuilding exact 1.0000x attract audio cache used by runtime..."
    & "$PSScriptRoot\prewarm_attract_audio.ps1" -RepositoryRoot $root

    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    [IO.File]::WriteAllText($configFile,$radPath,(New-Object Text.UTF8Encoding($false)))

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\RADEmbeddedHost_V72_4_3_2_31_7_5_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backup,(New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.7.5] RAD_PLAYER=" + $radPath)
    Write-Host "[V72.4.3.2.31.7.5] SUCCESS: external RAD is now wired into the existing BinkHostPlaybackAssist CPU/GPU cinematic gates; child HWND cuts before post-roll branding; attract sidecar remains native 1.0000x." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.7.5] Backup: " + $backup)
}
catch {
    foreach ($rel in $tracked) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel
        if ($existed[$rel] -and (Test-Path -LiteralPath $saved -PathType Leaf)) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
        elseif ((-not $existed[$rel]) -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    $savedConfig = Join-Path $backup $configRel
    if ($configPreviouslyExisted -and (Test-Path -LiteralPath $savedConfig -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
        Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
    }
    elseif ((-not $configPreviouslyExisted) -and (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        Remove-Item -LiteralPath $configFile -Force
    }

    Write-Host ("[V72.4.3.2.31.7.5] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.7.5] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
