param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [switch]$SkipBuild
)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot

$decoderRel =
    "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audioRel =
    "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs"
$bootstrapRel =
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$chromaRel =
    "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs"
$introAudioRel =
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$toolRel =
    "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

$decoder = Join-Path $root $decoderRel
$audio = Join-Path $root $audioRel
$bootstrap = Join-Path $root $bootstrapRel
$chroma = Join-Path $root $chromaRel
$introAudio = Join-Path $root $introAudioRel
$tool = Join-Path $root $toolRel

$nativePayload =
    Join-Path $packageRoot "payload\nihav-tool-native.exe"
$chromaPayload =
    Join-Path $packageRoot "payload\BinkChromaRepairV7243227.cs"
$introAudioPayload =
    Join-Path $packageRoot "payload\BinkDemonSoulsIntroAudioV7243227.cs"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\BinkExecutionColorAudio_V72_4_3_2_27_" +
        $stamp)

$backupFiles = @(
    $decoderRel,
    $audioRel,
    $bootstrapRel,
    $toolRel
)

foreach ($rel in $backupFiles) {
    $source = Join-Path $root $rel
    $destination = Join-Path $backup $rel

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Split-Path -Parent $destination) |
        Out-Null

    Copy-Item `
        -LiteralPath $source `
        -Destination $destination `
        -Force
}

foreach ($rel in @($chromaRel,$introAudioRel)) {
    $source = Join-Path $root $rel

    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $destination = Join-Path $backup $rel

        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Split-Path -Parent $destination) |
            Out-Null

        Copy-Item `
            -LiteralPath $source `
            -Destination $destination `
            -Force
    }
}

$pointer =
    Join-Path $root (
        ".sharpemu-hotfix-backup\" +
        "BinkExecutionColorAudio_V72_4_3_2_27_LAST.txt")

try {
    # -------------------------------------------------------------
    # 1. Decoder: no stale-frame dropping + U/V boundary repair.
    # -------------------------------------------------------------
    $decoderFormat = Get-TextFormat -Path $decoder
    $d = Read-Normalized -Path $decoder

    if (-not $d.Contains("V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP")) {
        $d =
            Replace-RegexOnce `
                -Text $d `
                -Pattern '^[ \t]*var maxCatchupSkip = [0-9]+;' `
                -Replacement (
                    "        // V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP`n" +
                    "        // Preserve decoded frame order. The 60-frame startup buffer`n" +
                    "        // absorbs the measured short-movie producer deficit instead of`n" +
                    "        // creating visible jumps by deleting stale frames.`n" +
                    "        var maxCatchupSkip = 0;") `
                -Label "maxCatchupSkip"
    }

    if (-not $d.Contains("V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR")) {
        $anchor = "        var yPlane = planar[..yBytes];"

        $insert = @"
        // V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR
        // The RAW NIHAV audit isolated rectangular discontinuities to U/V
        // before SharpEmu color conversion. Repair only those chroma block
        // boundaries; Y remains bit-for-bit untouched.
        BinkChromaRepairV7243227.RepairInPlace(
            planarU,
            planarV,
            chromaWidth,
            chromaHeight,
            _moviePath);

$anchor
"@

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $anchor `
                -New $insert `
                -Label "row-split chroma repair insertion"
    }

    if (-not $d.Contains(
            "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX")) {

        $oldNeutral =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\neutral_v22.old.txt")
        $newNeutral =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\neutral_v27.new.txt")

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $oldNeutral `
                -New $newNeutral `
                -Label "centered chroma neutral gate"
    }

    Write-Normalized `
        -Path $decoder `
        -Text $d `
        -Format $decoderFormat

    # -------------------------------------------------------------
    # 2. Audio bridge: external intro stems, first-frame sync.
    # -------------------------------------------------------------
    $audioFormat = Get-TextFormat -Path $audio
    $a = Read-Normalized -Path $audio

    if (-not $a.Contains(
            "V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO")) {

        $oldStart = @"
        long generation;
        lock (Gate)
        {
            generation = ++_generation;

            // Stop the prior movie audio exactly when the video bridge changes
            // source. This also handles logo_intro -> logo_intro_loop.
            _ = PlaySound(null, IntPtr.Zero, 0);

            if (CachedWavByMovie.TryGetValue(hostPath, out var cached) &&
"@

        $newStart = @"
        // V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO
        //
        // The game eboot starts opening video and music through separate
        // state-machine actions. Demon's Souls resolves its opening music/SFX/
        // VO from external AT9 banks rather than embedded logo_intro audio.
        var v7243227IntroAttach =
            BinkDemonSoulsIntroAudioV7243227.PrepareAttach(hostPath);

        long generation;
        lock (Gate)
        {
            // Always advance the base generation so a late extraction from the
            // previous Bink movie can never overwrite the external timeline.
            generation = ++_generation;

            if (v7243227IntroAttach !=
                BinkDemonSoulsIntroAudioV7243227.AttachDisposition.ContinueTimeline)
            {
                _ = PlaySound(null, IntPtr.Zero, 0);
            }

            if (v7243227IntroAttach !=
                BinkDemonSoulsIntroAudioV7243227.AttachDisposition.NotHandled)
            {
                return;
            }

            if (CachedWavByMovie.TryGetValue(hostPath, out var cached) &&
"@

        $a =
            Replace-ExactOnce `
                -Text $a `
                -Old $oldStart `
                -New $newStart `
                -Label "audio TryStart generation/stop block"

        $notifyAnchor = @"
    public static void NotifyPresentationStarted(string moviePath)
    {
"@

        $notifyNew = @"
    public static void NotifyPresentationStarted(string moviePath)
    {
        // V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO_PRESENT
        // The existing V24 HostMovieBridge hook calls this exactly on the first
        // presented frame. External intro audio therefore shares that same
        // presentation boundary instead of starting at file-open time.
        if (BinkDemonSoulsIntroAudioV7243227.NotifyPresentationStarted(moviePath))
        {
            return;
        }

"@

        $a =
            Replace-ExactOnce `
                -Text $a `
                -Old $notifyAnchor `
                -New $notifyNew `
                -Label "audio first-presented-frame hook"
    }

    Write-Normalized `
        -Path $audio `
        -Text $a `
        -Format $audioFormat

    # -------------------------------------------------------------
    # 3. Runtime defaults: 640x360, 60-frame buffer, no catchup drop.
    # -------------------------------------------------------------
    $bootstrapFormat = Get-TextFormat -Path $bootstrap
    $b = Read-Normalized -Path $bootstrap

    if (-not $b.Contains(
            "V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")) {

        $b =
            Replace-RegexOnce `
                -Text $b `
                -Pattern 'SetDefault\("SHARPEMU_BINK_OUTPUT_MAX_WIDTH",\s*"[0-9]+"\);' `
                -Replacement 'SetDefault("SHARPEMU_BINK_OUTPUT_MAX_WIDTH", "640");' `
                -Label "output width"

        $b =
            Replace-RegexOnce `
                -Text $b `
                -Pattern 'SetDefault\("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT",\s*"[0-9]+"\);' `
                -Replacement 'SetDefault("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT", "360");' `
                -Label "output height"

        $b =
            Replace-RegexOnce `
                -Text $b `
                -Pattern 'SetDefault\("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES",\s*"[0-9]+"\);' `
                -Replacement 'SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES", "60");' `
                -Label "startup prefetch"

        $b =
            Replace-RegexOnce `
                -Text $b `
                -Pattern 'SetDefault\("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS",\s*"[0-9]+"\);' `
                -Replacement 'SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS", "8");' `
                -Label "startup prefetch timeout"

        $b =
            Replace-RegexOnce `
                -Text $b `
                -Pattern 'SetDefault\("SHARPEMU_BINK_MAX_CATCHUP_SKIP",\s*"[0-9]+"\);' `
                -Replacement 'SetDefault("SHARPEMU_BINK_MAX_CATCHUP_SKIP", "0");' `
                -Label "catchup skip default"

        $anchor =
            '        SetDefault("SHARPEMU_BINK_MAX_CATCHUP_SKIP", "0");'

        $insert = @"
$anchor

        // V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES
        //
        // Native/LTO NIHAV measured ~26.2 exported logo frames/s. A 60-frame
        // startup reservoir is enough to absorb the measured 12-second logo
        // deficit while preserving all decoded frames in order.
        //
        // Keep the validated V17 Q14 path active and apply the V27 U/V-only
        // boundary repair before conversion.
        SetDefault("SHARPEMU_BINK_FFMPEG_COLOR", "0");
        SetDefault("SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION", "1");
        SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK", "1");
        SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD", "24");
        SetDefault("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "1");
"@

        $b =
            Replace-ExactOnce `
                -Text $b `
                -Old $anchor `
                -New $insert `
                -Label "V27 runtime defaults"
    }

    Write-Normalized `
        -Path $bootstrap `
        -Text $b `
        -Format $bootstrapFormat

    # -------------------------------------------------------------
    # 4. Install new helper source files.
    # -------------------------------------------------------------
    Copy-Item `
        -LiteralPath $chromaPayload `
        -Destination $chroma `
        -Force

    Copy-Item `
        -LiteralPath $introAudioPayload `
        -Destination $introAudio `
        -Force

    # -------------------------------------------------------------
    # 5. Deploy the user's already benchmarked native/LTO NIHAV build.
    # -------------------------------------------------------------
    $payloadHash =
        (Get-FileHash -LiteralPath $nativePayload -Algorithm SHA256).
        Hash.ToLowerInvariant()

    if ($payloadHash -ne
        "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18") {
        throw "[V72.4.3.2.27] Native NIHAV payload hash mismatch."
    }

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Split-Path -Parent $tool) |
        Out-Null

    Copy-Item `
        -LiteralPath $nativePayload `
        -Destination $tool `
        -Force

    $installedToolHash =
        (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
        Hash.ToLowerInvariant()

    if ($installedToolHash -ne $payloadHash) {
        throw "[V72.4.3.2.27] Installed NIHAV hash mismatch."
    }

    # -------------------------------------------------------------
    # 6. Structural post-apply verification.
    # -------------------------------------------------------------
    $afterD = Read-Normalized -Path $decoder
    $afterA = Read-Normalized -Path $audio
    $afterB = Read-Normalized -Path $bootstrap
    $afterChroma = Read-Normalized -Path $chroma
    $afterIntro = Read-Normalized -Path $introAudio

    foreach ($marker in @(
        "V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP",
        "var maxCatchupSkip = 0;",
        "V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR",
        "BinkChromaRepairV7243227.RepairInPlace(",
        "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX",
        "12044 * cbValue",
        "14647 * crValue",
        "8259 * crValue"
    )) {
        if (-not $afterD.Contains($marker)) {
            throw "[V72.4.3.2.27] Decoder post-apply marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO",
        "V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO_PRESENT",
        "BinkDemonSoulsIntroAudioV7243227.PrepareAttach(hostPath)",
        "BinkDemonSoulsIntroAudioV7243227.NotifyPresentationStarted(moviePath)"
    )) {
        if (-not $afterA.Contains($marker)) {
            throw "[V72.4.3.2.27] Audio post-apply marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES",
        'SetDefault("SHARPEMU_BINK_OUTPUT_MAX_WIDTH", "640");',
        'SetDefault("SHARPEMU_BINK_OUTPUT_MAX_HEIGHT", "360");',
        'SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES", "60");',
        'SetDefault("SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS", "8");',
        'SetDefault("SHARPEMU_BINK_MAX_CATCHUP_SKIP", "0");',
        'SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD", "24");',
        'SetDefault("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "1");'
    )) {
        if (-not $afterB.Contains($marker)) {
            throw "[V72.4.3.2.27] Bootstrap post-apply marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "BinkChromaRepairV7243227",
        "ChromaBlock = 8",
        "Luma is never modified"
    )) {
        if (-not $afterChroma.Contains($marker)) {
            throw "[V72.4.3.2.27] Chroma helper marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "BinkDemonSoulsIntroAudioV7243227",
        "pr_demons_souls_intro_music.at9",
        "pr_demons_souls_intro_sfx.at9",
        "pr_demons_souls_intro_vo.at9",
        "AttractOffsetSeconds = 12.0"
    )) {
        if (-not $afterIntro.Contains($marker)) {
            throw "[V72.4.3.2.27] Intro audio helper marker missing: $marker"
        }
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        Push-Location $root
        try {
            & git.exe diff --check -- `
                $decoderRel `
                $audioRel `
                $bootstrapRel `
                $chromaRel `
                $introAudioRel

            if ($LASTEXITCODE -ne 0) {
                throw "[V72.4.3.2.27] git diff --check failed."
            }
        }
        finally {
            Pop-Location
        }
    }

    if (-not $SkipBuild) {
        Push-Location $root
        try {
            Write-Host "[V72.4.3.2.27] Building SharpEmu.Libs..."
            & dotnet.exe build `
                "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
                -c Debug `
                --nologo

            if ($LASTEXITCODE -ne 0) {
                throw "[V72.4.3.2.27] SharpEmu.Libs build failed."
            }

            Write-Host "[V72.4.3.2.27] Building SharpEmu.CLI win-x64..."
            & dotnet.exe build `
                "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
                -c Debug `
                -r win-x64 `
                --nologo

            if ($LASTEXITCODE -ne 0) {
                throw "[V72.4.3.2.27] SharpEmu.CLI build failed."
            }
        }
        finally {
            Pop-Location
        }
    }

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host (
        "[V72.4.3.2.27] Native NIHAV installed SHA256: " +
        $installedToolHash)
    Write-Host (
        "[V72.4.3.2.27] Backup: " +
        $backup)
    Write-Host (
        "[V72.4.3.2.27] SUCCESS: video buffering + chroma repair + " +
        "centered color gate + external intro audio installed.") `
        -ForegroundColor Green
}
catch {
    foreach ($rel in $backupFiles) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            New-Item `
                -ItemType Directory `
                -Force `
                -Path (Split-Path -Parent $target) |
                Out-Null

            Copy-Item `
                -LiteralPath $saved `
                -Destination $target `
                -Force
        }
    }

    foreach ($rel in @($chromaRel,$introAudioRel)) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item `
                -LiteralPath $saved `
                -Destination $target `
                -Force
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    Write-Host (
        "[V72.4.3.2.27] FAILURE: " +
        $_.Exception.Message) `
        -ForegroundColor Red
    Write-Host (
        "[V72.4.3.2.27] Restored from: " +
        $backup) `
        -ForegroundColor Yellow

    throw
}
