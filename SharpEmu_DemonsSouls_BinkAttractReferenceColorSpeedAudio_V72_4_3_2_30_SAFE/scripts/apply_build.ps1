param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot

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

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\BinkAttractReferenceColorSpeedAudio_V72_4_3_2_30_" +
        $stamp)

foreach ($rel in @($decoderRel,$audioRel,$bootstrapRel)) {
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
    # -----------------------------------------------------------
    # 1. Remove V29.0.2 block9 and restore the original 3x3 exact633
    #    chroma sampling cost.
    # -----------------------------------------------------------
    $format = Get-TextFormat -Path $decoder
    $d = Read-Normalized -Path $decoder

    $oldCall =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\block9_call.old.txt")
    $fastCall =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\fast_3x3.new.txt")

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old $oldCall `
            -New $fastCall `
            -Label "V29.0.2 block9 call"

    $oldHelper =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\block9_helper.old.txt")

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old $oldHelper `
            -New "" `
            -Label "V29.0.2 block9 helper"

    # -----------------------------------------------------------
    # 2. Replace the exact633 V17/V21 color body by the V30 movie-
    #    specific branch. Non-attract movies keep existing V17/V27.
    # -----------------------------------------------------------
    $oldColor =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\v21_exact_color.old.txt")
    $newColor =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\v30_exact_color.new.txt")

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old $oldColor `
            -New $newColor `
            -Label "exact633 V17/V21 color block"

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old "path=exact633-row-split-refcal-neutral-block9 luma=center-2x2 chroma=block9 " `
            -New "path=exact633-v30-fast3x3 luma=center-2x2 chroma=box3x3 " `
            -Label "runtime color path log"

    Write-Normalized `
        -Path $decoder `
        -Text $d `
        -Format $format

    # -----------------------------------------------------------
    # 3. Install V30 attract audio helper and change bootstrap default
    #    from 0.9054 to the pacing estimate 0.7000.
    # -----------------------------------------------------------
    Copy-Item `
        -LiteralPath (
            Join-Path $packageRoot "payload\BinkDemonSoulsIntroAudioV7243227.cs") `
        -Destination $audio `
        -Force

    $format = Get-TextFormat -Path $bootstrap
    $b = Read-Normalized -Path $bootstrap

    $oldTempo =
        '        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.9054");'
    $newTempo =
        '        // V72.4.3.2.30 ATTRACT_AUDIO_PACING_ESTIMATE' + "`n" +
        '        SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.7000");'

    if ($b.Contains($oldTempo)) {
        $b =
            Replace-ExactOnce `
                -Text $b `
                -Old $oldTempo `
                -New $newTempo `
                -Label "attract audio tempo"
    }
    elseif (-not $b.Contains(
        'SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.7000");')) {
        throw "[V72.4.3.2.30] Attract audio tempo default anchor missing."
    }

    Write-Normalized `
        -Path $bootstrap `
        -Text $b `
        -Format $format

    # -----------------------------------------------------------
    # 4. Post-apply structural verification.
    # -----------------------------------------------------------
    $afterD = Read-Normalized -Path $decoder
    $afterA = Read-Normalized -Path $audio
    $afterB = Read-Normalized -Path $bootstrap

    foreach ($marker in @(
        "V72.4.3.2.30 ATTRACT_REFERENCE_112_COLOR_Q14",
        "20573 * yy",
        "10379 * cbValue",
        "13999 * crValue",
        "path=exact633-v30-fast3x3",
        "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY",
        "TryApplyV724329DedicatedAffinity(process)",
        "V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED"
    )) {
        if (-not $afterD.Contains($marker)) {
            throw "[V72.4.3.2.30] Decoder post-apply marker missing: $marker"
        }
    }

    foreach ($forbidden in @(
        "SampleV7243292PackedChromaBlock9(",
        "SampleV724329PackedChroma7x7("
    )) {
        if ($afterD.Contains($forbidden)) {
            throw "[V72.4.3.2.30] Expensive chroma helper still present: $forbidden"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.30 ATTRACT_PRESENTATION_RATE_AUDIO",
        "return 0.7000;",
        "from12-v30-"
    )) {
        if (-not $afterA.Contains($marker)) {
            throw "[V72.4.3.2.30] Audio post-apply marker missing: $marker"
        }
    }

    if (-not $afterB.Contains(
        'SetDefault("SHARPEMU_DS_ATTRACT_AUDIO_TEMPO", "0.7000");')) {
        throw "[V72.4.3.2.30] Bootstrap audio tempo 0.7000 missing."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.30] Building SharpEmu.Libs..."

        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.30] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.30] Building SharpEmu.CLI win-x64..."

        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.30] SharpEmu.CLI build failed."
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
        throw "[V72.4.3.2.30] Native NIHAV did not survive build. SHA256=$finalHash"
    }

    $pointer =
        Join-Path $root (
            ".sharpemu-hotfix-backup\" +
            "BinkAttractReferenceColorSpeedAudio_V72_4_3_2_30_LAST.txt")

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.30] FINAL_NIHAV_SHA256=" + $finalHash)
    Write-Host ("[V72.4.3.2.30] Backup: " + $backup)
    Write-Host (
        "[V72.4.3.2.30] SUCCESS: fast 3x3 restored + " +
        "attract reference color matrix + audio tempo 0.7000 installed.") `
        -ForegroundColor Green
}
catch {
    foreach ($rel in @($decoderRel,$audioRel,$bootstrapRel)) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
    }

    Write-Host ("[V72.4.3.2.30] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.30] Restored from: " + $backup) -ForegroundColor Yellow
    throw
}
