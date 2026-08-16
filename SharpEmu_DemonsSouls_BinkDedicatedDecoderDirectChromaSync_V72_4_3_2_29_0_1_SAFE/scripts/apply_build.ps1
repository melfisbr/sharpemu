param(
    [string]$RepositoryRoot=(Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$root =
    Resolve-RepoRoot -RepositoryRoot $RepositoryRoot

& "$PSScriptRoot\precheck.ps1" `
    -RepositoryRoot $root

$packageRoot =
    Split-Path -Parent $PSScriptRoot

$decoderRel =
    "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audioRel =
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$bootstrapRel =
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"

$decoder = Join-Path $root $decoderRel
$audio = Join-Path $root $audioRel
$bootstrap = Join-Path $root $bootstrapRel

$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

$stamp =
    Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\BinkDedicatedDecoderDirectChroma_V72_4_3_2_29_" +
        $stamp)

foreach ($rel in @(
    $decoderRel,
    $audioRel,
    $bootstrapRel
)) {
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

try {
    # ---------------------------------------------------------------
    # Decoder / exact633 direct packed colour path.
    # ---------------------------------------------------------------
    $format =
        Get-TextFormat -Path $decoder
    $d =
        Read-Normalized -Path $decoder

    if (-not $d.Contains(
            "V72.4.3.2.29 DIRECT_PACKED_CHROMA_SMOOTH")) {

        $oldChroma =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\exact633_chroma.old.txt")
        $newChroma =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\exact633_chroma.new.txt")

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $oldChroma `
                -New $newChroma `
                -Label "exact633 direct packed 3x3 chroma"

        $helperAnchor =
            "    private static void TryDumpV7243213PackedFrameTruth("

        $directHelper =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\direct_chroma_helper.cs.txt")

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $helperAnchor `
                -New ($directHelper + $helperAnchor) `
                -Label "direct packed chroma helper insertion"

        $oldLog =
            "path=exact633-row-split-refcal-neutral luma=center-2x2 chroma=box3x3 "
        $newLog =
            "path=exact633-row-split-refcal-neutral-chroma7 luma=center-2x2 chroma=box7x7 "

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $oldLog `
                -New $newLog `
                -Label "exact633 runtime path log"
    }

    # ---------------------------------------------------------------
    # Decoder child affinity: dedicate the top system logical CPUs to
    # external NihAV, outside SharpEmu's lower-CPU movie affinity mask.
    # ---------------------------------------------------------------
    if (-not $d.Contains(
            "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY")) {

        $streamAnchor = @'
        catch (InvalidOperationException)
        {
        }

        _streamProcess = process;
'@

        $streamReplacement = @'
        catch (InvalidOperationException)
        {
        }

        // V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY_APPLY
        TryApplyV724329DedicatedAffinity(process);

        _streamProcess = process;
'@

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $streamAnchor `
                -New $streamReplacement `
                -Label "stream process affinity application"

        $waitAnchor =
            "    // [V70.8.0.1][STREAM_FULL_CACHE]"

        $affinityHelper =
            Read-Normalized `
                -Path (Join-Path $packageRoot "payload\dedicated_affinity_helper.cs.txt")

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $waitAnchor `
                -New ($affinityHelper + $waitAnchor) `
                -Label "dedicated NIHAV affinity helper insertion"
    }

    # Capture frames well inside the attract movie in the next result.
    if (-not $d.Contains(
            "V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED")) {

        $truthOld = @'
        if (serial == 30 ||
            serial == 120 ||
            serial == 240 ||
            serial == 360 ||
            serial == 600 ||
            serial == 720)
'@

        $truthNew = @'
        // V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED
        if (serial == 30 ||
            serial == 120 ||
            serial == 240 ||
            serial == 360 ||
            serial == 600 ||
            serial == 720 ||
            serial == 840 ||
            serial == 1200 ||
            serial == 1800 ||
            serial == 2400 ||
            serial == 3000 ||
            serial == 3600 ||
            serial == 4080)
'@

        $d =
            Replace-ExactOnce `
                -Text $d `
                -Old $truthOld `
                -New $truthNew `
                -Label "extended attract frame truth"
    }

    Write-Normalized `
        -Path $decoder `
        -Text $d `
        -Format $format

    # ---------------------------------------------------------------
    # Audio: install V29 rate-compensated attract tail.
    # ---------------------------------------------------------------
    Copy-Item `
        -LiteralPath (
            Join-Path $packageRoot "payload\BinkDemonSoulsIntroAudioV7243227.cs") `
        -Destination $audio `
        -Force

    # ---------------------------------------------------------------
    # Bootstrap defaults.
    # ---------------------------------------------------------------
    $format =
        Get-TextFormat -Path $bootstrap
    $b =
        Read-Normalized -Path $bootstrap

    if (-not $b.Contains(
            "V72.4.3.2.29 DEDICATED_DECODER_RUNTIME_DEFAULTS")) {

        $anchor =
            '        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");'

        $insert = @'
        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");

        // V72.4.3.2.29 DEDICATED_DECODER_RUNTIME_DEFAULTS
        SetDefault("SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT", "2");
        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.9054");
        SetDefault("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS", "1500");
'@

        $b =
            Replace-ExactOnce `
                -Text $b `
                -Old $anchor `
                -New $insert `
                -Label "V29 runtime defaults"
    }

    Write-Normalized `
        -Path $bootstrap `
        -Text $b `
        -Format $format

    # ---------------------------------------------------------------
    # Structural verification.
    # ---------------------------------------------------------------
    $afterD =
        Read-Normalized -Path $decoder
    $afterA =
        Read-Normalized -Path $audio
    $afterB =
        Read-Normalized -Path $bootstrap

    foreach ($marker in @(
        "V72.4.3.2.29 DIRECT_PACKED_CHROMA_SMOOTH",
        "SampleV724329PackedChroma7x7(",
        "path=exact633-row-split-refcal-neutral-chroma7",
        "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY",
        "TryApplyV724329DedicatedAffinity(process)",
        "bink2.nihav_dedicated_affinity",
        "V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED"
    )) {
        if (-not $afterD.Contains($marker)) {
            throw "[V72.4.3.2.29.0.1] Decoder post-apply marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.29 ATTRACT_DECODER_RATE_AUDIO",
        "ResolveV724329AttractTempo",
        "atempo="
    )) {
        if (-not $afterA.Contains($marker)) {
            throw "[V72.4.3.2.29.0.1] Audio post-apply marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.29 DEDICATED_DECODER_RUNTIME_DEFAULTS",
        'SetDefault("SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT", "2");',
        'SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.9054");',
        'SetDefault("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS", "1500");'
    )) {
        if (-not $afterB.Contains($marker)) {
            throw "[V72.4.3.2.29.0.1] Bootstrap post-apply marker missing: $marker"
        }
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.29.0.1] Building SharpEmu.Libs..."

        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.29.0.1] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.29.0.1] Building SharpEmu.CLI win-x64..."

        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.29.0.1] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $expectedHash =
        "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
    $finalHash =
        (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
        Hash.ToLowerInvariant()

    if ($finalHash -ne $expectedHash) {
        throw (
            "[V72.4.3.2.29.0.1] Native NIHAV did not survive build. SHA256=" +
            $finalHash)
    }

    $pointer =
        Join-Path $root (
            ".sharpemu-hotfix-backup\" +
            "BinkDedicatedDecoderDirectChroma_V72_4_3_2_29_LAST.txt")

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host (
        "[V72.4.3.2.29.0.1] FINAL_NIHAV_SHA256=" +
        $finalHash)
    Write-Host (
        "[V72.4.3.2.29.0.1] Backup: " +
        $backup)
    Write-Host (
        "[V72.4.3.2.29.0.1] SUCCESS: dedicated decoder affinity + " +
        "direct packed chroma smoothing + attract audio rate compensation installed.") `
        -ForegroundColor Green
}
catch {
    foreach ($rel in @(
        $decoderRel,
        $audioRel,
        $bootstrapRel
    )) {
        $saved =
            Join-Path $backup $rel
        $target =
            Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item `
                -LiteralPath $saved `
                -Destination $target `
                -Force
        }
    }

    Write-Host (
        "[V72.4.3.2.29.0.1] FAILURE: " +
        $_.Exception.Message) `
        -ForegroundColor Red
    Write-Host (
        "[V72.4.3.2.29.0.1] Restored from: " +
        $backup) `
        -ForegroundColor Yellow

    throw
}
