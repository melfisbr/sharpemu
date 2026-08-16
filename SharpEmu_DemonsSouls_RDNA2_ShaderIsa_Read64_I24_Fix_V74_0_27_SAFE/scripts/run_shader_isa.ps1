param(
    [string]$RepositoryRoot = "",
    [string]$Eboot = "F:\JOGOSPS5\PPSA01341\eboot.bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

function Get-LiveTreeIdsV74027 {
    param([int]$RootId)
    $ids=New-Object 'System.Collections.Generic.List[int]'
    try { if (Get-Process -Id $RootId -ErrorAction SilentlyContinue) { $ids.Add($RootId) } } catch {}
    foreach ($childIdValue in @(Get-DescendantProcessIdsV74027 -ParentId $RootId)) {
        if (-not $ids.Contains([int]$childIdValue)) { $ids.Add([int]$childIdValue) }
    }
    return @($ids)
}

function Get-TreeMetricsV74027 {
    param([int[]]$Ids)
    [double]$workingBytes=0
    [double]$privateBytes=0
    [double]$cpuSeconds=0
    $liveCount=0
    foreach($processIdValue in $Ids){
        try{
            $processInfo=Get-Process -Id $processIdValue -ErrorAction Stop
            $workingBytes += [double]$processInfo.WorkingSet64
            $privateBytes += [double]$processInfo.PrivateMemorySize64
            $cpuSeconds += [double]$processInfo.TotalProcessorTime.TotalSeconds
            $liveCount++
        }catch{}
    }
    return [pscustomobject]@{
        Live=$liveCount
        WorkingMb=[Math]::Round($workingBytes/1MB,1)
        PrivateMb=[Math]::Round($privateBytes/1MB,1)
        CpuSeconds=$cpuSeconds
    }
}

function Get-WaitLatencyStatsV74027 {
    param([string]$Text)
    $count=0
    $overOneSecond=0
    $overFourSeconds=0
    [double]$maxMilliseconds=0
    [double]$sumMilliseconds=0
    foreach($latencyMatch in [regex]::Matches($Text,'\[V74\.0\.25\]\[WAIT_RESUME\][^\r\n]*waited_ms=([0-9]+(?:[.,][0-9]+)?)')){
        $milliseconds=Convert-InvariantDoubleV74027 -Value $latencyMatch.Groups[1].Value
        $count++
        $sumMilliseconds += $milliseconds
        if($milliseconds -gt $maxMilliseconds){$maxMilliseconds=$milliseconds}
        if($milliseconds -gt 1000){$overOneSecond++}
        if($milliseconds -gt 4000){$overFourSeconds++}
    }
    $average=if($count -gt 0){$sumMilliseconds/$count}else{0}
    return [pscustomobject]@{
        Count=$count
        MaxMs=$maxMilliseconds
        AverageMs=$average
        Gt1000=$overOneSecond
        Gt4000=$overFourSeconds
    }
}

$repoRoot=Resolve-RepoRootV74027 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
if((Get-ShaderIsaStateV74027 -Root $repoRoot) -ne "Applied"){throw "[V74.0.27] RUN_4 requires RUN_3 success: shader ISA state is not Applied."}

$ebootPath=[System.IO.Path]::GetFullPath($Eboot)
if(-not [System.IO.File]::Exists($ebootPath)){throw "[V74.0.27] EBOOT missing: $ebootPath"}
$expectedEboot="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actualEboot=(Get-FileHash -LiteralPath $ebootPath -Algorithm SHA256).Hash.ToUpperInvariant()
if($actualEboot -ne $expectedEboot){throw "[V74.0.27] EBOOT SHA256 mismatch: $actualEboot"}

$runtimeDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($runtimeDll)){throw "[V74.0.27] Release runtime missing: $runtimeDll"}
$dotnetCommand=(Get-Command dotnet -ErrorAction Stop).Source

$processorCount=[Environment]::ProcessorCount
$defaultReserved=[Math]::Max(2,[int]([Math]::Floor($processorCount*3/8)))
$testReserved=$defaultReserved
$testUsable=[Math]::Max($processorCount-$testReserved,2)
$uniqueBpeLanes=New-Object 'System.Collections.Generic.HashSet[int]'
$bpeMap=New-Object 'System.Collections.Generic.List[string]'
for($guestCpu=0;$guestCpu -le 12;$guestCpu++){
    $hostCpu=Get-HostCpuForGuestV74027 -GuestCpu $guestCpu -ProcessorCount $processorCount -ReservedLanes $testReserved
    [void]$uniqueBpeLanes.Add($hostCpu)
    $bpeMap.Add("$guestCpu->$hostCpu")
}
$rendererCpu9=Get-HostCpuForGuestV74027 -GuestCpu 9 -ProcessorCount $processorCount -ReservedLanes $testReserved
$rendererCpu11=Get-HostCpuForGuestV74027 -GuestCpu 11 -ProcessorCount $processorCount -ReservedLanes $testReserved

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$outputDirectory=[System.IO.Path]::Combine($repoRoot,"SharpEmu_V74_0_27_SHADER_ISA_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($outputDirectory)|Out-Null
$stdoutPath=[System.IO.Path]::Combine($outputDirectory,"stdout.log")
$stderrPath=[System.IO.Path]::Combine($outputDirectory,"stderr.log")
$profilePath=[System.IO.Path]::Combine($outputDirectory,"RUN_PROFILE.txt")
$summaryPath=[System.IO.Path]::Combine($outputDirectory,"SUMMARY.txt")
$milestonesPath=[System.IO.Path]::Combine($outputDirectory,"MILESTONES.txt")
$perfPath=[System.IO.Path]::Combine($outputDirectory,"PROCESS_TREE_PERF.csv")
[System.IO.File]::WriteAllText($perfPath,"elapsed_s,live_processes,working_mb,private_mb,cpu_percent,cpu_core_equiv`r`n")
[System.IO.File]::WriteAllText($milestonesPath,"")

$environmentProfile=[ordered]@{
    SHARPEMU_RESERVED_HOST_LANES="$testReserved"
    SHARPEMU_WRITE_DATA_PACKET_POSITION="1"
    SHARPEMU_BINK_AUTO_BOOT="0"
    SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="1500"
    SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"
    SHARPEMU_LLE_INIT_ENV="1"
    SHARPEMU_LLE_LIBC_SAFE_ONLY="1"
    SHARPEMU_DISABLE_LLE_LIBC="0"
    SHARPEMU_NATIVE_MEMCPY_INTRINSIC="1"
    SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC="1"
    SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"
    SHARPEMU_RENDER_SCALE="1.0"
    SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="256"
    SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="192"
    SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB="384"
    SHARPEMU_DCC_ALIAS_HISTORY_MS="0"
    SHARPEMU_TRACE_DCC_ALIAS="0"
    SHARPEMU_LARGE_ARRAY_CACHE_TRUST="0"
    SHARPEMU_PERF_MEM="0"
    SHARPEMU_PROFILE_RENDER="0"
    SHARPEMU_TRACE_DRAWS="0"
    SHARPEMU_LOG_AGC="0"
    SHARPEMU_LOG_AGC_SHADER="0"
    SHARPEMU_LOG_ALL_IMPORTS="0"
    SHARPEMU_LOG_IMPORT_PERIODIC="0"
    SHARPEMU_LOG_GUEST_THREADS="0"
    SHARPEMU_LOG_PTHREADS="0"
    SHARPEMU_OVERLAY="0"
}
$previousEnvironment=@{}
foreach($environmentName in $environmentProfile.Keys){
    $previousEnvironment[$environmentName]=[Environment]::GetEnvironmentVariable($environmentName,"Process")
    [Environment]::SetEnvironmentVariable($environmentName,$environmentProfile[$environmentName],"Process")
}

$profileLines=New-Object 'System.Collections.Generic.List[string]'
$profileLines.Add("version=74.0.27")
$profileLines.Add("eboot=$ebootPath")
$profileLines.Add("eboot_sha256=$actualEboot")
$profileLines.Add("runtime=$runtimeDll")
$profileLines.Add("runner_auto_kill=False")
$profileLines.Add("exit_policy=user-closes-window-or-runtime-exits")
$profileLines.Add("processor_count=$processorCount")
$profileLines.Add("source_default_reserved_lanes=$defaultReserved")
$profileLines.Add("source_default_usable_lanes=$($processorCount-$defaultReserved)")
$profileLines.Add("test_reserved_lanes=$testReserved")
$profileLines.Add("test_usable_lanes=$testUsable")
$profileLines.Add("lane_profile=source-default-recovered-after-v74026-no-speedup")
$profileLines.Add("shader_isa_state=Applied")
$profileLines.Add("BPE_CPU0_12_unique_host_lanes=$($uniqueBpeLanes.Count)")
$profileLines.Add("BPE_CPU0_12_map=$([string]::Join(',',@($bpeMap)))")
$profileLines.Add("HighGraphics_guest_cpu9_host_lane=$rendererCpu9")
$profileLines.Add("HighGraphics_guest_cpu11_host_lane=$rendererCpu11")
$profileLines.Add("baseline_v74025_wait_resume_samples=258")
$profileLines.Add("baseline_v74025_wait_resume_max_ms=7160.489")
$profileLines.Add("baseline_v74025_wait_resume_gt_1000ms=26")
$profileLines.Add("baseline_v74025_wait_resume_gt_4000ms=24")
$profileLines.Add("baseline_v74025_natural_bink=0_at_107.04s")
$profileLines.Add("baseline_v74026_first_natural_bink_seconds=366.2")
$profileLines.Add("baseline_v74026_lane_packing=10_usable_lanes_no_material_speedup")
foreach($environmentName in $environmentProfile.Keys){$profileLines.Add("$environmentName=$($environmentProfile[$environmentName])")}
[System.IO.File]::WriteAllLines($profilePath,$profileLines)

Write-Host "[V74.0.27] RDNA2 shader ISA post-boot test starting."
Write-Host "[V74.0.27] processor_count=$processorCount reserved_host_lanes restored to source default=$defaultReserved; guest_usable=$testUsable."
Write-Host "[V74.0.27] V74.0.26 lane-packing A/B is OFF; source-default mapping is active: $([string]::Join(', ',@($bpeMap)))"
Write-Host "[V74.0.27] V74.0.25 WRITE_DATA repair remains enabled; no WAIT label is force-written."
Write-Host "[V74.0.27] Host Bink auto boot remains OFF. No timer closes SharpEmu."
Write-Host "[V74.0.27] V74.0.26 reached the first natural movie near 366 s. Leave this run active through ps_studios_logo and at least 60 s after it completes."

$runStopwatch=[System.Diagnostics.Stopwatch]::StartNew()
$processObject=$null
$lastStatus=-10.0
$lastCpuSampleElapsed=0.0
$lastCpuSeconds=0.0
$hasCpuBaseline=$false
$seenWrite=0
$seenResume=0
$seenNatural=0
$seenCompleted=0
$seenMainLoop=$false
$seenFrame=$false
$launcherExitCode="not-observed"

try{
    $dotnetArgumentLine='"{0}" "{1}"' -f $runtimeDll,$ebootPath
    $processObject=Start-Process -FilePath $dotnetCommand -ArgumentList $dotnetArgumentLine -WorkingDirectory (Split-Path -Parent $runtimeDll) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    while($true){
        Start-Sleep -Milliseconds 1000
        $elapsedSeconds=$runStopwatch.Elapsed.TotalSeconds
        try{$processObject.Refresh()}catch{}
        $treeIds=@(Get-LiveTreeIdsV74027 -RootId $processObject.Id)
        $treeMetrics=Get-TreeMetricsV74027 -Ids $treeIds
        [double]$cpuPercent=0
        [double]$cpuCoreEquivalent=0
        if($hasCpuBaseline){
            $wallDelta=$elapsedSeconds-$lastCpuSampleElapsed
            $cpuDelta=[Math]::Max(0.0,$treeMetrics.CpuSeconds-$lastCpuSeconds)
            if($wallDelta -gt 0){
                $cpuCoreEquivalent=$cpuDelta/$wallDelta
                $cpuPercent=($cpuCoreEquivalent/$processorCount)*100.0
            }
        }else{$hasCpuBaseline=$true}
        $lastCpuSampleElapsed=$elapsedSeconds
        $lastCpuSeconds=$treeMetrics.CpuSeconds
        Add-Content -LiteralPath $perfPath -Encoding UTF8 -Value ([string]::Format(
            [Globalization.CultureInfo]::InvariantCulture,
            "{0:F1},{1},{2:F1},{3:F1},{4:F2},{5:F2}",
            $elapsedSeconds,$treeMetrics.Live,$treeMetrics.WorkingMb,$treeMetrics.PrivateMb,$cpuPercent,$cpuCoreEquivalent))

        $stderrText=Read-TextSharedV74027 -Path $stderrPath
        $stdoutText=Read-TextSharedV74027 -Path $stdoutPath
        $combinedText=$stderrText+"`n"+$stdoutText
        $writeCount=Get-MaxCounterV74027 -Text $combinedText -Pattern '\[V74\.0\.25\]\[WRITE_DATA_PACKET_POSITION\] count=(\d+)'
        if($writeCount -gt $seenWrite){
            $seenWrite=$writeCount
            Write-Host "[V74.0.27] WRITE_DATA packet-position count=$writeCount"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s write_data_packet_position={1}",$elapsedSeconds,$writeCount))
        }
        $resumeCount=Get-MaxCounterV74027 -Text $combinedText -Pattern '\[V74\.0\.25\]\[WAIT_RESUME\] count=(\d+)'
        if($resumeCount -gt $seenResume){
            $seenResume=$resumeCount
            Write-Host "[V74.0.27] Real WAIT resume count=$resumeCount"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s wait_resume={1}",$elapsedSeconds,$resumeCount))
        }
        if(-not $seenMainLoop -and $combinedText -match 'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s'){
            $seenMainLoop=$true
            $mainLoopValue=$Matches[1]
            Write-Host "[V74.0.27] Main loop observed: guest_seconds=$mainLoopValue"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s main_loop guest_seconds={1}",$elapsedSeconds,$mainLoopValue))
        }
        if(-not $seenFrame -and $combinedText -match 'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)'){
            $seenFrame=$true
            $frameSizeValue=$Matches[1]
            Write-Host "[V74.0.27] First guest frame observed: $frameSizeValue"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s first_guest_frame size={1}",$elapsedSeconds,$frameSizeValue))
        }
        $naturalCount=([regex]::Matches($combinedText,'bink2\.natural_guest_movie_observed')).Count
        if($naturalCount -gt $seenNatural){
            $seenNatural=$naturalCount
            Write-Host "[V74.0.27] Natural guest movie observed: count=$naturalCount"
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s natural_guest_movie count={1}",$elapsedSeconds,$naturalCount))
        }
        $completedCount=([regex]::Matches($combinedText,'Bink (?:RAD|NIHAV) bridge completed: .*?\.bk2')).Count
        if($completedCount -gt $seenCompleted){$seenCompleted=$completedCount;Write-Host "[V74.0.27] Bink completion observed: count=$completedCount"}

        if(($elapsedSeconds-$lastStatus)-ge 10.0){
            $lastStatus=$elapsedSeconds
            Write-Host ([string]::Format(
                [Globalization.CultureInfo]::InvariantCulture,
                "[V74.0.27] t={0:F0}s procs={1} cpu={2:F1}% cores={3:F1} work={4:F0}MB private={5:F0}MB write_pos={6} wait_resume={7} natural={8}",
                $elapsedSeconds,$treeMetrics.Live,$cpuPercent,$cpuCoreEquivalent,$treeMetrics.WorkingMb,$treeMetrics.PrivateMb,$seenWrite,$seenResume,$seenNatural))
        }
        if($treeMetrics.Live -eq 0){
            try{$processObject.Refresh();if($processObject.HasExited){$launcherExitCode=$processObject.ExitCode}}catch{}
            break
        }
    }
}finally{
    foreach($environmentName in $environmentProfile.Keys){[Environment]::SetEnvironmentVariable($environmentName,$previousEnvironment[$environmentName],"Process")}
}

$runStopwatch.Stop()
Start-Sleep -Milliseconds 500
$stderrFinal=Read-TextSharedV74027 -Path $stderrPath
$stdoutFinal=Read-TextSharedV74027 -Path $stdoutPath
$combinedFinal=$stderrFinal+"`n"+$stdoutFinal

$writeMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern '\[V74\.0\.25\]\[WRITE_DATA_PACKET_POSITION\] count=(\d+)'
$resumeMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern '\[V74\.0\.25\]\[WAIT_RESUME\] count=(\d+)'
$waitLatency=Get-WaitLatencyStatsV74027 -Text $combinedFinal
$startupLabels=@('0000000456CFF100','0000000456CFF360','0000000456CFF580','0000000456CFF700','0000000456CFF4C0','0000000442FFF300','0000000442FFF200')
$resumedLabels=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach($resumeMatch in [regex]::Matches($combinedFinal,'\[V74\.0\.25\]\[WAIT_RESUME\][^\r\n]*label=0x([0-9A-Fa-f]{16})')){
    if($startupLabels -contains $resumeMatch.Groups[1].Value.ToUpperInvariant()){[void]$resumedLabels.Add($resumeMatch.Groups[1].Value.ToUpperInvariant())}
}
$parserWaitersLast="not-observed"
$parserMatches=[regex]::Matches($combinedFinal,'\[V73\.0\.15\]\[PARSER_ESCAPE\][^\r\n]*waiters=(\d+)')
if($parserMatches.Count -gt 0){$parserWaitersLast=$parserMatches[$parserMatches.Count-1].Groups[1].Value}
$fenceWaitMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern 'vk\.ordered_action_fence_wait count=(\d+)'
$staleChangedTotal=([regex]::Matches($combinedFinal,'TEXTURE_CACHE_STALE[^\r\n]*reason=guest-bytes-changed')).Count
$arrayStale=([regex]::Matches($combinedFinal,'TEXTURE_CACHE_STALE[^\r\n]*reason=missing-baseline[^\r\n]*addr=0x000000102A400000|TEXTURE_CACHE_STALE[^\r\n]*addr=0x000000102A400000[^\r\n]*reason=missing-baseline')).Count
$arrayRefresh=([regex]::Matches($combinedFinal,'TEXTURE_CACHE_REFRESH[^\r\n]*addr=0x000000102A400000')).Count
$arrayOwnerMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern 'ARRAY_SINGLEFLIGHT\] owner[^\r\n]*count=(\d+)[^\r\n]*addr=0x000000102A400000'
$arrayReuseMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern 'ARRAY_SINGLEFLIGHT\] reuse[^\r\n]*count=(\d+)[^\r\n]*addr=0x000000102A400000'
$allocMax=Get-MaxCounterV74027 -Text $combinedFinal -Pattern 'alloc2s_mb=(\d+)'
$naturalMatches=[regex]::Matches($combinedFinal,"bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+\.bk2)'")
$attachMatches=[regex]::Matches($combinedFinal,"(?:Bink RAD|Bink2 NIHAV) bridge attached:\s*([^\s']+\.bk2)")
$completeMatches=[regex]::Matches($combinedFinal,"(?:Bink RAD|Bink2 NIHAV) bridge completed:\s*([^\s']+\.bk2)")
$deviceLost=([regex]::Matches($combinedFinal,'(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException')).Count
$heapCorruption=([regex]::Matches($combinedFinal,'(?i)HEAP_CORRUPTION|0xC0000374')).Count
$firstFrameMatches=[regex]::Matches($combinedFinal,'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)')
$firstFrameSize=if($firstFrameMatches.Count -gt 0){$firstFrameMatches[0].Groups[1].Value}else{"none"}
$mainLoopMatches=[regex]::Matches($combinedFinal,'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s')
$mainLoopSeconds=if($mainLoopMatches.Count -gt 0){$mainLoopMatches[$mainLoopMatches.Count-1].Groups[1].Value}else{"not-observed"}
$gatherMatches=[regex]::Matches($combinedFinal,'ResourcePool::GatherResourceFileInfo\(\) took\s*([0-9]+(?:[.,][0-9]+)?)s')
$gatherSeconds=if($gatherMatches.Count -gt 0){$gatherMatches[$gatherMatches.Count-1].Groups[1].Value}else{"not-observed"}

$perfRows=@(Import-Csv -LiteralPath $perfPath)
[double]$peakWorking=0
[double]$peakPrivate=0
[double]$maxCpuPercent=0
[double]$sumCpuPercent=0
[double]$sumSteadyCpuPercent=0
[double]$maxCoreEquivalent=0
$cpuSamples=0
$steadyCpuSamples=0
foreach($perfRow in $perfRows){
    $workingValue=Convert-InvariantDoubleV74027 -Value $perfRow.working_mb
    $privateValue=Convert-InvariantDoubleV74027 -Value $perfRow.private_mb
    $cpuValue=Convert-InvariantDoubleV74027 -Value $perfRow.cpu_percent
    $coreValue=Convert-InvariantDoubleV74027 -Value $perfRow.cpu_core_equiv
    $elapsedValue=Convert-InvariantDoubleV74027 -Value $perfRow.elapsed_s
    if($workingValue -gt $peakWorking){$peakWorking=$workingValue}
    if($privateValue -gt $peakPrivate){$peakPrivate=$privateValue}
    if($cpuValue -gt $maxCpuPercent){$maxCpuPercent=$cpuValue}
    if($coreValue -gt $maxCoreEquivalent){$maxCoreEquivalent=$coreValue}
    if($elapsedValue -gt 2 -and [int]$perfRow.live_processes -gt 0){
        $sumCpuPercent += $cpuValue
        $cpuSamples++
        if($elapsedValue -ge 20){
            $sumSteadyCpuPercent += $cpuValue
            $steadyCpuSamples++
        }
    }
}
$averageCpuPercent=if($cpuSamples -gt 0){$sumCpuPercent/$cpuSamples}else{0}
$steadyCpuPercent=if($steadyCpuSamples -gt 0){$sumSteadyCpuPercent/$steadyCpuSamples}else{0}

$unknownDs76=([regex]::Matches($combinedFinal,'unknown-ds op=0x76')).Count
$unknownDs77=([regex]::Matches($combinedFinal,'unknown-ds op=0x77')).Count
$unknownDs78=([regex]::Matches($combinedFinal,'unknown-ds op=0x78')).Count
$unknownVop209=([regex]::Matches($combinedFinal,'unknown-vop2 op=0x09')).Count
$unknownVop20A=([regex]::Matches($combinedFinal,'unknown-vop2 op=0x0A')).Count
$compatShaderErrors=([regex]::Matches($combinedFinal,'\[COMPAT\]\[SHADER\][^\r\n]*error=')).Count
$firstMovieCompletionOffset=-1
$firstMovieCompleteMatch=[regex]::Match($combinedFinal,'Bink (?:RAD|NIHAV) bridge completed:\s*ps_studios_logo\.bk2')
if($firstMovieCompleteMatch.Success){$firstMovieCompletionOffset=$firstMovieCompleteMatch.Index}
$postFirstMovieShaderErrors=0
if($firstMovieCompletionOffset -ge 0){
    $postText=$combinedFinal.Substring($firstMovieCompletionOffset)
    $postFirstMovieShaderErrors=([regex]::Matches($postText,'\[COMPAT\]\[SHADER\][^\r\n]*error=')).Count
}

$classification="shader-isa-test-complete"
if($deviceLost -gt 0){$classification="device-lost"}
elseif($naturalMatches.Count -gt 0 -and $unknownDs76 -eq 0 -and $unknownDs77 -eq 0 -and $unknownDs78 -eq 0 -and $unknownVop209 -eq 0 -and $unknownVop20A -eq 0 -and $postFirstMovieShaderErrors -eq 0){$classification="shader-isa-target-errors-cleared-postmovie-clean"}
elseif($naturalMatches.Count -gt 0 -and $unknownDs76 -eq 0 -and $unknownDs77 -eq 0 -and $unknownDs78 -eq 0 -and $unknownVop209 -eq 0 -and $unknownVop20A -eq 0){$classification="shader-isa-target-errors-cleared-other-shader-errors-remain"}
elseif($naturalMatches.Count -gt 0){$classification="shader-isa-natural-boot-progressed"}
elseif($resumedLabels.Count -ge 5){$classification="shader-isa-waits-recovered-awaiting-natural-movie"}
elseif($resumeMax -gt 0){$classification="shader-isa-partial-wait-recovery"}

$naturalFiles=@($naturalMatches|ForEach-Object{$_.Groups[1].Value})
$attachedFiles=@($attachMatches|ForEach-Object{$_.Groups[1].Value})
$completedFiles=@($completeMatches|ForEach-Object{$_.Groups[1].Value})
$summaryLines=@(
    "VERSION=74.0.27",
    "WALL_SECONDS=$([Math]::Round($runStopwatch.Elapsed.TotalSeconds,2))",
    "RUNNER_FORCED_STOP=False",
    "LAUNCHER_EXIT_CODE=$launcherExitCode",
    "CLASSIFICATION=$classification",
    "EBOOT_SHA256=$actualEboot",
    "PROCESSOR_COUNT=$processorCount",
    "SOURCE_DEFAULT_RESERVED_LANES=$defaultReserved",
    "SOURCE_DEFAULT_USABLE_LANES=$($processorCount-$defaultReserved)",
    "TEST_RESERVED_LANES=$testReserved",
    "TEST_USABLE_LANES=$testUsable",
    "BPE_CPU0_12_UNIQUE_HOST_LANES=$($uniqueBpeLanes.Count)",
    "BPE_CPU0_12_MAP=$([string]::Join(',',@($bpeMap)))",
    "HIGHGRAPHICS_HOST_LANES=$rendererCpu9,$rendererCpu11",
    "WRITE_DATA_PACKET_POSITION_MAX_COUNTER=$writeMax",
    "WAIT_RESUME_MAX_COUNTER=$resumeMax",
    "WAIT_RESUME_SAMPLES_LOGGED=$($waitLatency.Count)",
    "WAIT_RESUME_MAX_MS=$([Math]::Round($waitLatency.MaxMs,3))",
    "WAIT_RESUME_AVG_MS=$([Math]::Round($waitLatency.AverageMs,3))",
    "WAIT_RESUME_GT_1000MS=$($waitLatency.Gt1000)",
    "WAIT_RESUME_GT_4000MS=$($waitLatency.Gt4000)",
    "STARTUP_LABEL_RESUMED_COUNT=$($resumedLabels.Count)",
    "STARTUP_LABELS_RESUMED=$([string]::Join(',',@($resumedLabels)))",
    "PARSER_ESCAPE_LAST_WAITERS=$parserWaitersLast",
    "ORDERED_ACTION_FENCE_WAIT_MAX_COUNTER=$fenceWaitMax",
    "STALE_CHANGED_TOTAL=$staleChangedTotal",
    "ARRAY_102A4_MISSING_BASELINE_STALE_LOGS=$arrayStale",
    "ARRAY_102A4_REFRESH_LOGS=$arrayRefresh",
    "ARRAY_SINGLEFLIGHT_OWNER_MAX=$arrayOwnerMax",
    "ARRAY_SINGLEFLIGHT_REUSE_MAX=$arrayReuseMax",
    "MAX_ALLOC2S_MB=$allocMax",
    "PEAK_TREE_WORKING_MB=$([Math]::Round($peakWorking,1))",
    "PEAK_TREE_PRIVATE_MB=$([Math]::Round($peakPrivate,1))",
    "AVG_TREE_CPU_PERCENT=$([Math]::Round($averageCpuPercent,2))",
    "STEADY_TREE_CPU_PERCENT_AFTER_20S=$([Math]::Round($steadyCpuPercent,2))",
    "MAX_TREE_CPU_PERCENT=$([Math]::Round($maxCpuPercent,2))",
    "MAX_TREE_CPU_CORE_EQUIV=$([Math]::Round($maxCoreEquivalent,2))",
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
    "UNKNOWN_DS_0X76=$unknownDs76",
    "UNKNOWN_DS_0X77=$unknownDs77",
    "UNKNOWN_DS_0X78=$unknownDs78",
    "UNKNOWN_VOP2_0X09=$unknownVop209",
    "UNKNOWN_VOP2_0X0A=$unknownVop20A",
    "COMPAT_SHADER_ERRORS_TOTAL=$compatShaderErrors",
    "POST_FIRST_MOVIE_SHADER_ERRORS=$postFirstMovieShaderErrors",
    "HOST_AUTO_BOOT=OFF",
    "WRITE_DATA_LABEL_FORCE=False",
    "SOURCE_CHANGED_BY_V74027=True"
)
[System.IO.File]::WriteAllLines($summaryPath,$summaryLines)

$zipPath=$outputDirectory+".zip"
if([System.IO.File]::Exists($zipPath)){Remove-Item -LiteralPath $zipPath -Force}
Compress-Archive -Path ([System.IO.Path]::Combine($outputDirectory,"*")) -DestinationPath $zipPath -CompressionLevel Optimal -Force
Write-Host "[V74.0.27] RESULT: $classification"
Write-Host ([string]::Format(
    [Globalization.CultureInfo]::InvariantCulture,
    "[V74.0.27] lanes={0}/{1} wait_max={2:F1}ms >1s={3} >4s={4} cpu_avg={5:F1}% cpu_steady={6:F1}% peak_work={7:F0}MB natural={8}",
    $testUsable,$processorCount,$waitLatency.MaxMs,$waitLatency.Gt1000,$waitLatency.Gt4000,$averageCpuPercent,$steadyCpuPercent,$peakWorking,$naturalMatches.Count))
Write-Host "[V74.0.27] Result ZIP: $zipPath"
