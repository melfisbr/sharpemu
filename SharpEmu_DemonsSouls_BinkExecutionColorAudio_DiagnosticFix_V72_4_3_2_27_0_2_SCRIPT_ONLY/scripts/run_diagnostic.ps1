param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# V72.4.3.2.27.0.2 POWERSHELL_5_1_PROCESS_ARGUMENTS_FIX
#
# Windows PowerShell 5.1/.NET Framework does not expose
# ProcessStartInfo.ArgumentList. Use the classic Arguments property instead.

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$exe = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
$tool = Join-Path $root "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

$decoder = Join-Path $root "src\SharpEmu.Libs\Media\NihavBink2Decoder.cs"
$audio = Join-Path $root "src\SharpEmu.Libs\Media\BinkHostAudioBridgeV7241.cs"
$bootstrap = Join-Path $root "src\SharpEmu.Libs\Media\BinkRuntimeBootstrapV6113166.cs"

foreach ($path in @($exe,$tool,$Eboot,$decoder,$audio,$bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "[V72.4.3.2.27.0.2] Diagnostic prerequisite missing: $path"
    }
}

$d = [IO.File]::ReadAllText($decoder)
$a = [IO.File]::ReadAllText($audio)
$b = [IO.File]::ReadAllText($bootstrap)

foreach ($marker in @(
    "V72.4.3.2.27 NO_CLOCK_CATCHUP_DROP",
    "V72.4.3.2.27 CHROMA_DEBLOCK_BEFORE_COLOR",
    "V72.4.3.2.27 CENTERED_CHROMA_NEUTRAL_GATE_FIX"
)) {
    if (-not $d.Contains($marker)) {
        throw "[V72.4.3.2.27.0.2] V27 decoder marker missing: $marker"
    }
}

if (-not $a.Contains("V72.4.3.2.27 DEMONS_SOULS_EXTERNAL_INTRO_AUDIO")) {
    throw "[V72.4.3.2.27.0.2] V27 external intro audio marker missing."
}

if (-not $b.Contains("V72.4.3.2.27 BUFFERED_NATIVE_BOOT_MOVIES")) {
    throw "[V72.4.3.2.27.0.2] V27 buffered runtime marker missing."
}

$expectedHash = "cc911d477e772598f7a5995b6738265fb77bda0061f7a0b8ba79711acf263a18"
$toolHash = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant()
$hashOk = $toolHash -eq $expectedHash

if (-not $hashOk) {
    throw "[V72.4.3.2.27.0.2] Runtime NIHAV hash is not the native V27 build: $toolHash"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_27_0_2_BINK_RESULT_" + $stamp)
$truth = Join-Path $out "frame_truth"
$session = Join-Path $out "bink_session.log"
$stdout = Join-Path $out "stdout.log"
$stderr = Join-Path $out "stderr.log"

New-Item -ItemType Directory -Force -Path $truth | Out-Null

$names = @(
    "SHARPEMU_BINK_OUTPUT_MAX_WIDTH",
    "SHARPEMU_BINK_OUTPUT_MAX_HEIGHT",
    "SHARPEMU_NIHAV_SKIP_MODE",
    "SHARPEMU_BINK_FFMPEG_COLOR",
    "SHARPEMU_NIHAV_UV_SWAP",
    "SHARPEMU_BINK_PACKED_DIRECT",
    "SHARPEMU_BINK_FRAME_TRUTH_DIR",
    "SHARPEMU_BINK_SESSION_LOG",
    "SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION",
    "SHARPEMU_BINK_CHROMA_DEBLOCK",
    "SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD",
    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO",
    "SHARPEMU_LOG_BINK2",
    "SHARPEMU_BINK_HOST_CPU_LOGICAL",
    "SHARPEMU_NIHAV_FAST_PRIORITY",
    "SHARPEMU_BINK_REALTIME_DEADLINE",
    "SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES",
    "SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS",
    "SHARPEMU_BINK_HOST_TAIL_HOLD_MS",
    "SHARPEMU_BINK_MAX_CATCHUP_SKIP",
    "SHARPEMU_NIHAV_STREAM_FULL_CACHE"
)

$previous = @{}

foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable(
        $name,
        [System.EnvironmentVariableTarget]::Process)
}

try {
    $env:SHARPEMU_BINK_OUTPUT_MAX_WIDTH = "640"
    $env:SHARPEMU_BINK_OUTPUT_MAX_HEIGHT = "360"
    $env:SHARPEMU_NIHAV_SKIP_MODE = "none"
    $env:SHARPEMU_BINK_FFMPEG_COLOR = "0"
    $env:SHARPEMU_NIHAV_UV_SWAP = "0"
    $env:SHARPEMU_BINK_PACKED_DIRECT = "1"
    $env:SHARPEMU_BINK_FRAME_TRUTH_DIR = $truth
    $env:SHARPEMU_BINK_SESSION_LOG = $session
    $env:SHARPEMU_BINK_REFERENCE_COLOR_CALIBRATION = "1"
    $env:SHARPEMU_BINK_CHROMA_DEBLOCK = "1"
    $env:SHARPEMU_BINK_CHROMA_DEBLOCK_THRESHOLD = "24"
    $env:SHARPEMU_DS_INTRO_EXTERNAL_AUDIO = "1"
    $env:SHARPEMU_LOG_BINK2 = "1"
    $env:SHARPEMU_BINK_HOST_CPU_LOGICAL = "16"
    $env:SHARPEMU_NIHAV_FAST_PRIORITY = "2"
    $env:SHARPEMU_BINK_REALTIME_DEADLINE = "1"
    $env:SHARPEMU_NIHAV_STREAM_PREFETCH_FRAMES = "60"
    $env:SHARPEMU_NIHAV_STREAM_PREFETCH_TIMEOUT_SECONDS = "8"
    $env:SHARPEMU_BINK_HOST_TAIL_HOLD_MS = "13000"
    $env:SHARPEMU_BINK_MAX_CATCHUP_SKIP = "0"
    $env:SHARPEMU_NIHAV_STREAM_FULL_CACHE = "0"

    Write-Host "[V72.4.3.2.27.0.2] Starting Demon's Souls."
    Write-Host ("[V72.4.3.2.27.0.2] NIHAV SHA256: " + $toolHash)
    Write-Host "[V72.4.3.2.27.0.2] Close SharpEmu normally after checking the boot videos/title."

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = Split-Path -Parent $exe
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # PowerShell 5.1-compatible command line. Eboot paths are quoted so spaces
    # remain one argument. Embedded quote characters are rejected explicitly.
    if ($Eboot.Contains('"')) {
        throw "[V72.4.3.2.27.0.2] Eboot path contains an unsupported quote character."
    }

    $psi.Arguments = '"' + $Eboot + '"'

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $watch = [Diagnostics.Stopwatch]::StartNew()

    if (-not $proc.Start()) {
        throw "[V72.4.3.2.27.0.2] Failed to start SharpEmu."
    }

    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $proc.WaitForExit()
    $watch.Stop()

    $stdoutText = $stdoutTask.Result
    $stderrText = $stderrTask.Result
    $exitCode = $proc.ExitCode

    $proc.Dispose()

    [IO.File]::WriteAllText(
        $stdout,
        $stdoutText,
        (New-Object Text.UTF8Encoding($true)))

    [IO.File]::WriteAllText(
        $stderr,
        $stderrText,
        (New-Object Text.UTF8Encoding($true)))

    $lines = @()
    $lines += ($stderrText -split "`r?`n")
    $lines += ($stdoutText -split "`r?`n")

    $completed = @($lines | Where-Object { $_ -match 'Bink2 bridge completed:' })
    $catchup = @($lines | Where-Object { $_ -match 'bink2\.clock_catchup' })
    $audioStarts = @($lines | Where-Object { $_ -match 'bink2\.ds_intro_audio_start' })
    $audioContinue = @($lines | Where-Object { $_ -match 'bink2\.ds_intro_audio_continue' })
    $audioErrors = @($lines | Where-Object { $_ -match 'bink2\.ds_intro_audio_.*(failed|unavailable|missing)' })
    $deadline = @($lines | Where-Object { $_ -match 'bink2\.realtime_deadline' })
    $perf = @($lines | Where-Object { $_ -match 'bink2\.perf' })
    $unhandled = @($lines | Where-Object { $_ -match 'Unhandled exception' })

    $summary = @(
        "SharpEmu V72.4.3.2.27.0.2 BINK RESULT",
        "======================================",
        ("WALL_SECONDS=" + [Math]::Round($watch.Elapsed.TotalSeconds,2)),
        ("EXIT_CODE=" + $exitCode),
        ("NIHAV_SHA256=" + $toolHash),
        ("NIHAV_RUNTIME_HASH_OK=" + $hashOk),
        "OUTPUT=640x360",
        "PREFETCH_FRAMES=60",
        "PREFETCH_TIMEOUT_SECONDS=8",
        "MAX_CATCHUP_SKIP=0",
        "REFERENCE_COLOR_CALIBRATION=1",
        "CHROMA_DEBLOCK=1",
        "CHROMA_DEBLOCK_THRESHOLD=24",
        "EXTERNAL_INTRO_AUDIO=1",
        ("MOVIES_COMPLETED=" + $completed.Count),
        ("CLOCK_CATCHUP_EVENTS=" + $catchup.Count),
        ("INTRO_AUDIO_STARTS=" + $audioStarts.Count),
        ("INTRO_AUDIO_CONTINUES=" + $audioContinue.Count),
        ("INTRO_AUDIO_ERRORS=" + $audioErrors.Count),
        ("REALTIME_DEADLINES=" + $deadline.Count),
        ("PERF_SAMPLES=" + $perf.Count),
        ("UNHANDLED_EXCEPTIONS=" + $unhandled.Count)
    )

    [IO.File]::WriteAllLines(
        (Join-Path $out "SUMMARY.txt"),
        [string[]]$summary,
        (New-Object Text.UTF8Encoding($true)))

    $relevant = @(
        $lines |
        Where-Object {
            $_ -match 'bink2\.' -or
            $_ -match 'Bink2 bridge' -or
            $_ -match 'Unhandled exception'
        }
    )

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
    Write-Host ("[V72.4.3.2.27.0.2] RESULT ZIP: " + $zip) -ForegroundColor Green
}
finally {
    foreach ($name in $names) {
        $oldValue = $previous[$name]

        if ($null -eq $oldValue) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $null,
                [System.EnvironmentVariableTarget]::Process)
        }
        else {
            [Environment]::SetEnvironmentVariable(
                $name,
                [string]$oldValue,
                [System.EnvironmentVariableTarget]::Process)
        }
    }
}
