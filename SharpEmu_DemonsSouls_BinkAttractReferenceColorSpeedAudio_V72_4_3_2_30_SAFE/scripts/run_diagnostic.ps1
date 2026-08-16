param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$exe =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
$tool =
    Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"
$decoder =
    Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"

foreach ($path in @($exe,$tool,$decoder,$Eboot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.30] Diagnostic prerequisite missing: $path"
    }
}

$d = [IO.File]::ReadAllText($decoder)

foreach ($marker in @(
    "V72.4.3.2.30 ATTRACT_REFERENCE_112_COLOR_Q14",
    "path=exact633-v30-fast3x3",
    "V72.4.3.2.29 NIHAV_DEDICATED_CPU_AFFINITY"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.30] Runtime source marker missing: $marker"
    }
}

$expectedHash =
    "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
$toolHash =
    (Get-FileHash -LiteralPath $tool -Algorithm SHA256).
    Hash.ToLowerInvariant()

if ($toolHash -ne $expectedHash) {
    throw "[V72.4.3.2.30] Runtime NIHAV hash mismatch: $toolHash"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out =
    Join-Path $root (
        "SharpEmu_V72_4_3_2_30_BINK_RESULT_" +
        $stamp)
$truth = Join-Path $out "frame_truth"
$session = Join-Path $out "bink_session.log"
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"

New-Item -ItemType Directory -Force -Path $truth | Out-Null

$names = @(
    "SHARPEMU_BINK_FRAME_TRUTH_DIR",
    "SHARPEMU_BINK_SESSION_LOG",
    "SHARPEMU_LOG_BINK2",
    "SHARPEMU_NIHAV_FAST_PRIORITY",
    "SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT",
    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS"
)

$previous = @{}
foreach ($name in $names) {
    $previous[$name] =
        [Environment]::GetEnvironmentVariable(
            $name,
            [System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_FRAME_TRUTH_DIR = $truth
    $env:SHARPEMU_BINK_SESSION_LOG = $session
    $env:SHARPEMU_LOG_BINK2 = "1"
    $env:SHARPEMU_NIHAV_FAST_PRIORITY = "3"
    $env:SHARPEMU_NIHAV_DEDICATED_LOGICAL_COUNT = "2"
    $env:SHARPEMU_DS_ATTRACT_AUDIO_TEMPO = "0.7000"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"

    Write-Host "[V72.4.3.2.30] Starting Demon's Souls."
    Write-Host "[V72.4.3.2.30] Fast 3x3 restored; attract uses reference-112 matrix."
    Write-Host "[V72.4.3.2.30] Attract audio tempo: 0.7000."
    Write-Host "[V72.4.3.2.30] Close SharpEmu normally after attract/title check."

    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.30] Unsupported quote in Eboot path."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '"' + $Eboot + '"'
    $psi.WorkingDirectory = Split-Path -Parent $exe
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $watch = [Diagnostics.Stopwatch]::StartNew()

    if (-not $proc.Start()) {
        throw "[V72.4.3.2.30] Failed to start SharpEmu."
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $proc.WaitForExit()
    $watch.Stop()

    $outText = $outTask.Result
    $errText = $errTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    [IO.File]::WriteAllText(
        $stdout,$outText,(New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText(
        $stderr,$errText,(New-Object Text.UTF8Encoding($true)))

    $lines = @()
    $lines += ($errText -split "`r?`n")
    $lines += ($outText -split "`r?`n")

    $completed =
        @($lines | Where-Object { $_ -match 'Bink2 bridge completed:' })
    $fast3 =
        @($lines | Where-Object { $_ -match 'path=exact633-v30-fast3x3' })
    $affinity =
        @($lines | Where-Object { $_ -match 'bink2\.nihav_dedicated_affinity ' })
    $unhandled =
        @($lines | Where-Object { $_ -match 'Unhandled exception' })
    $perf =
        @($lines | Where-Object { $_ -match 'bink2\.perf' })

    $summary = @(
        "SharpEmu V72.4.3.2.30 BINK RESULT",
        "=================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        ("NIHAV_SHA256=" + $toolHash),
        ("MOVIES_COMPLETED=" + $completed.Count),
        ("V30_FAST3X3_ACTIVE=" + ($fast3.Count -gt 0)),
        ("NIHAV_DEDICATED_AFFINITY_EVENTS=" + $affinity.Count),
        ("PERF_SAMPLES=" + $perf.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count),
        "ATTRACT_AUDIO_TEMPO=0.7000",
        "ATTRACT_REFERENCE_COLOR=REF112_Q14"
    )

    [IO.File]::WriteAllLines(
        (Join-Path $out "SUMMARY.txt"),
        [string[]]$summary,
        (New-Object Text.UTF8Encoding($true)))

    $relevant =
        @($lines | Where-Object {
            $_ -match 'bink2\.' -or
            $_ -match 'Bink2 bridge' -or
            $_ -match 'Unhandled exception'
        })

    [IO.File]::WriteAllLines(
        (Join-Path $out "BINK_RELEVANT.log"),
        [string[]]$relevant,
        (New-Object Text.UTF8Encoding($true)))

    $zip = $out + ".zip"
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
    }

    Compress-Archive `
        -LiteralPath $out `
        -DestinationPath $zip `
        -CompressionLevel Optimal

    Write-Host ""
    Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
    Write-Host ""
    Write-Host ("[V72.4.3.2.30] RESULT ZIP: " + $zip) -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        $oldValue = $previous[$name]

        [Environment]::SetEnvironmentVariable(
            $name,
            $oldValue,
            [System.EnvironmentVariableTarget]::Process)
    }
}
