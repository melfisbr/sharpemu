param(
    [string]$RepositoryRoot = "",
    [string]$Eboot = "F:\JOGOSPS5\PPSA01341\eboot.bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

function Get-LiveTreeIdsV740231 {
    param([int]$RootId)
    $ids = New-Object 'System.Collections.Generic.List[int]'
    try { if (Get-Process -Id $RootId -ErrorAction SilentlyContinue) { $ids.Add($RootId) } } catch {}
    foreach ($childId in @(Get-DescendantProcessIdsV740231 -ParentId $RootId)) {
        if (-not $ids.Contains([int]$childId)) { $ids.Add([int]$childId) }
    }
    return @($ids)
}

function Get-TreeMemoryV740231 {
    param([int[]]$Ids)
    [double]$workingBytes = 0
    [double]$privateBytes = 0
    $liveCount = 0
    foreach ($processIdValue in $Ids) {
        try {
            $processInfo = Get-Process -Id $processIdValue -ErrorAction Stop
            $workingBytes += [double]$processInfo.WorkingSet64
            $privateBytes += [double]$processInfo.PrivateMemorySize64
            $liveCount++
        } catch {}
    }
    return [pscustomobject]@{
        Live = $liveCount
        WorkingMb = [Math]::Round($workingBytes / 1MB, 1)
        PrivateMb = [Math]::Round($privateBytes / 1MB, 1)
    }
}

function Get-MaxCounterV740231 {
    param([string]$Text, [string]$Pattern)
    $maxValue = 0
    foreach ($counterMatch in [regex]::Matches($Text, $Pattern)) {
        [int]$parsedValue = 0
        if ([int]::TryParse($counterMatch.Groups[1].Value, [ref]$parsedValue) -and $parsedValue -gt $maxValue) {
            $maxValue = $parsedValue
        }
    }
    return $maxValue
}

$repoRoot = Resolve-RepoRootV740231 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
$presenterText = [System.IO.File]::ReadAllText((Get-PresenterPathV740231 -Root $repoRoot))
if ((Get-V231StateV740231 -Text $presenterText) -ne "Applied") {
    throw "[V74.0.23.1] Source repair is not applied. RUN_3 must finish successfully before RUN_4."
}
$ebootPath = [System.IO.Path]::GetFullPath($Eboot)
if (-not [System.IO.File]::Exists($ebootPath)) { throw "[V74.0.23.1] EBOOT missing: $ebootPath" }
$expectedEboot = "22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actualEboot = (Get-FileHash -LiteralPath $ebootPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actualEboot -ne $expectedEboot) { throw "[V74.0.23.1] EBOOT SHA256 mismatch: $actualEboot" }
$runtimeDll = [System.IO.Path]::Combine($repoRoot, "artifacts", "bin", "Release", "net10.0", "win-x64", "SharpEmu.dll")
if (-not [System.IO.File]::Exists($runtimeDll)) { throw "[V74.0.23.1] Release runtime missing: $runtimeDll" }
$dotnetCommand = (Get-Command dotnet -ErrorAction Stop).Source

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDirectory = [System.IO.Path]::Combine($repoRoot, "SharpEmu_V74_0_23_1_LARGE_ARRAY_BASELINE_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$stdoutPath = [System.IO.Path]::Combine($outputDirectory, "stdout.log")
$stderrPath = [System.IO.Path]::Combine($outputDirectory, "stderr.log")
$profilePath = [System.IO.Path]::Combine($outputDirectory, "RUN_PROFILE.txt")
$summaryPath = [System.IO.Path]::Combine($outputDirectory, "SUMMARY.txt")
$milestonesPath = [System.IO.Path]::Combine($outputDirectory, "MILESTONES.txt")
$perfPath = [System.IO.Path]::Combine($outputDirectory, "PROCESS_TREE_PERF.csv")
[System.IO.File]::WriteAllText($perfPath, "elapsed_s,live_processes,working_mb,private_mb`r`n")
[System.IO.File]::WriteAllText($milestonesPath, "")

$environmentProfile = [ordered]@{
    SHARPEMU_BINK_AUTO_BOOT = "0"
    SHARPEMU_BINK_AUTO_BOOT_GRACE_MS = "1500"
    SHARPEMU_BINK_STARTUP_COMPLETION_SHIM = "1"
    SHARPEMU_LLE_INIT_ENV = "1"
    SHARPEMU_LLE_LIBC_SAFE_ONLY = "1"
    SHARPEMU_DISABLE_LLE_LIBC = "0"
    SHARPEMU_LOG_PROC_PARAM = "0"
    SHARPEMU_LOG_PROC_PARAM_PTRS = "0"
    SHARPEMU_NATIVE_MEMCPY_INTRINSIC = "1"
    SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC = "1"
    SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT = "2"
    SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT = "8"
    SHARPEMU_RENDER_SCALE = "1.0"
    SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB = "256"
    SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB = "768"
    SHARPEMU_VK_GUEST_BUFFER_CACHE_MB = "192"
    SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB = "384"
    SHARPEMU_DCC_ALIAS_HISTORY_MS = "0"
    SHARPEMU_TRACE_DCC_ALIAS = "0"
    SHARPEMU_LARGE_ARRAY_CACHE_TRUST = "0"
    SHARPEMU_PERF_MEM = "0"
    SHARPEMU_PROFILE_RENDER = "0"
    SHARPEMU_TRACE_DRAWS = "0"
    SHARPEMU_LOG_ALL_IMPORTS = "0"
    SHARPEMU_LOG_IMPORT_PERIODIC = "0"
    SHARPEMU_LOG_GUEST_THREADS = "0"
    SHARPEMU_LOG_PTHREADS = "0"
    SHARPEMU_OVERLAY = "0"
}
$previousEnvironment = @{}
foreach ($environmentName in $environmentProfile.Keys) {
    $previousEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable($environmentName, "Process")
    [Environment]::SetEnvironmentVariable($environmentName, $environmentProfile[$environmentName], "Process")
}
$profileLines = New-Object 'System.Collections.Generic.List[string]'
$profileLines.Add("version=74.0.23.1")
$profileLines.Add("eboot=$ebootPath")
$profileLines.Add("eboot_sha256=$actualEboot")
$profileLines.Add("runtime=$runtimeDll")
$profileLines.Add("runner_auto_kill=False")
$profileLines.Add("exit_policy=user-closes-window-or-runtime-exits")
$profileLines.Add("large_array_sparse_baseline=source-enabled-bounded-512MiB")
foreach ($environmentName in $environmentProfile.Keys) { $profileLines.Add("$environmentName=$($environmentProfile[$environmentName])") }
[System.IO.File]::WriteAllLines($profilePath, $profileLines)

Write-Host "[V74.0.23.1] LARGE-ARRAY SPARSE-BASELINE TEST starting."
Write-Host "[V74.0.23.1] Host Bink auto boot remains OFF; V74.0.21 Entry ABI remains active."
Write-Host "[V74.0.23.1] Old V74.0.23 AGC trust experiment is explicitly OFF."
Write-Host "[V74.0.23.1] No timer will close SharpEmu. Close the SharpEmu window yourself when you want the result ZIP."

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$processObject = $null
$lastStatus = -10.0
$seenBaseline = 0
$seenNatural = 0
$seenCompleted = 0
$seenMainLoop = $false
$seenFrame = $false
$launcherExitCode = "not-observed"
try {
    $dotnetArgumentLine = '"{0}" "{1}"' -f $runtimeDll, $ebootPath
    $processObject = Start-Process -FilePath $dotnetCommand -ArgumentList $dotnetArgumentLine -WorkingDirectory (Split-Path -Parent $runtimeDll) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    while ($true) {
        Start-Sleep -Milliseconds 1000
        $elapsedSeconds = $runStopwatch.Elapsed.TotalSeconds
        try { $processObject.Refresh() } catch {}
        $treeIds = @(Get-LiveTreeIdsV740231 -RootId $processObject.Id)
        $treeInfo = Get-TreeMemoryV740231 -Ids $treeIds
        Add-Content -LiteralPath $perfPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1},{1},{2:F1},{3:F1}", $elapsedSeconds, $treeInfo.Live, $treeInfo.WorkingMb, $treeInfo.PrivateMb))
        $stderrText = Read-TextSharedV740231 -Path $stderrPath
        $stdoutText = Read-TextSharedV740231 -Path $stdoutPath
        $combinedText = $stderrText + "`n" + $stdoutText

        $baselineLogged = ([regex]::Matches($combinedText, '\[V74\.0\.23\.1\]\[ARRAY_BASELINE\]')).Count
        if ($baselineLogged -gt $seenBaseline) {
            $seenBaseline = $baselineLogged
            Write-Host "[V74.0.23.1] Large-array sparse baseline observed; logged=$baselineLogged"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1}s array_baseline logged={1}", $elapsedSeconds, $baselineLogged))
        }
        if (-not $seenMainLoop -and $combinedText -match 'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s') {
            $seenMainLoop = $true
            $mainLoopValue = $Matches[1]
            Write-Host "[V74.0.23.1] Main loop observed: guest_seconds=$mainLoopValue"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1}s main_loop guest_seconds={1}", $elapsedSeconds, $mainLoopValue))
        }
        if (-not $seenFrame -and $combinedText -match 'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)') {
            $seenFrame = $true
            $frameSizeValue = $Matches[1]
            Write-Host "[V74.0.23.1] First guest frame observed: $frameSizeValue"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1}s first_guest_frame size={1}", $elapsedSeconds, $frameSizeValue))
        }
        $naturalCount = ([regex]::Matches($combinedText, 'bink2\.natural_guest_movie_observed')).Count
        if ($naturalCount -gt $seenNatural) {
            $seenNatural = $naturalCount
            Write-Host "[V74.0.23.1] Natural guest movie observed: count=$naturalCount"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1}s natural_guest_movie count={1}", $elapsedSeconds, $naturalCount))
        }
        $completedCount = ([regex]::Matches($combinedText, 'Bink (?:RAD|NIHAV) bridge completed: .*?\.bk2')).Count
        if ($completedCount -gt $seenCompleted) {
            $seenCompleted = $completedCount
            Write-Host "[V74.0.23.1] Bink completion observed: count=$completedCount"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:F1}s bink_completed count={1}", $elapsedSeconds, $completedCount))
        }
        if (($elapsedSeconds - $lastStatus) -ge 10.0) {
            $lastStatus = $elapsedSeconds
            Write-Host ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "[V74.0.23.1] t={0:F0}s procs={1} work={2:F0}MB private={3:F0}MB baseline_logs={4} natural={5} completed={6}", $elapsedSeconds, $treeInfo.Live, $treeInfo.WorkingMb, $treeInfo.PrivateMb, $seenBaseline, $seenNatural, $seenCompleted))
        }
        if ($treeInfo.Live -eq 0) {
            try { $processObject.Refresh(); if ($processObject.HasExited) { $launcherExitCode = $processObject.ExitCode } } catch {}
            break
        }
    }
}
finally {
    foreach ($environmentName in $environmentProfile.Keys) {
        [Environment]::SetEnvironmentVariable($environmentName, $previousEnvironment[$environmentName], "Process")
    }
}
$runStopwatch.Stop()
Start-Sleep -Milliseconds 500
$stderrFinal = Read-TextSharedV740231 -Path $stderrPath
$stdoutFinal = Read-TextSharedV740231 -Path $stdoutPath
$combinedFinal = $stderrFinal + "`n" + $stdoutFinal

$baselineLoggedFinal = ([regex]::Matches($combinedFinal, '\[V74\.0\.23\.1\]\[ARRAY_BASELINE\]')).Count
$baselineMax = Get-MaxCounterV740231 -Text $combinedFinal -Pattern '\[V74\.0\.23\.1\]\[ARRAY_BASELINE\] count=(\d+)'
$arrayStale = ([regex]::Matches($combinedFinal, 'TEXTURE_CACHE_STALE[^\r\n]*reason=missing-baseline[^\r\n]*addr=0x000000102A400000|TEXTURE_CACHE_STALE[^\r\n]*addr=0x000000102A400000[^\r\n]*reason=missing-baseline')).Count
$arrayRefresh = ([regex]::Matches($combinedFinal, 'TEXTURE_CACHE_REFRESH[^\r\n]*addr=0x000000102A400000')).Count
$arrayOwnerMax = Get-MaxCounterV740231 -Text $combinedFinal -Pattern 'ARRAY_SINGLEFLIGHT\] owner[^\r\n]*count=(\d+)[^\r\n]*addr=0x000000102A400000'
$arrayReuseMax = Get-MaxCounterV740231 -Text $combinedFinal -Pattern 'ARRAY_SINGLEFLIGHT\] reuse[^\r\n]*count=(\d+)[^\r\n]*addr=0x000000102A400000'
$allocMax = Get-MaxCounterV740231 -Text $combinedFinal -Pattern 'alloc2s_mb=(\d+)'
$naturalMatches = [regex]::Matches($combinedFinal, "bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+\.bk2)'")
$attachMatches = [regex]::Matches($combinedFinal, "(?:Bink RAD|Bink2 NIHAV) bridge attached:\s*([^\s']+\.bk2)")
$completeMatches = [regex]::Matches($combinedFinal, "(?:Bink RAD|Bink2 NIHAV) bridge completed:\s*([^\s']+\.bk2)")
$deviceLost = ([regex]::Matches($combinedFinal, '(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException')).Count
$heapCorruption = ([regex]::Matches($combinedFinal, '(?i)HEAP_CORRUPTION|0xC0000374')).Count
$firstFrameMatches = [regex]::Matches($combinedFinal, 'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)')
$firstFrameSize = if ($firstFrameMatches.Count -gt 0) { $firstFrameMatches[0].Groups[1].Value } else { "none" }
$mainLoopMatches = [regex]::Matches($combinedFinal, 'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s')
$mainLoopSeconds = if ($mainLoopMatches.Count -gt 0) { $mainLoopMatches[$mainLoopMatches.Count - 1].Groups[1].Value } else { "not-observed" }
$gatherMatches = [regex]::Matches($combinedFinal, 'ResourcePool::GatherResourceFileInfo\(\) took\s*([0-9]+(?:[.,][0-9]+)?)s')
$gatherSeconds = if ($gatherMatches.Count -gt 0) { $gatherMatches[$gatherMatches.Count - 1].Groups[1].Value } else { "not-observed" }
$perfRows = @(Import-Csv -LiteralPath $perfPath)
[double]$peakWorking = 0
[double]$peakPrivate = 0
foreach ($perfRow in $perfRows) {
    [double]$workingValue = 0
    [double]$privateValue = 0
    if ([double]::TryParse($perfRow.working_mb, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$workingValue) -and $workingValue -gt $peakWorking) { $peakWorking = $workingValue }
    if ([double]::TryParse($perfRow.private_mb, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$privateValue) -and $privateValue -gt $peakPrivate) { $peakPrivate = $privateValue }
}

$classification = "large-array-baseline-test-complete"
if ($deviceLost -gt 0) { $classification = "device-lost" }
elseif ($baselineMax -eq 0) { $classification = "large-array-baseline-not-reached" }
elseif ($arrayStale -le 1 -and $arrayRefresh -le 1 -and $naturalMatches.Count -gt 0) { $classification = "large-array-baseline-fixed-natural-boot-progressed" }
elseif ($arrayStale -le 1 -and $arrayRefresh -le 1) { $classification = "large-array-baseline-fixed-awaiting-natural-movie" }
else { $classification = "large-array-baseline-still-refreshing" }
$naturalFiles = @($naturalMatches | ForEach-Object { $_.Groups[1].Value })
$attachedFiles = @($attachMatches | ForEach-Object { $_.Groups[1].Value })
$completedFiles = @($completeMatches | ForEach-Object { $_.Groups[1].Value })
$summaryLines = @(
    "VERSION=74.0.23.1",
    "WALL_SECONDS=$([Math]::Round($runStopwatch.Elapsed.TotalSeconds,2))",
    "RUNNER_FORCED_STOP=False",
    "LAUNCHER_EXIT_CODE=$launcherExitCode",
    "CLASSIFICATION=$classification",
    "EBOOT_SHA256=$actualEboot",
    "ARRAY_BASELINE_LOGGED=$baselineLoggedFinal",
    "ARRAY_BASELINE_MAX_COUNTER=$baselineMax",
    "ARRAY_102A4_MISSING_BASELINE_STALE_LOGS=$arrayStale",
    "ARRAY_102A4_REFRESH_LOGS=$arrayRefresh",
    "ARRAY_SINGLEFLIGHT_OWNER_MAX=$arrayOwnerMax",
    "ARRAY_SINGLEFLIGHT_REUSE_MAX=$arrayReuseMax",
    "MAX_ALLOC2S_MB=$allocMax",
    "PEAK_TREE_WORKING_MB=$([Math]::Round($peakWorking,1))",
    "PEAK_TREE_PRIVATE_MB=$([Math]::Round($peakPrivate,1))",
    "NATURAL_GUEST_MOVIE_COUNT=$($naturalMatches.Count)",
    "NATURAL_GUEST_MOVIES=$($naturalFiles -join ' -> ')",
    "BINK_ATTACH_COUNT=$($attachMatches.Count)",
    "BINK_ATTACH_FILES=$($attachedFiles -join ' -> ')",
    "BINK_COMPLETED_COUNT=$($completeMatches.Count)",
    "BINK_COMPLETED_FILES=$($completedFiles -join ' -> ')",
    "FIRST_GUEST_FRAME=$firstFrameSize",
    "MAIN_LOOP_SECONDS=$mainLoopSeconds",
    "GATHER_SECONDS=$gatherSeconds",
    "DEVICE_LOST_HITS=$deviceLost",
    "HEAP_CORRUPTION_HITS=$heapCorruption",
    "HOST_AUTO_BOOT=OFF",
    "OLD_V74023_AGC_TRUST=OFF",
    "HOST_MOVIE_BRIDGE_CHANGED=False"
)
[System.IO.File]::WriteAllLines($summaryPath, $summaryLines)
$zipPath = $outputDirectory + ".zip"
if ([System.IO.File]::Exists($zipPath)) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path ([System.IO.Path]::Combine($outputDirectory, "*")) -DestinationPath $zipPath -CompressionLevel Optimal -Force
Write-Host "[V74.0.23.1] RESULT: $classification"
Write-Host "[V74.0.23.1] baseline_max=$baselineMax stale=$arrayStale refresh=$arrayRefresh owner_max=$arrayOwnerMax reuse_max=$arrayReuseMax max_alloc2s=$allocMax natural=$($naturalMatches.Count) peak_work=$([Math]::Round($peakWorking,1))MB"
Write-Host "[V74.0.23.1] Result ZIP: $zipPath"
