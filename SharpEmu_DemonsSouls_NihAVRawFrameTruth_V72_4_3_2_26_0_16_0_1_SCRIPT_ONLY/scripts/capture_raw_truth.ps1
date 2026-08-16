param(
    [string]$RepositoryRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# V72.4.3.2.26.0.16 NIHAV_RAW_FRAME_TRUTH
# V72.4.3.2.26.0.16.0.1 VALIDATOR_DYNAMIC_OUTPUT_FIX
# SCRIPT ONLY. No SharpEmu process, no source changes, no build.

$repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$game = "F:\JOGOSPS5\PPSA01341"
$tool = Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\nihav-tool.exe"

if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){
    throw "[NIHAV-RAW] nihav-tool missing: $tool"
}

$tests = @(
    [pscustomobject]@{
        Name = "logo_intro_t4"
        Movie = (Join-Path $game "movies\logo_intro.bk2")
        Seek = "00:00:03.800"
        EndTime = "00:00:04.300"
    },
    [pscustomobject]@{
        Name = "attract_t30"
        Movie = (Join-Path $game "movies\attract_movie.bk2")
        Seek = "00:00:29.800"
        EndTime = "00:00:30.300"
    }
)

foreach($test in $tests){
    if(-not(Test-Path -LiteralPath $test.Movie -PathType Leaf)){
        throw "[NIHAV-RAW] Movie missing: $($test.Movie)"
    }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$result = Join-Path $repo ("SharpEmu_NIHAV_RAW_FRAME_TRUTH_" + $stamp)
$tempRoot = Join-Path $result "_temp"
New-Item -ItemType Directory -Force -Path $result | Out-Null
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$utf8 = New-Object Text.UTF8Encoding($true)
$summary = @(
    "SharpEmu NIHAV RAW FRAME TRUTH",
    "================================",
    "SOURCE_CHANGE=NONE",
    "BUILD=NONE",
    "SHARPEMU_PROCESS=NONE",
    "VULKAN=NONE",
    ("TOOL_SHA256=" + (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash),
    ""
)

function Read-PgmHeader {
    param([string]$Path)

    $stream = New-Object IO.FileStream(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite)

    try{
        $buf = New-Object byte[] 256
        $got = $stream.Read($buf,0,$buf.Length)
        if($got -le 0){
            return ""
        }

        $text = [Text.Encoding]::ASCII.GetString($buf,0,$got)
        $parts = $text -split '\s+'

        if($parts.Count -ge 4){
            return ($parts[0] + " " + $parts[1] + " " + $parts[2] + " " + $parts[3])
        }

        return $text
    }
    finally{
        $stream.Dispose()
    }
}

foreach($test in $tests){
    Write-Host ""
    Write-Host (
        "[NIHAV-RAW] Capturing " +
        $test.Name +
        " seek=" +
        $test.Seek +
        " end=" +
        $test.EndTime) -ForegroundColor Yellow

    $runDir = Join-Path $tempRoot $test.Name
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $prefix = Join-Path $runDir "frame_"

    $stdout = Join-Path $result ($test.Name + "_stdout.txt")
    $stderr = Join-Path $result ($test.Name + "_stderr.txt")

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $tool
    $psi.WorkingDirectory = Split-Path -Parent $tool
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments =
        '-an -nm=frmpts -vpfx "' +
        $prefix.Replace('"','\"') +
        '" -ignerr -seek ' +
        $test.Seek +
        ' "' +
        $test.Movie.Replace('"','\"') +
        '" ' +
        $test.EndTime

    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $psi
    $watch = [Diagnostics.Stopwatch]::StartNew()

    if(-not $proc.Start()){
        throw "[NIHAV-RAW] Failed to start NihAV."
    }

    try{
        $proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::High
    }
    catch{
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $proc.WaitForExit()
    $watch.Stop()

    $outText = $outTask.Result
    $errText = $errTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    [IO.File]::WriteAllText($stdout,$outText,$utf8)
    [IO.File]::WriteAllText($stderr,$errText,$utf8)

    $frames = @(
        Get-ChildItem `
            -LiteralPath $runDir `
            -Filter *.pgm `
            -File `
            -ErrorAction SilentlyContinue |
        Sort-Object Name
    )

    if($frames.Count -eq 0){
        throw "[NIHAV-RAW] No PGM frames produced for $($test.Name)."
    }

    # Keep a representative middle frame from the short seek window.
    $selectedIndex = [int][Math]::Floor(($frames.Count - 1) / 2.0)
    $selected = $frames[$selectedIndex]
    $saved = Join-Path $result ($test.Name + "_RAW.pgm")
    Copy-Item -LiteralPath $selected.FullName -Destination $saved -Force

    $file = Get-Item -LiteralPath $saved
    $hash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
    $header = Read-PgmHeader -Path $saved

    $summary += ("TEST=" + $test.Name)
    $summary += ("MOVIE=" + $test.Movie)
    $summary += ("SEEK=" + $test.Seek)
    $summary += ("ENDTIME=" + $test.EndTime)
    $summary += ("GENERATED_FRAMES=" + $frames.Count)
    $summary += ("SELECTED_SOURCE_NAME=" + $selected.Name)
    $summary += ("RAW_FILE=" + $saved)
    $summary += ("RAW_BYTES=" + $file.Length)
    $summary += ("RAW_SHA256=" + $hash)
    $summary += ("PGM_HEADER=" + $header)
    $summary += ("WALL_SECONDS=" + $watch.Elapsed.TotalSeconds.ToString("F3",[Globalization.CultureInfo]::InvariantCulture))
    $summary += ("EXIT_CODE=" + $exitCode)
    $summary += ""

    Write-Host (
        "[NIHAV-RAW] saved=" +
        [IO.Path]::GetFileName($saved) +
        " bytes=" +
        $file.Length +
        " header='" +
        $header +
        "'")
}

if(Test-Path -LiteralPath $tempRoot){
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

$summary += "INTERPRETATION:"
$summary += "These PGM files are direct NihAV decoded-frame output before SharpEmu reads, repacks, color-converts, scales, or presents them."
$summary += "If block artifacts already exist in these raw planes, the decoder is responsible."
$summary += "If the raw planes are clean but SharpEmu frame truth is corrupted, the SharpEmu PGMYUV/repack/color path is responsible."

$summaryPath = Join-Path $result "SUMMARY.txt"
[IO.File]::WriteAllLines($summaryPath,[string[]]$summary,$utf8)

Write-Host ""
Write-Host "[NIHAV-RAW] SUMMARY:" -ForegroundColor Cyan
Get-Content -LiteralPath $summaryPath

$zip = $result + ".zip"
if(Test-Path -LiteralPath $zip){
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive `
    -LiteralPath $result `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host ""
Write-Host ("[NIHAV-RAW] RESULT ZIP: " + $zip) -ForegroundColor Green
Write-Host "[NIHAV-RAW] No SharpEmu/NihAV source was modified."
