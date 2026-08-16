param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64

if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31] radvideo64.exe disappeared after precheck."
}

$hostRel = "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$audioRel = "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrapRel = "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"

$hostBridgePath = Join-Path $root $hostRel
$audio = Join-Path $root $audioRel
$bootstrap = Join-Path $root $bootstrapRel
$radSource = Join-Path $root $radRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\RADBinkPlayerBackend_V72_4_3_2_31_" +
        $stamp)

foreach ($rel in @($hostRel,$audioRel,$bootstrapRel)) {
    $source = Join-Path $root $rel
    $dest = Join-Path $backup $rel

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$radPreviouslyExisted =
    Test-Path -LiteralPath $radSource -PathType Leaf

if ($radPreviouslyExisted) {
    $dest = Join-Path $backup $radRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $radSource -Destination $dest -Force
}

try {
    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") `
        -Destination $radSource `
        -Force

    $format = Get-TextFormat -Path $hostBridgePath
    $h = Read-Normalized -Path $hostBridgePath

    if (-not $h.Contains("V72.4.3.2.31 RAD_EXTERNAL_BACKEND")) {
        $old = '    private static Thread? _directPresentationThread;'
        $new = @'
    private static Thread? _directPresentationThread;

    // V72.4.3.2.31 RAD_EXTERNAL_BACKEND
    private static RadBinkExternalPlaybackV7243231? _radPlayback;
'@
        $h = Replace-ExactOnce -Text $h -Old $old -New $new.TrimEnd() -Label "RAD state"

        $old = '                return _playback is not null || _frameBuffer is not null;'
        $new = @'
                return _playback is not null ||
                       _frameBuffer is not null ||
                       _radPlayback is not null;
'@
        $h = Replace-ExactOnce -Text $h -Old $old -New $new.TrimEnd() -Label "same active RAD state"

        $old = @'
            if (_playback is not null || _frameBuffer is not null)
            {
'@
        $new = @'
            if (_playback is not null ||
                _frameBuffer is not null ||
                _radPlayback is not null)
            {
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "busy RAD state"

        $old = @'
            return string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) &&
                   (_playback is not null || _frameBuffer is not null);
'@
        $new = @'
            return string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) &&
                   (_playback is not null ||
                    _frameBuffer is not null ||
                    _radPlayback is not null);
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "post attach RAD state"

        $old = @'
            if (_playback is not null)
            {
'@
        $new = @'
            if (_radPlayback is not null)
            {
                if (!_radPlayback.IsFinished)
                {
                    return false;
                }

                var completedPath = _activePath;
                var elapsedSeconds = _radPlayback.ElapsedSeconds;
                var exitCode = _radPlayback.ExitCode;

                CloseActiveLocked();

                Console.Error.WriteLine(
                    "[LOADER][INFO] Bink RAD bridge completed: " +
                    $"{Path.GetFileName(completedPath)} after " +
                    $"{elapsedSeconds:F2}s exit={exitCode?.ToString() ?? "unknown"}");

                AttachNextQueuedMovieLocked();
                return false;
            }

            if (_playback is not null)
            {
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "RAD completion poll"

        $old = @'
    private static void AttachMovieLocked(string hostPath, MovieMode mode)
    {
        BinkHostAudioBridgeV7241.TryStart(hostPath);
        switch (mode)
        {
'@
        $new = @'
    private static void AttachMovieLocked(string hostPath, MovieMode mode)
    {
        if (mode != MovieMode.Rad)
        {
            BinkHostAudioBridgeV7241.TryStart(hostPath);
        }

        switch (mode)
        {
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "RAD audio ownership"

        $old = @'
            case MovieMode.Native:
                // Stock FFmpeg recognises the KB2 container but does not decode
                // Bink2 video. Prefer the optional NihAV backend for KB2 and
                // retain FFmpeg as the generic fallback for other host movies.
                if (AttachNihavMovieLocked(hostPath))
                {
                    return;
                }
                AttachFfmpegMovieLocked(hostPath);
                return;
'@
        $new = @'
            case MovieMode.Rad:
                // V72.4.3.2.31 RAD_EXTERNAL_BACKEND_ATTACH
                if (AttachRadMovieLocked(hostPath))
                {
                    return;
                }

                BinkHostAudioBridgeV7241.TryStart(hostPath);

                if (AttachNihavMovieLocked(hostPath))
                {
                    return;
                }

                AttachFfmpegMovieLocked(hostPath);
                return;

            case MovieMode.Native:
                // Stock FFmpeg recognises the KB2 container but does not decode
                // Bink2 video. Prefer the optional NihAV backend for KB2 and
                // retain FFmpeg as the generic fallback for other host movies.
                if (AttachNihavMovieLocked(hostPath))
                {
                    return;
                }
                AttachFfmpegMovieLocked(hostPath);
                return;
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "MovieMode.Rad switch"

        $old = @'
    private static bool AttachNihavMovieLocked(string hostPath)
    {
'@
        $new = @'
    private static bool AttachRadMovieLocked(string hostPath)
    {
        if (!TryReadBinkInfo(hostPath, out var info) ||
            !IsValid(info))
        {
            return false;
        }

        if (!RadBinkExternalPlaybackV7243231.TryStart(
                hostPath,
                out var source) ||
            source is null)
        {
            return false;
        }

        CloseActiveLocked();

        _activePath = hostPath;
        _activeInfo = info;
        _radPlayback = source;

        var disposition =
            BinkDemonSoulsIntroAudioV7243227.PrepareAttach(hostPath);

        if (disposition !=
            BinkDemonSoulsIntroAudioV7243227.AttachDisposition.NotHandled)
        {
            _ =
                BinkDemonSoulsIntroAudioV7243227.
                    NotifyPresentationStarted(hostPath);
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] Bink RAD bridge attached: " +
            $"{Path.GetFileName(hostPath)} " +
            $"{info.Width}x{info.Height} @ " +
            $"{info.FramesPerSecondNumerator}/" +
            $"{info.FramesPerSecondDenominator} fps " +
            $"tool='{source.ToolPath}'");
        return true;
    }

    private static bool AttachNihavMovieLocked(string hostPath)
    {
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "AttachRadMovieLocked"

        $old = @'
    private static MovieMode ResolveMode()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE");
'@
        $new = @'
    private static MovieMode ResolveMode()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE");

        if (string.Equals(configured, "rad", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "binkplay", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "radvideo", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Rad;
        }
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "ResolveMode Rad"

        $old = @'
                    if (_playback is null &&
                        _frameBuffer is null &&
                        PendingMoviePaths.Count == 0)
'@
        $new = @'
                    if (_playback is null &&
                        _frameBuffer is null &&
                        _radPlayback is null &&
                        PendingMoviePaths.Count == 0)
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "direct loop RAD lifetime"

        $old = @'
    private static void CloseActiveLocked()
    {
        _playback?.Dispose();
        _playback = null;
        _activePath = null;
'@
        $new = @'
    private static void CloseActiveLocked()
    {
        _playback?.Dispose();
        _playback = null;

        _radPlayback?.Dispose();
        _radPlayback = null;

        _activePath = null;
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "CloseActive RAD"

        $old = @'
        Native,
        Nihav,
        Ffmpeg,
'@
        $new = @'
        Native,
        Rad,
        Nihav,
        Ffmpeg,
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "MovieMode enum Rad"

        $old = @'
            AttachMovieLocked(path, ResolveMode());
            if (_playback is not null || _frameBuffer is not null)
            {
                return;
            }
'@
        $new = @'
            AttachMovieLocked(path, ResolveMode());
            if (_playback is not null ||
                _frameBuffer is not null ||
                _radPlayback is not null)
            {
                return;
            }
'@
        $h = Replace-ExactOnce -Text $h -Old $old.TrimEnd() -New $new.TrimEnd() -Label "queued RAD attach"
    }

    Write-Normalized -Path $hostBridgePath -Text $h -Format $format

    $format = Get-TextFormat -Path $audio
    $a = Read-Normalized -Path $audio

    if (-not $a.Contains("V72.4.3.2.31 RAD_REALTIME_EXTERNAL_AUDIO")) {
        $a = [regex]::Replace(
            $a,
            '(\$"demons-souls-intro-\{key\}-from12-v)(?:29|30)(-\{tempoTag\}\.wav")',
            '${1}31-rad${2}')

        $a = [regex]::Replace(
            $a,
            'return 0\.(?:9054|7000);',
            'return 1.0000;')

        $tempoAnchor =
            "    private static double ResolveV724329AttractTempo()"

        if (-not $a.Contains($tempoAnchor)) {
            throw "[V72.4.3.2.31] Attract tempo method anchor missing."
        }

        $a = $a.Replace(
            $tempoAnchor,
            "    // V72.4.3.2.31 RAD_REALTIME_EXTERNAL_AUDIO`n" +
            $tempoAnchor)
    }

    Write-Normalized -Path $audio -Text $a -Format $format

    $format = Get-TextFormat -Path $bootstrap
    $b = Read-Normalized -Path $bootstrap

    if (-not $b.Contains("V72.4.3.2.31 RAD_BINK_DEFAULT")) {
        $old = @'
    internal static void Initialize()
    {
'@
        $new = @'
    internal static void Initialize()
    {
        // V72.4.3.2.31 RAD_BINK_DEFAULT
        SetDefault("SHARPEMU_BINK_MODE", "rad");
        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "1.0000");
'@
        $b = Replace-ExactOnce -Text $b -Old $old.TrimEnd() -New $new.TrimEnd() -Label "RAD bootstrap defaults"
    }

    $b = [regex]::Replace(
        $b,
        'SetDefault\("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",\s*"0\.(?:9054|7000)"\);',
        'SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "1.0000");')

    Write-Normalized -Path $bootstrap -Text $b -Format $format

    $afterH = Read-Normalized -Path $hostBridgePath
    $afterA = Read-Normalized -Path $audio
    $afterB = Read-Normalized -Path $bootstrap
    $afterRad = Read-Normalized -Path $radSource

    foreach ($marker in @(
        "V72.4.3.2.31 RAD_EXTERNAL_BACKEND",
        "MovieMode.Rad",
        "AttachRadMovieLocked",
        "RadBinkExternalPlaybackV7243231.TryStart",
        "Bink RAD bridge attached",
        "Bink RAD bridge completed",
        "_radPlayback?.Dispose()"
    )) {
        if (-not $afterH.Contains($marker)) {
            throw "[V72.4.3.2.31] Host RAD marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.31 RAD_REALTIME_EXTERNAL_AUDIO",
        "return 1.0000;",
        "from12-v31-rad-"
    )) {
        if (-not $afterA.Contains($marker)) {
            throw "[V72.4.3.2.31] Audio marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.31 RAD_BINK_DEFAULT",
        'SetDefault("SHARPEMU_BINK_MODE", "rad");',
        'SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "1.0000");'
    )) {
        if (-not $afterB.Contains($marker)) {
            throw "[V72.4.3.2.31] Bootstrap marker missing: $marker"
        }
    }

    if (-not $afterRad.Contains('start.ArgumentList.Add("binkplay");')) {
        throw "[V72.4.3.2.31] RAD binkplay command marker missing."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31] Building SharpEmu.Libs..."

        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31] Building SharpEmu.CLI win-x64..."

        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $configDir =
        Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2"

    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $configFile = Join-Path $configDir "radvideo64.path"

    [IO.File]::WriteAllText(
        $configFile,
        $radPath,
        (New-Object Text.UTF8Encoding($false)))

    $stored = [IO.File]::ReadAllText($configFile).Trim()

    if ($stored -ne $radPath -or
        -not (Test-Path -LiteralPath $stored -PathType Leaf))
    {
        throw "[V72.4.3.2.31] RAD path configuration verification failed."
    }

    $pointer =
        Join-Path $root (
            ".sharpemu-hotfix-backup\" +
            "RADBinkPlayerBackend_V72_4_3_2_31_LAST.txt")

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31] RAD_PLAYER=" + $radPath)
    Write-Host ("[V72.4.3.2.31] RAD_PATH_CONFIG=" + $configFile)
    Write-Host ("[V72.4.3.2.31] Backup: " + $backup)
    Write-Host (
        "[V72.4.3.2.31] SUCCESS: official RAD Bink player is primary; " +
        "NIHAV remains fallback.") `
        -ForegroundColor Green
}
catch {
    foreach ($rel in @($hostRel,$audioRel,$bootstrapRel)) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
    }

    $savedRad = Join-Path $backup $radRel

    if ($radPreviouslyExisted) {
        if (Test-Path -LiteralPath $savedRad -PathType Leaf) {
            Copy-Item -LiteralPath $savedRad -Destination $radSource -Force
        }
    }
    elseif (Test-Path -LiteralPath $radSource -PathType Leaf) {
        Remove-Item -LiteralPath $radSource -Force
    }

    Write-Host ("[V72.4.3.2.31] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
