. "$PSScriptRoot\common.ps1"

$repo = Get-RepoRoot
& "$PSScriptRoot\precheck.ps1"

$dll = Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.dll"

if (-not (Test-Path -LiteralPath $dll)) {
    throw "SharpEmu.dll missing. Run RUN_3_APPLY_BUILD.cmd first."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $repo ("SharpEmu_DragonBallFighterZ_ImportLoopUnlockBoundary_V1_7_6_Result_" + $stamp)

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stdout = Join-Path $outDir "dragonball_stdout.log"
$stderr = Join-Path $outDir "dragonball_stderr.log"
$combined = Join-Path $outDir "dragonball_combined.log"
$summaryPath = Join-Path $outDir "SUMMARY.txt"

$env:SHARPEMU_DBFZ_NULL_SHARED_PTR_COMPAT = "1"
$env:SHARPEMU_DBFZ_DERIVED_NULL_CONTAINER_COMPAT = "1"
$env:SHARPEMU_DBFZ_NULL_RESOURCE_FALLBACK = "1"
$env:SHARPEMU_LOG_OPEN = "1"
$env:SHARPEMU_LOG_IO = "0"
$env:SHARPEMU_LOG_AMPR = "0"

# Keep the guard enabled. V1.7.6 is meant to fix false-positive classification,
# not to hide it by disabling the watchdog.
Remove-Item Env:\SHARPEMU_DISABLE_IMPORT_LOOP_GUARD -ErrorAction SilentlyContinue

Write-Host "[DBFZ-ILU-176] Running DBFZ for up to 180 seconds with import-loop guard ENABLED..."

$args = @(
    "`"$dll`"",
    "`"$Script:GamePath`""
)

$process = Start-Process `
    -FilePath "dotnet" `
    -ArgumentList $args `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru `
    -NoNewWindow

$survived = -not $process.WaitForExit(180000)

if ($survived) {
    Write-Host "[DBFZ-ILU-176] Runtime survived 180 seconds; stopping diagnostic process tree."
    & taskkill /PID $process.Id /T /F | Out-Null
    Start-Sleep -Seconds 2
}

$exitCode = $null

try {
    $process.Refresh()
    if ($process.HasExited) {
        $exitCode = $process.ExitCode
    }
}
catch {
    $exitCode = $null
}

$stdoutText = if (Test-Path -LiteralPath $stdout) {
    [System.IO.File]::ReadAllText($stdout)
}
else {
    ""
}

$stderrText = if (Test-Path -LiteralPath $stderr) {
    [System.IO.File]::ReadAllText($stderr)
}
else {
    ""
}

$text = $stdoutText + "`r`n" + $stderrText

[System.IO.File]::WriteAllText(
    $combined,
    $text,
    (Get-Utf8NoBom))

$guardMatches = [regex]::Matches(
    $text,
    'Import-loop guard fired at import#(\d+): nid=([^\s]+) ret=0x([0-9A-Fa-f]+)',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$guardFired = $guardMatches.Count -gt 0
$guardImport = ""
$guardNid = ""
$guardReturn = ""

if ($guardFired) {
    $lastGuard = $guardMatches[$guardMatches.Count - 1]
    $guardImport = $lastGuard.Groups[1].Value
    $guardNid = $lastGuard.Groups[2].Value
    $guardReturn = "0x" + $lastGuard.Groups[3].Value
}

$aprAfter = [regex]::Matches(
    $text,
    'dbfz\.apr_payload after[^\r\n]*',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$lastAprSequence = 0
$pak0Changed = 0
$pak1Changed = 0

foreach ($match in $aprAfter) {
    $line = $match.Value

    $seqMatch = [regex]::Match($line, 'seq=(\d+)')
    if ($seqMatch.Success) {
        $seq = [int]$seqMatch.Groups[1].Value
        if ($seq -gt $lastAprSequence) {
            $lastAprSequence = $seq
        }
    }

    if ($line.IndexOf("changed=True", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        if ($line.IndexOf("pak=0", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $pak0Changed++
        }
        elseif ($line.IndexOf("pak=1", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $pak1Changed++
        }
    }
}

$globalShaderFatal =
    $text.IndexOf("global shader cache file", [System.StringComparison]::OrdinalIgnoreCase) -ge 0

$abortCalled =
    $text.IndexOf("abort() called by guest", [System.StringComparison]::OrdinalIgnoreCase) -ge 0

$nativeException =
    $text.IndexOf("NATIVE EXCEPTION CAUGHT!", [System.StringComparison]::OrdinalIgnoreCase) -ge 0

$forcedLoopUnwind =
    $text.IndexOf("Detected repeating import loop and forced guest unwind to host", [System.StringComparison]::OrdinalIgnoreCase) -ge 0

$lastVeh = ""
$vehMatches = [regex]::Matches(
    $text,
    'VEH_AV first-chance[^\r\n]*',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if ($vehMatches.Count -gt 0) {
    $lastVeh = $vehMatches[$vehMatches.Count - 1].Value
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("Dragon Ball FighterZ Import-Loop Unlock Boundary V1.7.6 Result")

if ($null -eq $exitCode) {
    $summary.Add("ExitCode=<unavailable>")
}
else {
    $summary.Add("ExitCode=" + $exitCode)
}

$summary.Add("RuntimeSurvived180Seconds=" + $survived)
$summary.Add("ImportLoopGuardEnabled=True")
$summary.Add("ImportLoopGuardFired=" + $guardFired)
$summary.Add("ImportLoopGuardImport=" + $guardImport)
$summary.Add("ImportLoopGuardNid=" + $guardNid)
$summary.Add("ImportLoopGuardReturn=" + $guardReturn)
$summary.Add("ForcedLoopUnwind=" + $forcedLoopUnwind)
$summary.Add("LastAprSequence=" + $lastAprSequence)
$summary.Add("Pak0PayloadChangedCount=" + $pak0Changed)
$summary.Add("Pak1PayloadChangedCount=" + $pak1Changed)
$summary.Add("GlobalShaderCacheFatal=" + $globalShaderFatal)
$summary.Add("AbortCalled=" + $abortCalled)
$summary.Add("NativeException=" + $nativeException)
$summary.Add("LastVEH=" + $lastVeh)

[System.IO.File]::WriteAllLines(
    $summaryPath,
    $summary,
    (Get-Utf8NoBom))

foreach ($relative in @(
    $Script:ImportsRelative,
    $Script:TraceRelative,
    $Script:V173Relative)) {

    $source = Join-Path $repo $relative

    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $outDir -Force
    }
}

$diff = & git diff -- `
    "src/SharpEmu.Core/Cpu/Native/DirectExecutionBackend.Imports.cs"

$diff | Set-Content -LiteralPath (Join-Path $outDir "git_diff_dbfz_v1_7_6.txt") -Encoding UTF8

$zip = $outDir + ".zip"

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive `
    -Path (Join-Path $outDir "*") `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[DBFZ-ILU-176] RESULT ZIP: $zip"
Get-Content -LiteralPath $summaryPath
