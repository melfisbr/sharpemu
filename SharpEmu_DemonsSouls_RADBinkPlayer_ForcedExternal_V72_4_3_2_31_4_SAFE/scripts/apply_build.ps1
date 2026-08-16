param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot
$radPath = Find-RadVideo64 -RepositoryRoot $root -DeepSearch
if ([string]::IsNullOrWhiteSpace($radPath)) {
    throw "[V72.4.3.2.31.4] RAD player is required; precheck should have stopped before apply."
}
$defaultBinkMode = "rad"

$hostRel = "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$audioRel = "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrapRel = "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$radRel = "src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs"
$configRel = "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

$hostBridgePath = Join-Path $root $hostRel
$audio = Join-Path $root $audioRel
$bootstrap = Join-Path $root $bootstrapRel
$radSource = Join-Path $root $radRel
$configFile = Join-Path $root $configRel

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\RADBinkPlayerBackend_V72_4_3_2_31_4_" +
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

$configPreviouslyExisted =
    Test-Path -LiteralPath $configFile -PathType Leaf

if ($configPreviouslyExisted) {
    $dest = Join-Path $backup $configRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $configFile -Destination $dest -Force
}

try {
    # RAD is required in V31.4. No fallback-only build path exists.
    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\RadBinkExternalPlaybackV7243231.cs") `
        -Destination $radSource `
        -Force

    $format = Get-TextFormat -Path $hostBridgePath
    $h = Read-Normalized -Path $hostBridgePath

    if (-not $h.Contains("V72.4.3.2.31.4 RAD_EXTERNAL_BACKEND")) {
        $old = '    private static Thread? _directPresentationThread;'
        $new = @'
    private static Thread? _directPresentationThread;

    // V72.4.3.2.31.4 RAD_EXTERNAL_BACKEND
    private static RadBinkExternalPlaybackV7243231? _radPlayback;
'@
        $h = Replace-ExactOnce -Text $h -Old $old -New $new.TrimEnd() -Label "RAD state"

        $old = '                return _playback is not null || _frameBuffer is not null;'
        $new = @'
                return _playback is not null ||
                       _frameBuffer is not null ||
                       _radPlayback is not null;
'@
        # This active-state expression legitimately occurs more than once in the
        # accumulated HostMovieBridge. Every occurrence must treat RAD playback
        # as active, so an exact-once anchor is semantically wrong here.
        $activeCount = 0
        $cursor = 0
        while (($index = $h.IndexOf($old,$cursor,[StringComparison]::Ordinal)) -ge 0) {
            $h = $h.Substring(0,$index) + $new.TrimEnd() + $h.Substring($index + $old.Length)
            $cursor = $index + $new.TrimEnd().Length
            $activeCount++
        }
        if ($activeCount -lt 1) {
            throw "[V72.4.3.2.31.4] Anchor missing: active RAD state"
        }
        Write-Host ("[V72.4.3.2.31.4] Active-state anchors updated: " + $activeCount)

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
        # V31.4 structural repair: this condition is intentionally present in
        # more than one HostMovieBridge path (including the queued-attach path).
        # Every such busy check must regard RAD as active, so patch all matches
        # atomically instead of requiring an artificial exact-once anchor.
        $busyResult = Replace-AllExact `
            -Text $h `
            -Old $old.TrimEnd() `
            -New $new.TrimEnd() `
            -Label "busy RAD state" `
            -MinimumCount 1
        $h = $busyResult.Text
        Write-Host ("[V72.4.3.2.31.4] Busy-state anchors updated: " + $busyResult.Count)

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
        # `_playback is not null` is also used in unrelated paths. Select
        # the occurrence that belongs to the completion/presentation method by
        # anchoring it immediately before the unique existing completion log.
        $h = Replace-ExactLastBefore `
            -Text $h `
            -Old $old.TrimEnd() `
            -Before "Bink2 bridge completed:" `
            -New $new.TrimEnd() `
            -Label "RAD completion poll"

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
                // V72.4.3.2.31.4 RAD_REQUIRED_NO_FALLBACK
                // Never hide RAD discovery/start failures by silently switching
                // back to NIHAV; that would reproduce the corrupted-color path.
                if (!AttachRadMovieLocked(hostPath))
                {
                    Console.Error.WriteLine(
                        "[LOADER][ERROR] bink2.rad_required_attach_failed " +
                        $"file='{Path.GetFileName(hostPath)}'");
                }
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

        // RAD owns the embedded Bink audio stream and the playback clock.
        // Do not start SharpEmu's generated WAV/tempo sidecar in this mode.

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
        # The queued-attach busy condition is normally already rewritten
        # by the all-occurrence busy-state pass above. Keep this block as an
        # idempotent structural validation/fallback for accumulated checkouts.
        if ($h.Contains($old.TrimEnd())) {
            $queuedResult = Replace-AllExact `
                -Text $h `
                -Old $old.TrimEnd() `
                -New $new.TrimEnd() `
                -Label "queued RAD attach" `
                -MinimumCount 1
            $h = $queuedResult.Text
            Write-Host ("[V72.4.3.2.31.4] Queued RAD attach anchors updated: " + $queuedResult.Count)
        }
        elseif (-not $h.Contains($new.TrimEnd())) {
            throw "[V72.4.3.2.31.4] Queued RAD attach structure is neither baseline nor patched."
        }
    }

    Write-Normalized -Path $hostBridgePath -Text $h -Format $format

    # V31.4 deliberately leaves the V30 sidecar-audio source untouched.
    # RAD mode never enters that sidecar path.
    $format = Get-TextFormat -Path $bootstrap
    $b = Read-Normalized -Path $bootstrap

    if (-not $b.Contains("V72.4.3.2.31.4 RAD_REQUIRED_DEFAULT")) {
        $old = @'
    internal static void Initialize()
    {
'@
        $new = @'
    internal static void Initialize()
    {
        // V72.4.3.2.31.4 RAD_REQUIRED_DEFAULT
        SetDefault("SHARPEMU_BINK_MODE", "rad");
'@
        $b = Replace-ExactOnce -Text $b -Old $old.TrimEnd() -New $new.TrimEnd() -Label "RAD required bootstrap default"
    }
    else {
        foreach ($knownMode in @("rad","native")) {
            $known =
                '        SetDefault("SHARPEMU_BINK_MODE", "' +
                $knownMode +
                '");'
            $desired = '        SetDefault("SHARPEMU_BINK_MODE", "rad");'
            if ($b.Contains($known)) {
                $b = $b.Replace($known,$desired)
            }
        }
    }

    Write-Normalized -Path $bootstrap -Text $b -Format $format

    $afterH = Read-Normalized -Path $hostBridgePath
    $afterB = Read-Normalized -Path $bootstrap
    $afterRad = Read-Normalized -Path $radSource

    foreach ($marker in @(
        "V72.4.3.2.31.4 RAD_EXTERNAL_BACKEND",
        "MovieMode.Rad",
        "AttachRadMovieLocked",
        "RadBinkExternalPlaybackV7243231.TryStart",
        "Bink RAD bridge attached",
        "Bink RAD bridge completed",
        "RAD_REQUIRED_NO_FALLBACK",
        "_radPlayback?.Dispose()"
    )) {
        if (-not $afterH.Contains($marker)) {
            throw "[V72.4.3.2.31.4] Host RAD marker missing: $marker"
        }
    }

    foreach ($legacyBusy in @(
        '            if (_playback is not null || _frameBuffer is not null)',
        '                return _playback is not null || _frameBuffer is not null;'
    )) {
        if ($afterH.Contains($legacyBusy)) {
            throw "[V72.4.3.2.31.4] Legacy busy/active Bink condition remains after structural patch."
        }
    }


    foreach ($marker in @(
        "V72.4.3.2.31.4 RAD_REQUIRED_DEFAULT",
        ('SetDefault("SHARPEMU_BINK_MODE", "' + $defaultBinkMode + '");')
    )) {
        if (-not $afterB.Contains($marker)) {
            throw "[V72.4.3.2.31.4] Bootstrap marker missing: $marker"
        }
    }

    if (-not $afterRad.Contains('start.ArgumentList.Add("binkplay");') -or
        -not $afterRad.Contains('start.ArgumentList.Add("/#");'))
    {
        throw "[V72.4.3.2.31.4] RAD binkplay/auto-exit command marker missing."
    }

    $radCaseStart = $afterH.IndexOf("case MovieMode.Rad:", [StringComparison]::Ordinal)
    $nativeCaseStart = $afterH.IndexOf("case MovieMode.Native:", $radCaseStart, [StringComparison]::Ordinal)
    if ($radCaseStart -lt 0 -or $nativeCaseStart -le $radCaseStart) {
        throw "[V72.4.3.2.31.4] RAD switch structure validation failed."
    }
    $radCase = $afterH.Substring($radCaseStart, $nativeCaseStart - $radCaseStart)
    if ($radCase.Contains("AttachNihavMovieLocked") -or
        $radCase.Contains("AttachFfmpegMovieLocked") -or
        $radCase.Contains("BinkHostAudioBridgeV7241.TryStart"))
    {
        throw "[V72.4.3.2.31.4] RAD mode still contains a silent/internal fallback."
    }

    $attachRadStart = $afterH.IndexOf("private static bool AttachRadMovieLocked", [StringComparison]::Ordinal)
    $attachNihavStart = $afterH.IndexOf("private static bool AttachNihavMovieLocked", $attachRadStart, [StringComparison]::Ordinal)
    if ($attachRadStart -lt 0 -or $attachNihavStart -le $attachRadStart) {
        throw "[V72.4.3.2.31.4] AttachRad method structure validation failed."
    }
    $attachRadSection = $afterH.Substring($attachRadStart, $attachNihavStart - $attachRadStart)
    if ($attachRadSection.Contains("PrepareAttach") -or
        $attachRadSection.Contains("NotifyPresentationStarted") -or
        $attachRadSection.Contains("BinkHostAudioBridge"))
    {
        throw "[V72.4.3.2.31.4] RAD mode still starts SharpEmu sidecar audio."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.31.4] Building SharpEmu.Libs..."

        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.4] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.31.4] Building SharpEmu.CLI win-x64..."

        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.31.4] SharpEmu.CLI build failed."
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

    $stored = [IO.File]::ReadAllText($configFile).Trim()
    if ($stored -ne $radPath -or
        -not (Test-Path -LiteralPath $stored -PathType Leaf))
    {
        throw "[V72.4.3.2.31.4] RAD path configuration verification failed."
    }

    $pointer =
        Join-Path $root (
            ".sharpemu-hotfix-backup\" +
            "RADBinkPlayerBackend_V72_4_3_2_31_4_LAST.txt")

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.31.4] RAD_PLAYER=" + $radPath)
    Write-Host ("[V72.4.3.2.31.4] RAD_PATH_CONFIG=" + $configFile)
    Write-Host "[V72.4.3.2.31.4] SUCCESS: RAD-required backend installed; NIHAV/FFmpeg fallback is forbidden in RAD mode." -ForegroundColor Green
    Write-Host ("[V72.4.3.2.31.4] Backup: " + $backup)
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

    $savedConfig = Join-Path $backup $configRel
    if ($configPreviouslyExisted -and
        (Test-Path -LiteralPath $savedConfig -PathType Leaf))
    {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configFile) | Out-Null
        Copy-Item -LiteralPath $savedConfig -Destination $configFile -Force
    }
    elseif ((-not $configPreviouslyExisted) -and
            (Test-Path -LiteralPath $configFile -PathType Leaf))
    {
        Remove-Item -LiteralPath $configFile -Force
    }

    Write-Host ("[V72.4.3.2.31.4] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.31.4] Restored source from: " + $backup) -ForegroundColor Yellow
    throw
}
