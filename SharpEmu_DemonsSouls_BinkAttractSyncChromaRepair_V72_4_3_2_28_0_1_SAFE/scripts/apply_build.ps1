param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& "$PSScriptRoot\precheck.ps1" -RepositoryRoot $root

$packageRoot = Split-Path -Parent $PSScriptRoot

$hostBridgePath = Join-Path $root "src\SharpEmu.Libs\Media\HostMovieBridge.cs"
$bootstrap = Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"
$chroma = Join-Path $root "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs"
$audio = Join-Path $root "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
$tool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root (".sharpemu-hotfix-backup\BinkAttractSyncChroma_V72_4_3_2_28_" + $stamp)

$files = @(
    "src\SharpEmu.Libs\Media\HostMovieBridge.cs",
    "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs",
    "src\SharpEmu.Libs\Media\BinkChromaRepairV7243227.cs",
    "src\SharpEmu.Libs\Media\BinkDemonSoulsIntroAudioV7243227.cs"
)

foreach ($rel in $files) {
    $source = Join-Path $root $rel
    $dest = Join-Path $backup $rel

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

try {
    $format = Get-TextFormat -Path $hostBridgePath
    $h = Read-Normalized -Path $hostBridgePath

    if (-not $h.Contains("V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION")) {
        $anchor = @'
        var autoPaths = orderedBootMovieNames
            .Select(name => Path.Combine(movieRoot, name))
            .Where(File.Exists)
            .Where(static path => TryReadBinkInfo(path, out _))
            .ToArray();
'@

        $insert = @'
        var autoPaths = orderedBootMovieNames
            .Select(name => Path.Combine(movieRoot, name))
            .Where(File.Exists)
            .Where(static path => TryReadBinkInfo(path, out _))
            .ToArray();

        // V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION
        // V27 completed only ps_studios_logo + logo_intro while the external
        // opening timeline continued. Inject attract only for audited Demon's
        // Souls installs and remove the finite title loop from host fallback.
        if (app0.Contains(
                "PPSA01341",
                StringComparison.OrdinalIgnoreCase) ||
            app0.Contains(
                "PPSA25646",
                StringComparison.OrdinalIgnoreCase))
        {
            var attractPath =
                Path.Combine(movieRoot, "attract_movie.bk2");

            if (File.Exists(attractPath) &&
                TryReadBinkInfo(attractPath, out _))
            {
                autoPaths = autoPaths
                    .Where(
                        static path =>
                            !Path.GetFileName(path).Equals(
                                "logo_intro_loop.bk2",
                                StringComparison.OrdinalIgnoreCase) &&
                            !Path.GetFileName(path).Equals(
                                "attract_movie.bk2",
                                StringComparison.OrdinalIgnoreCase))
                    .Concat(new[] { attractPath })
                    .ToArray();

                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.ds_boot_attract_injected " +
                    $"sequence='{string.Join(" -> ", autoPaths.Select(Path.GetFileName))}'");
            }
        }
'@

        $h = Replace-ExactOnce -Text $h -Old $anchor -New $insert -Label "autoPaths construction"
    }

    Write-Normalized -Path $hostBridgePath -Text $h -Format $format

    $format = Get-TextFormat -Path $bootstrap
    $b = Read-Normalized -Path $bootstrap

    if (-not $b.Contains("V72.4.3.2.28 NIHAV_HIGH_PRIORITY")) {
        $oldPriority = '        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "2");'
        $newPriority =
            '        // V72.4.3.2.28 NIHAV_HIGH_PRIORITY' + "`n" +
            '        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");'

        if ($b.Contains($oldPriority)) {
            $b = Replace-ExactOnce -Text $b -Old $oldPriority -New $newPriority -Label "NIHAV priority"
        }
        elseif ($b.Contains('        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");')) {
            $b = $b.Replace(
                '        SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");',
                $newPriority)
        }
        else {
            throw "[V72.4.3.2.28.0.1] NIHAV priority anchor missing."
        }

        $oldBias = '        SetDefault("SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD", "24");'
        $newBias = $oldBias + "`n" +
            '        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_BIAS_THRESHOLD", "4");' + "`n" +
            '        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_NEIGHBOUR_SPREAD", "12");' + "`n" +
            '        SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_BIAS_STRENGTH", "75");'

        if ($b.Contains($oldBias)) {
            $b = Replace-ExactOnce -Text $b -Old $oldBias -New $newBias -Label "chroma bias defaults"
        }
    }

    Write-Normalized -Path $bootstrap -Text $b -Format $format

    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\BinkChromaRepairV7243227.cs") `
        -Destination $chroma `
        -Force

    Copy-Item `
        -LiteralPath (Join-Path $packageRoot "payload\BinkDemonSoulsIntroAudioV7243227.cs") `
        -Destination $audio `
        -Force

    $afterH = Read-Normalized -Path $hostBridgePath
    $afterB = Read-Normalized -Path $bootstrap
    $afterC = Read-Normalized -Path $chroma
    $afterA = Read-Normalized -Path $audio

    foreach ($marker in @(
        "V72.4.3.2.28 DEMONS_SOULS_ATTRACT_BOOT_CONTINUATION",
        "bink2.ds_boot_attract_injected"
    )) {
        if (-not $afterH.Contains($marker)) {
            throw "[V72.4.3.2.28.0.1] Host marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.28 NIHAV_HIGH_PRIORITY",
        'SetDefault("SHARPEMU_NIHAV_FAST_PRIORITY", "3");',
        'SetDefault("SHARPEMU_BINK_CHROMA_BLOCK_BIAS_THRESHOLD", "4");'
    )) {
        if (-not $afterB.Contains($marker)) {
            throw "[V72.4.3.2.28.0.1] Bootstrap marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "V72.4.3.2.28",
        "RepairBlockBias(",
        "DefaultBiasStrengthPercent = 75"
    )) {
        if (-not $afterC.Contains($marker)) {
            throw "[V72.4.3.2.28.0.1] Chroma marker missing: $marker"
        }
    }

    foreach ($marker in @(
        "ATTRACT_AUDIO_RESYNC",
        "LOGO_AUDIO_SEGMENT_LIMIT",
        "bink2.ds_intro_audio_logo_segment_stop"
    )) {
        if (-not $afterA.Contains($marker)) {
            throw "[V72.4.3.2.28.0.1] Audio marker missing: $marker"
        }
    }

    Push-Location $root
    try {
        Write-Host "[V72.4.3.2.28.0.1] Building SharpEmu.Libs..."
        & dotnet.exe build "src\SharpEmu.Libs\SharpEmu.Libs.csproj" -c Debug --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.28.0.1] SharpEmu.Libs build failed."
        }

        Write-Host "[V72.4.3.2.28.0.1] Building SharpEmu.CLI win-x64..."
        & dotnet.exe build "src\SharpEmu.CLI\SharpEmu.CLI.csproj" -c Debug -r win-x64 --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "[V72.4.3.2.28.0.1] SharpEmu.CLI build failed."
        }
    }
    finally {
        Pop-Location
    }

    $expectedHash = "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
    $finalHash = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($finalHash -ne $expectedHash) {
        throw "[V72.4.3.2.28.0.1] Native NIHAV did not survive build. SHA256=$finalHash"
    }

    $pointer = Join-Path $root ".sharpemu-hotfix-backup\BinkAttractSyncChroma_V72_4_3_2_28_LAST.txt"
    [IO.File]::WriteAllText($pointer,$backup,(New-Object Text.UTF8Encoding($false)))

    Write-Host ("[V72.4.3.2.28.0.1] FINAL_NIHAV_SHA256=" + $finalHash)
    Write-Host ("[V72.4.3.2.28.0.1] Backup: " + $backup)
    Write-Host "[V72.4.3.2.28.0.1] SUCCESS: attract continuation + audio resync + block-wide chroma repair installed." -ForegroundColor Green
}
catch {
    foreach ($rel in $files) {
        $saved = Join-Path $backup $rel
        $target = Join-Path $root $rel

        if (Test-Path -LiteralPath $saved -PathType Leaf) {
            Copy-Item -LiteralPath $saved -Destination $target -Force
        }
    }

    Write-Host ("[V72.4.3.2.28.0.1] FAILURE: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("[V72.4.3.2.28.0.1] Restored from: " + $backup) -ForegroundColor Yellow
    throw
}
