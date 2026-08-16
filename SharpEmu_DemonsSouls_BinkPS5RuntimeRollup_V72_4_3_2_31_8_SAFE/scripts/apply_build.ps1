param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.8] RAD player disappeared after precheck."
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$apiRel = "src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs"
$profileRel = "src\SharpEmu.Libs\Media\BinkPs5RuntimeProfileV724323180.cs"
$bootstrapRel = "src\SharpEmu.Libs\Media\BinkRadAutoSelectV724323180.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

$radSource = Join-Path $root $radRel
$apiSource = Join-Path $root $apiRel
$audioSource = Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$profileSource = Join-Path $root $profileRel
$bootstrapSource = Join-Path $root $bootstrapRel
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (".sharpemu-hotfix-backup\BinkPS5Runtime_V72_4_3_2_31_8_" + $stamp)

$tracked = @($radRel,$apiRel,$profileRel,$bootstrapRel)
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
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\BinkPs5RuntimeProfileV724323180.cs") -Destination $profileSource -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot "payload\BinkRadAutoSelectV724323180.cs") -Destination $bootstrapSource -Force

    $radText = Read-Normalized -Path $radSource
    $apiText = Read-Normalized -Path $apiSource
    $audioText = Read-Normalized -Path $audioSource
    $profileText = Read-Normalized -Path $profileSource
    $bootstrapText = Read-Normalized -Path $bootstrapSource

    foreach ($marker in @(
        "V72.4.3.2.31.8",
        "RadBinkEmbeddedHostApiV724323171.TryAttach",
        "CaptureRadProcessSnapshot",
        "KillSpawnedRadProcesses",
        'start.ArgumentList.Add("/I2");',
        "external_window_forbidden=True",
        "bink2.rad_renderer_bound",
        "anchor=rad-embedded-playback-ready",
        "BinkDemonSoulsIntroAudioV7243227",
        ".NotifyPresentationStarted(moviePath)"
    )) {
        if (-not $radText.Contains($marker)) {
            throw "[V72.4.3.2.31.8] RAD source marker missing: $marker"
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
        "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS"
    )) {
        if (-not $apiText.Contains($marker)) {
            throw "[V72.4.3.2.31.8] Embedded host API marker missing: $marker"
        }
    }


    foreach ($marker in @(
        "internal static class BinkDemonSoulsIntroAudioV7243227",
        "public static AttachDisposition PrepareAttach",
        "public static bool NotifyPresentationStarted",
        "public static void StopForMovie"
    )) {
        if (-not $audioText.Contains($marker)) {
            throw "[V72.4.3.2.31.8] Intro-audio runtime prerequisite missing: $marker"
        }
    }

    foreach ($marker in @(
        "BinkPs5RuntimeProfileV724323180",
        "bink2.ps5_runtime_profile",
        "decode_owner=official-rad",
        "sharpemu_bgra_conversion=False"
    )) {
        if (-not $profileText.Contains($marker)) {
            throw "[V72.4.3.2.31.8] PS5 runtime profile marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "BinkRadAutoSelectV724323180",
        '"SHARPEMU_BINK_MODE"',
        '"rad"',
        "bink2.rad_auto_selected"
    )) {
        if (-not $bootstrapText.Contains($marker)) {
            throw "[V72.4.3.2.31.8] RAD auto-select marker missing: $marker"
        }
    }

    if ($radText.Contains('start.ArgumentList.Add("/#");')) {
        throw "[V72.4.3.2.31.8] Historical invalid BinkPlay '/#' argument returned."
    }

    if ($apiText.Contains("GetWindowTextW(") -or
        $apiText.Contains("GetWindowTextLengthW(") -or
        $apiText.Contains("GetWindowTitle(")) {
        throw "[V72.4.3.2.31.8] Blocking title-based HWND discovery regression returned."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.8] Building SharpEmu.Libs..."
        & dotnet.exe build "src\SharpEmu.Libs\SharpEmu.Libs.csproj" -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.8] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.8] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.8] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    [IO.File]::WriteAllText($configFile,$radPath,(New-Object Text.UTF8Encoding($false)))

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\BinkPS5Runtime_V72_4_3_2_31_8_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backup,(New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.8] RAD_PLAYER=" + $radPath)
    Write-Host "[V72.4.3.2.31.8] SUCCESS: RAD host API uses PID/MainWindowHandle discovery with no in-process title messaging; verified child parenting required; attract audio remains anchored after host attachment." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.8] Backup: " + $backup)
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

    Write-Host ("[V72.4.3.2.31.8] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.8] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
