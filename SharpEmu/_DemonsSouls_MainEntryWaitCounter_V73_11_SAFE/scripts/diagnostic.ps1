param(
    [string]$RepositoryRoot,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$direct = Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$sampler = Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
if (Test-ContainsOrdinal -Text ([IO.File]::ReadAllText($direct)) -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE') {
    throw '[V73.11] Diagnostic refused: V73.10 usleep preference is still installed.'
}
if (-not (Test-ContainsOrdinal -Text ([IO.File]::ReadAllText($sampler)) -Pattern 'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT')) {
    throw '[V73.11] Diagnostic refused: entry-thread probe is not installed.'
}

if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw ('[V73.11] EBOOT missing: {0}' -f $Eboot)
}
$expectedEboot = '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$actualEboot = (Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if ($actualEboot -ne $expectedEboot) {
    throw ('[V73.11] Wrong EBOOT. expected={0} actual={1}' -f $expectedEboot,$actualEboot)
}

$exe = $null
foreach ($candidate in @(
    (Join-Path $root 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $root 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $exe = $candidate
        break
    }
}
if ($null -eq $exe) {
    throw '[V73.11] SharpEmu.exe not found.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ('SharpEmu_V73_11_MAIN_ENTRY_WAIT_RESULT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout = Join-Path $out 'demons_stdout.log'
$stderr = Join-Path $out 'demons_stderr.log'

$vars = @(
    'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_PROFILE_GUEST_RIP',
    'SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS',
    'SHARPEMU_PROFILE_GUEST_RIP_REPORT_S',
    'SHARPEMU_LOG_VIDEOOUT_FPS',
    'SHARPEMU_AUTO_OPTIONS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_LOG_USLEEP',
    'SHARPEMU_LOG_GUEST_THREADS',
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    'SHARPEMU_LOG_IO',
    'SHARPEMU_LOG_AMPR_READS',
    'SHARPEMU_LOG_AGC',
    'SHARPEMU_LOG_AGC_SHADER',
    'SHARPEMU_LOG_VK_RESOURCES',
    'SHARPEMU_TRACE_DRAWS',
    'SHARPEMU_TRACE_FRAME_PACKETS',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old = @{}
foreach ($v in $vars) {
    $old[$v] = [Environment]::GetEnvironmentVariable($v,'Process')
}

try {
    $env:SHARPEMU_TRACE_DEMONS_ENTRY_WAIT = '1'
    $env:SHARPEMU_TRACE_DEMONS_UI_METHODS = '1'
    $env:SHARPEMU_PROFILE_GUEST_RIP = '1'
    # V73.9 used 1 ms. Entry-thread capture is additional Suspend/GetContext;
    # 4 ms keeps the diagnostic lower-impact while still yielding thousands of
    # entry samples over this run.
    $env:SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS = '4'
    $env:SHARPEMU_PROFILE_GUEST_RIP_REPORT_S = '5'
    $env:SHARPEMU_LOG_VIDEOOUT_FPS = '1'
    $env:SHARPEMU_AUTO_OPTIONS = '80,95,110,125,140'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE = '1'
    $env:SHARPEMU_SCANOUT_RECOVERY = 'off'

    foreach ($v in @(
        'SHARPEMU_LOG_USLEEP',
        'SHARPEMU_LOG_GUEST_THREADS',
        'SHARPEMU_TRACE_LABEL_PROVENANCE',
        'SHARPEMU_LOG_IO',
        'SHARPEMU_LOG_AMPR_READS',
        'SHARPEMU_LOG_AGC',
        'SHARPEMU_LOG_AGC_SHADER',
        'SHARPEMU_LOG_VK_RESOURCES',
        'SHARPEMU_TRACE_DRAWS',
        'SHARPEMU_TRACE_FRAME_PACKETS'
    )) {
        Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
    }

    Write-Host '[V73.11] Starting main-entry wait-counter diagnostic.'
    Write-Host '[V73.11] V73.10 usleep HLE preference is rolled back.'
    Write-Host '[V73.11] Entry thread and worker threads are sampled separately.'
    Write-Host '[V73.11] The run will stop automatically after 150 seconds.'

    $process = Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds(150)
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }

    if (-not $process.HasExited) {
        Write-Host '[V73.11] 150-second diagnostic window complete; stopping emulator.'
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }

    try {
        $exitCode = $process.ExitCode
    }
    catch {
        $exitCode = 'diagnostic-stop'
    }
}
finally {
    foreach ($v in $vars) {
        if ($null -eq $old[$v]) {
            Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')
        }
    }
}

$err = @()
$outLines = @()
if (Test-Path -LiteralPath $stderr -PathType Leaf) {
    $err = @([IO.File]::ReadAllLines($stderr))
}
if (Test-Path -LiteralPath $stdout -PathType Leaf) {
    $outLines = @([IO.File]::ReadAllLines($stdout))
}

function Pick([string]$Needle) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $err) {
        if ($line.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $result.Add($line)
        }
    }
    return $result.ToArray()
}

$entryWait = @(Pick '[V73.11][ENTRY_WAIT]')
$entrySummary = @(Pick '[V73.11][ENTRY]')
$uiCounts = @(Pick '[V73.9][UI_RIP] counts')
$uiHits = @(Pick '[V73.9][UI_RIP] first_hit')
$workerProfile = @(Pick '[PERF][GUEST]')
$fps = @(Pick '[LOADER][PERF] videoout submitted_fps=')
$options = @(Pick '[STARTMENU][AUTO_OPTIONS][V2.1.0]')
$scanout = @(Pick 'agc.scanout_lineage')
$unresolved = @(Pick 'unresolved:')
$deviceLost = @(Pick 'deviceLost=True')
$applicationHang = @(Pick 'APPLICATION_HANG')

$uiNames = @(
    'HasOpenMenus',
    'PrintSceneState',
    'ShowHudSceneRegion',
    'TransitionShowHUDValidate',
    'ShowLegacyMenuA',
    'ShowLegacyMenuB',
    'StartMenuThink',
    'StartMenuHandleInputFocus'
)
$maxUi = @{}
foreach ($name in $uiNames) {
    $maxUi[$name] = 0L
}
foreach ($line in $uiCounts) {
    foreach ($name in $uiNames) {
        $m = [regex]::Match(
            $line,
            '\b'+[regex]::Escape($name)+'=(\d+)')
        if (-not $m.Success) {
            continue
        }

        $value = 0L
        if ([long]::TryParse($m.Groups[1].Value,[ref]$value) -and
            $value -gt $maxUi[$name]) {
            $maxUi[$name] = $value
        }
    }
}

$entrySamples = 0L
$entryGuest = 0L
$entryGenericWait = 0L
$entryReadable = 0L
$entryMatched = 0L
$entryWaiting = 0L
foreach ($line in $entrySummary) {
    foreach ($field in @(
        @{Name='samples'; Ref='entrySamples'},
        @{Name='guest'; Ref='entryGuest'},
        @{Name='generic_wait'; Ref='entryGenericWait'},
        @{Name='readable'; Ref='entryReadable'},
        @{Name='matched'; Ref='entryMatched'},
        @{Name='waiting'; Ref='entryWaiting'}
    )) {
        $m = [regex]::Match(
            $line,
            '\b'+[regex]::Escape($field.Name)+'=(\d+)')
        if (-not $m.Success) {
            continue
        }
        $value = 0L
        if (-not [long]::TryParse($m.Groups[1].Value,[ref]$value)) {
            continue
        }

        switch ($field.Ref) {
            'entrySamples' { if ($value -gt $entrySamples) { $entrySamples = $value } }
            'entryGuest' { if ($value -gt $entryGuest) { $entryGuest = $value } }
            'entryGenericWait' { if ($value -gt $entryGenericWait) { $entryGenericWait = $value } }
            'entryReadable' { if ($value -gt $entryReadable) { $entryReadable = $value } }
            'entryMatched' { if ($value -gt $entryMatched) { $entryMatched = $value } }
            'entryWaiting' { if ($value -gt $entryWaiting) { $entryWaiting = $value } }
        }
    }
}

$observedNonZeroWaiting = 0
$observedMatched = 0
$distinctWaitPointers = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($line in $entryWait) {
    $pointerMatch = [regex]::Match($line,'\bwait_ptr=(0x[0-9A-Fa-f]+)')
    if ($pointerMatch.Success) {
        [void]$distinctWaitPointers.Add($pointerMatch.Groups[1].Value)
    }

    if ($line.IndexOf('predicate=matched',[StringComparison]::Ordinal) -ge 0) {
        $observedMatched++
    }

    if ($line.IndexOf('predicate=waiting',[StringComparison]::Ordinal) -ge 0) {
        $valueMatch = [regex]::Match($line,'\bwait_value=(0x[0-9A-Fa-f]+)')
        if ($valueMatch.Success -and
            $valueMatch.Groups[1].Value -ne '0x0000000000000000') {
            $observedNonZeroWaiting++
        }
    }
}

$optionPress = @(
    $options |
        Where-Object {
            $_.IndexOf(' press ',[StringComparison]::Ordinal) -ge 0
        }
)

$positivePresented = 0
$positiveSubmitted = 0
$maxPresented = 0.0
foreach ($line in $fps) {
    $submittedMatch = [regex]::Match(
        $line,
        'submitted_fps=([0-9]+(?:[\.,][0-9]+)?)')
    if ($submittedMatch.Success) {
        $text = $submittedMatch.Groups[1].Value.Replace(',','.')
        $value = 0.0
        if ([double]::TryParse(
                $text,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$value) -and
            $value -gt 0) {
            $positiveSubmitted++
        }
    }

    $presentedMatch = [regex]::Match(
        $line,
        'presented_fps=([0-9]+(?:[\.,][0-9]+)?)')
    if ($presentedMatch.Success) {
        $text = $presentedMatch.Groups[1].Value.Replace(',','.')
        $value = 0.0
        if ([double]::TryParse(
                $text,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$value)) {
            if ($value -gt 0) {
                $positivePresented++
            }
            if ($value -gt $maxPresented) {
                $maxPresented = $value
            }
        }
    }
}

$classification = 'entry-thread-diagnostic-inconclusive'
if ($maxUi['StartMenuThink'] -gt 0 -or
    $maxUi['StartMenuHandleInputFocus'] -gt 0) {
    $classification = 'entry-or-worker-reaches-startmenu-native-code'
}
elseif ($maxUi['HasOpenMenus'] -gt 0 -or
        $maxUi['ShowHudSceneRegion'] -gt 0 -or
        $maxUi['TransitionShowHUDValidate'] -gt 0) {
    $classification = 'entry-or-worker-reaches-ui-manager-native-code'
}
elseif ($entryGenericWait -gt 0 -and
        $observedNonZeroWaiting -gt 0 -and
        $observedMatched -eq 0) {
    $classification = 'main-entry-generic-wait-counter-stuck-nonzero'
}
elseif ($entryGenericWait -gt 0 -and
        $observedMatched -gt 0) {
    $classification = 'main-entry-generic-wait-predicate-satisfied-ui-still-unreached'
}
elseif ($entryGuest -gt 0 -and $entryGenericWait -eq 0) {
    $classification = 'main-entry-running-outside-audited-generic-wait'
}
elseif ($entrySamples -eq 0) {
    $classification = 'main-entry-thread-not-captured'
}

Write-Utf8Lines -Path (Join-Path $out 'ENTRY_WAIT_TRACE.txt') -Lines $entryWait
Write-Utf8Lines -Path (Join-Path $out 'ENTRY_SUMMARY_WINDOWS.txt') -Lines $entrySummary
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_COUNTS.txt') -Lines $uiCounts
Write-Utf8Lines -Path (Join-Path $out 'UI_RIP_FIRST_HITS.txt') -Lines $uiHits
Write-Utf8Lines -Path (Join-Path $out 'WORKER_RIP_PROFILE.txt') -Lines $workerProfile
Write-Utf8Lines -Path (Join-Path $out 'VIDEOOUT_FPS.txt') -Lines $fps
Write-Utf8Lines -Path (Join-Path $out 'AUTO_OPTIONS.txt') -Lines $options
Write-Utf8Lines -Path (Join-Path $out 'SCANOUT_LINEAGE.txt') -Lines $scanout

$milestones = New-Object System.Collections.Generic.List[string]
foreach ($needle in @(
    'ResourcePool::RecordResourceDependencies()',
    'Starting Script:',
    'Starting main loop:',
    'ResourcePool::GatherResourceFileInfo()'
)) {
    foreach ($line in $outLines) {
        if ($line.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $milestones.Add($line)
        }
    }
}
Write-Utf8Lines -Path (Join-Path $out 'BOOT_MILESTONES.txt') -Lines $milestones

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('version=73.11')
$summary.Add(('exit_code={0}' -f $exitCode))
$summary.Add(('classification={0}' -f $classification))
$summary.Add(('eboot_sha256={0}' -f $actualEboot))
$summary.Add('v73_10_usleep_hle_preference_rolled_back=1')
$summary.Add(('entry_samples={0}' -f $entrySamples))
$summary.Add(('entry_guest_samples={0}' -f $entryGuest))
$summary.Add(('entry_generic_wait_samples={0}' -f $entryGenericWait))
$summary.Add(('entry_wait_readable_samples={0}' -f $entryReadable))
$summary.Add(('entry_wait_matched_samples={0}' -f $entryMatched))
$summary.Add(('entry_wait_nonmatched_samples={0}' -f $entryWaiting))
$summary.Add(('entry_wait_trace_lines={0}' -f $entryWait.Count))
$summary.Add(('entry_wait_distinct_pointers={0}' -f $distinctWaitPointers.Count))
$summary.Add(('entry_wait_observed_nonzero_waiting={0}' -f $observedNonZeroWaiting))
$summary.Add(('entry_wait_observed_matched={0}' -f $observedMatched))
foreach ($name in $uiNames) {
    $summary.Add(('ui_{0}={1}' -f $name,$maxUi[$name]))
}
$summary.Add(('auto_options_press={0}' -f $optionPress.Count))
$summary.Add(('videoout_fps_windows={0}' -f $fps.Count))
$summary.Add(('videoout_submitted_positive_windows={0}' -f $positiveSubmitted))
$summary.Add(('videoout_presented_positive_windows={0}' -f $positivePresented))
$summary.Add(('videoout_max_presented_fps={0:F3}' -f $maxPresented))
$summary.Add(('scanout_lineage={0}' -f $scanout.Count))
$summary.Add(('application_hang_lines={0}' -f $applicationHang.Count))
$summary.Add(('runtime_unresolved={0}' -f $unresolved.Count))
$summary.Add(('device_lost={0}' -f $deviceLost.Count))
$summary.Add(('boot_milestones={0}' -f $milestones.Count))
Write-Utf8Lines -Path (Join-Path $out 'SUMMARY.txt') -Lines $summary

$packageRoot = Get-PackageRoot
Copy-Item `
    -LiteralPath (Join-Path $packageRoot 'evidence\V73_11_REASONING.txt') `
    -Destination $out `
    -Force
Copy-Item `
    -LiteralPath (Join-Path $packageRoot 'evidence\V73_10_ENTRY_USLEEP_SAMPLES.txt') `
    -Destination $out `
    -Force

$sourceDir = Join-Path $out 'sources'
New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
foreach ($relative in @(
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs',
    'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs',
    'src\SharpEmu.Libs\Kernel\KernelRuntimeCompatExports.cs'
)) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        continue
    }

    $destination = Join-Path $sourceDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$zipPath = $out + '.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath -Force

Write-Host ('[V73.11] RESULT: {0}' -f $zipPath)
Write-Host ('[V73.11] classification={0}' -f $classification)
Write-Host (
    '[V73.11] entry samples/guest/wait={0}/{1}/{2}; readable/matched/waiting={3}/{4}/{5}; pointers={6}; UI StartMenuThink={7}; Options={8}' -f
    $entrySamples,
    $entryGuest,
    $entryGenericWait,
    $entryReadable,
    $entryMatched,
    $entryWaiting,
    $distinctWaitPointers.Count,
    $maxUi['StartMenuThink'],
    $optionPress.Count)
