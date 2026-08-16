param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.6] RAD player disappeared after precheck."
}

$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$audioRel = "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

$radSource = Join-Path $root $radRel
$audioSource = Join-Path $root $audioRel
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (
    ".sharpemu-hotfix-backup\RADAttractAudio_V72_4_3_2_31_6_" + $stamp)

foreach ($rel in @($radRel,$audioRel)) {
    $source = Join-Path $root $rel
    $dest = Join-Path $backup $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$configPreviouslyExisted = Test-Path -LiteralPath $configFile -PathType Leaf
if ($configPreviouslyExisted) {
    $destConfig = Join-Path $backup $configRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destConfig) | Out-Null
    Copy-Item -LiteralPath $configFile -Destination $destConfig -Force
}

try {
    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") `
        -Destination $radSource `
        -Force

    # Add a narrow stop hook to the existing audited V30 intro-audio helper.
    # This lets the RAD process lifetime stop the WinMM WAV when attract ends
    # or when the user closes the player early.
    $format = Get-TextFormat -Path $audioSource
    $audioText = Read-Normalized -Path $audioSource

    if (-not $audioText.Contains("V72.4.3.2.31.6 RAD_ATTRACT_AUDIO_STOP")) {
        $old = @'
    private static void ResetStateForNonIntro(string moviePath)
'@
        $new = @'
    // V72.4.3.2.31.6 RAD_ATTRACT_AUDIO_STOP
    public static void StopForMovie(string moviePath)
    {
        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return;
        }

        lock (Gate)
        {
            if (!string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (_timelineStarted)
            {
                _ = PlaySound(null, IntPtr.Zero, 0);
            }

            _activeRoot = null;
            _activeMovie = null;
            _activeMode = TimelineMode.None;
            _timelineStarted = false;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_stop " +
                $"file='{Path.GetFileName(moviePath)}'");
        }
    }

    private static void ResetStateForNonIntro(string moviePath)
'@
        $audioText = Replace-ExactOnce `
            -Text $audioText `
            -Old $old.TrimEnd() `
            -New $new.TrimEnd() `
            -Label "RAD attract audio stop hook"
        Write-Normalized -Path $audioSource -Text $audioText -Format $format
    }

    $radText = Read-Normalized -Path $radSource
    $audioAfter = Read-Normalized -Path $audioSource

    foreach ($marker in @(
        "V72.4.3.2.31.6",
        "RAD_ATTRACT_AUDIO_NATIVE_RATE",
        "TryReadBinkAudioTrackIds",
        "bink2.rad_audio_header",
        "bink2.rad_attract_audio_sidecar",
        "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
        '"1.0000"',
        'start.ArgumentList.Add("binkplay");',
        'start.ArgumentList.Add(moviePath);',
        "BinkDemonSoulsIntroAudioV7243227.PrepareAttach",
        "BinkDemonSoulsIntroAudioV7243227.StopForMovie"
    )) {
        if (-not $radText.Contains($marker)) {
            throw "[V72.4.3.2.31.6] RAD source marker missing: $marker"
        }
    }

    if (-not $audioAfter.Contains("V72.4.3.2.31.6 RAD_ATTRACT_AUDIO_STOP") -or
        -not $audioAfter.Contains("public static void StopForMovie"))
    {
        throw "[V72.4.3.2.31.6] Intro-audio stop hook verification failed."
    }

    if ($radText.Contains('start.ArgumentList.Add("/#");')) {
        throw "[V72.4.3.2.31.6] Invalid historical BinkPlay '/#' argument returned."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.6] Building SharpEmu.Libs..."
        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.6] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.6] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.6] SharpEmu.CLI build failed."
        }

        Write-Host "[V72.4.3.2.31.6] Prewarming native-rate attract audio cache..."
        & "$PSScriptRoot\prewarm_attract_audio.ps1" `
            -RepositoryRoot $root `
            -GameRoot "F:\JOGOSPS5\PPSA01341"
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.6] Attract audio cache prewarm failed."
        }
    }
    finally {
        Pop-Location
    }

    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    [IO.File]::WriteAllText(
        $configFile,
        $radPath,
        (New-Object Text.UTF8Encoding($false)))

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\RADAttractAudio_V72_4_3_2_31_6_LAST.txt"
    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.6] RAD_PLAYER=" + $radPath)
    Write-Host "[V72.4.3.2.31.6] SUCCESS: RAD video/embedded-audio preserved; zero-track attract_movie uses audited external AT9 stems at native 1.0000 tempo." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.6] Backup: " + $backup)
}
catch {
    foreach ($rel in @($radRel,$audioRel)) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel
        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
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

    Write-Host ("[V72.4.3.2.31.6] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.6] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
