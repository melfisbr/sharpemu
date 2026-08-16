param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot

$decoderRel =
    "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$decoder = Join-Path $root $decoderRel

$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup =
    Join-Path $root (
        ".sharpemu-hotfix-backup\BinkSpeedRestoreBlockChroma_V72_4_3_2_29_0_2_" +
        $stamp)

$backupDecoder =
    Join-Path $backup $decoderRel

New-Item `
    -ItemType Directory `
    -Force `
    -Path (Split-Path -Parent $backupDecoder) |
    Out-Null

Copy-Item `
    -LiteralPath $decoder `
    -Destination $backupDecoder `
    -Force

try {
    $format = Get-TextFormat -Path $decoder
    $d = Read-Normalized -Path $decoder

    $oldCall =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\v29_chroma7_call.old.txt")
    $newCall =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\block9_call.new.txt")

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old $oldCall `
            -New $newCall `
            -Label "V29 expensive chroma7 call"

    $oldHelper =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\v29_chroma7_helper.old.txt")
    $newHelper =
        Read-Normalized `
            -Path (Join-Path $packageRoot "payload\block9_helper.new.txt")

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old $oldHelper `
            -New $newHelper `
            -Label "V29 expensive chroma7 helper"

    $d =
        Replace-ExactOnce `
            -Text $d `
            -Old "path=exact633-row-split-refcal-neutral-chroma7 luma=center-2x2 chroma=box7x7 " `
            -New "path=exact633-row-split-refcal-neutral-block9 luma=center-2x2 chroma=block9 " `
            -Label "V29 chroma7 runtime log"

    Write-Normalized `
        -Path $decoder `
        -Text $d `
        -Format $format

    $after = Read-Normalized -Path $decoder

    foreach ($marker in @(
        "V72.4.3.2.29.0.2 DIRECT_PACKED_BLOCK9_CHROMA",
        "SampleV7243292PackedChromaBlock9(",
        "path=exact633-row-split-refcal-neutral-block9",
        "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY",
        "TryApplyV724329DedicatedAffinity(process)",
        "V72.4.3.2.29 ATTRACT_FRAME_TRUTH_EXTENDED"
    )) {
        if (-not $after.Contains($marker)) {
            throw "[V72.4.3.2.29.0.2] Post-apply decoder marker missing: $marker"
        }
    }

    if ($after.Contains("SampleV724329PackedChroma7x7(")) {
        throw "[V72.4.3.2.29.0.2] Expensive V29 chroma7 helper still present."
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.29.0.2] Building SharpEmu.Libs..."

        & dotnet.exe build `
            "src\SharpEmu.Libs\SharpEmu.Libs.csproj" `
            -c Debug `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.29.0.2] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.29.0.2] Building SharpEmu.CLI win-x64..."

        & dotnet.exe build `
            "src\SharpEmu.CLI\SharpEmu.CLI.csproj" `
            -c Debug `
            -r win-x64 `
            --nologo

        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.29.0.2] SharpEmu.CLI build failed."
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
        throw "[V72.4.3.2.29.0.2] Native NIHAV did not survive build. SHA256=$finalHash"
    }

    $pointer =
        Join-Path $root (
            ".sharpemu-hotfix-backup\" +
            "BinkSpeedRestoreBlockChroma_V72_4_3_2_29_0_2_LAST.txt")

    [IO.File]::WriteAllText(
        $pointer,
        $backup,
        (New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.29.0.2] FINAL_NIHAV_SHA256=" + $finalHash)
    Write-Host ("[V72.4.3.2.29.0.2] Backup: " + $backup)
    Write-Host (
        "[V72.4.3.2.29.0.2] SUCCESS: expensive chroma7 removed; " +
        "cheap block9 direct chroma installed; dedicated NIHAV affinity preserved.") `
        -ForegroundColor Green
}
catch {
    Copy-Item `
        -LiteralPath $backupDecoder `
        -Destination $decoder `
        -Force

    Write-Host (
        "[V72.4.3.2.29.0.2] FAILURE: " +
        $_.Exception.Message) `
        -ForegroundColor Red
    Write-Host (
        "[V72.4.3.2.29.0.2] Decoder restored from: " +
        $backup) `
        -ForegroundColor Yellow

    throw
}
