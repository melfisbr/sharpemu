param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74015 $RepositoryRoot
if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.16] EBOOT not found: $Eboot"
}

$releaseDll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
$debugDll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")

$runtimeConfig="Release"
$dll=$releaseDll
if(-not [System.IO.File]::Exists($dll)){
    $runtimeConfig="Debug"
    $dll=$debugDll
}
if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.16] SharpEmu.dll not found in Release or Debug win-x64."
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_16_DCC_HISTORY_FASTBOOT_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$perfCsv=[System.IO.Path]::Combine($out,"FASTBOOT_TREE_PERF.csv")
$milestones=[System.IO.Path]::Combine($out,"MILESTONES.txt")
$summary=[System.IO.Path]::Combine($out,"SUMMARY.txt")
$profile=[System.IO.Path]::Combine($out,"RUNTIME_PROFILE.txt")

[System.IO.File]::WriteAllText(
    $perfCsv,
    "elapsed_s;processes;largest_pid;working_mb;private_mb;cpu_pct;stderr_mb`r`n",
    [System.Text.Encoding]::ASCII)

$variables=@(
    "SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT",
    "SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT",
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_BINK_STARTUP_COMPLETION_SHIM",
    "SHARPEMU_RENDER_SCALE",
    "SHARPEMU_GPU_DETILE",
    "SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB",
    "SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB",
    "SHARPEMU_VK_GUEST_BUFFER_CACHE_MB",
    "SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB",
    "SHARPEMU_LOG_GUEST_THREADS",
    "SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS",
    "SHARPEMU_PROFILE_GPU_WAIT",
    "SHARPEMU_LOG_DIRECT_MEMORY",
    "SHARPEMU_LOG_VMEM",
    "SHARPEMU_LOG_VIRTUAL_MEMORY",
    "SHARPEMU_LOG_LAZY_COMMIT",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT",
    "SHARPEMU_TRACE_RENDER_TARGET_ADDRESS",
    "SHARPEMU_LOG_AGC_SHADER",
    "SHARPEMU_TRACE_DCC_ALIAS",
    "SHARPEMU_TRACE_SCANOUT_LINEAGE",
    "SHARPEMU_TRACE_RESOURCE_DEPENDENCIES",
    "SHARPEMU_LOG_VK_RESOURCES",
    "SHARPEMU_LOG_VK_COMPUTE_RESOURCES",
    "SHARPEMU_TRACE_MOVIE_IO",
    "SHARPEMU_LOG_VIDEOOUT_FPS",
    "SHARPEMU_OVERLAY",
    "SHARPEMU_PERF_MEM",
    "SHARPEMU_PROFILE_RENDER",
    "SHARPEMU_TRACE_DRAWS",
    "SHARPEMU_TRACE_GUEST_IMAGES",
    "SHARPEMU_TRACE_GUEST_IMAGE_EVENTS",
    "SHARPEMU_TRACE_GUEST_WORK_COMPLETION",
    "SHARPEMU_TRACE_ORDERED_ACTION_LATENCY",
    "SHARPEMU_TRACE_RENDER_WORK",
    "SHARPEMU_LOG_AGC",
    "SHARPEMU_LOG_PTHREADS",
    "SHARPEMU_LOG_PTHREAD_CALLSITES",
    "SHARPEMU_LOG_PTHREAD_FASTPATH",
    "SHARPEMU_LOG_ALL_IMPORTS",
    "SHARPEMU_LOG_IMPORT_PERIODIC",
    "SHARPEMU_LOG_EXPECTED_IMPORT_RESULTS",
    "SHARPEMU_DCC_ALIAS_HISTORY_MS",
    "SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS"
)

$oldEnvironment=@{}
foreach($name in $variables){
    $oldEnvironment[$name]=[Environment]::GetEnvironmentVariable(
        $name,[EnvironmentVariableTarget]::Process)
}

$started=[DateTime]::UtcNow
$absoluteDeadline=$started.AddSeconds(600)
$deadline=$started.AddSeconds(300)
$nextStatus=$started
$logOffset=[int64]0
$lineCarry=""
$launcher=$null
$previousTreeCpu=0.0
$previousCpuAt=$started
$zeroProcessSamples=0
$peakTreeWorking=[int64]0
$peakTreePrivate=[int64]0
$maxProcessCount=0
$firstNaturalAt=$null
$firstCompleteAt=$null
$secondNaturalAt=$null
$secondCompleteAt=$null
$mainLoopAt=$null
$observedTbbLimit=-1
$tbbMismatch=$false
$liveDeviceLost=$false
$liveHeapCorruption=$false
$runFailure=""

try{
    $env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    $env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"

    $env:SHARPEMU_BINK_AUTO_BOOT="0"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="900000"
    $env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"

    # V74.0.15 keeps the stable 768MB Vulkan texture cache that removed the
    # V74.0.13.2 device-loss regression. The source patch coalesces concurrent
    # 320MB-class array snapshots; render_scale=0.25 is diagnostic-only and
    # reduces non-storage guest render-target pixel pressure for this run.
    $env:SHARPEMU_RENDER_SCALE="0.25"
    $env:SHARPEMU_GPU_DETILE="1"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="256"
    $env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    $env:SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="192"
    $env:SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB="384"

    $env:SHARPEMU_LOG_GUEST_THREADS="0"
    $env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS="0"
    $env:SHARPEMU_PROFILE_GPU_WAIT="0"
    $env:SHARPEMU_LOG_DIRECT_MEMORY="0"
    $env:SHARPEMU_LOG_VMEM="0"
    $env:SHARPEMU_LOG_VIRTUAL_MEMORY="0"
    $env:SHARPEMU_LOG_LAZY_COMMIT="0"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="0"
    $env:SHARPEMU_TRACE_RENDER_TARGET_ADDRESS="0"
    $env:SHARPEMU_LOG_AGC_SHADER="0"
    $env:SHARPEMU_TRACE_DCC_ALIAS="1"
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE="0"
    $env:SHARPEMU_TRACE_RESOURCE_DEPENDENCIES="0"
    $env:SHARPEMU_LOG_VK_RESOURCES="0"
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES="0"
    $env:SHARPEMU_TRACE_MOVIE_IO="0"
    $env:SHARPEMU_LOG_VIDEOOUT_FPS="0"
    $env:SHARPEMU_OVERLAY="0"
    $env:SHARPEMU_PERF_MEM="0"
    $env:SHARPEMU_PROFILE_RENDER="0"
    $env:SHARPEMU_TRACE_DRAWS="0"
    $env:SHARPEMU_TRACE_GUEST_IMAGES="0"
    $env:SHARPEMU_TRACE_GUEST_IMAGE_EVENTS="0"
    $env:SHARPEMU_TRACE_GUEST_WORK_COMPLETION="0"
    $env:SHARPEMU_TRACE_ORDERED_ACTION_LATENCY="0"
    $env:SHARPEMU_TRACE_RENDER_WORK="0"
    $env:SHARPEMU_LOG_AGC="0"
    $env:SHARPEMU_LOG_PTHREADS="0"
    $env:SHARPEMU_LOG_PTHREAD_CALLSITES="0"
    $env:SHARPEMU_LOG_PTHREAD_FASTPATH="0"
    $env:SHARPEMU_LOG_ALL_IMPORTS="0"
    $env:SHARPEMU_LOG_IMPORT_PERIODIC="0"
    $env:SHARPEMU_LOG_EXPECTED_IMPORT_RESULTS="0"
    $env:SHARPEMU_DCC_ALIAS_HISTORY_MS="2000"
    $env:SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS="10000"

    $profileLines=@(
        "version=74.0.16",
        "runtime=$runtimeConfig",
        "render_scale=0.25",
        "native_worker_max_concurrent=2",
        "renderer_resource_native_max_concurrent=8",
        "sampled_guest_image_cache_mb=256",
        "standalone_texture_cache_mb=768",
        "guest_buffer_cache_mb=192",
        "device_buffer_cache_mb=384",
        "bink_auto_boot=0",
        "startup_completion_shim=1",
        "gpu_detile=1",
        "process_telemetry=aggregate_process_tree",
        "dcc_alias_history_ms=2000",
        "large_snapshot_reuse_ms=10000"
    )
    [System.IO.File]::WriteAllLines(
        $profile,$profileLines,[System.Text.UTF8Encoding]::new($true))

    Write-Host "[V74.0.16] DCC HISTORY / FASTBOOT run starting."
    Write-Host "[V74.0.16] Runtime=$runtimeConfig render_scale=0.25 GPU_DETILE=1"
    Write-Host "[V74.0.16] Native limits: TBB=2 renderer/resource=8"
    Write-Host "[V74.0.16] Cache MB: sampled=256 texture=768 guest=192 device=384"
    Write-Host "[V74.0.16] Telemetry follows the full dotnet/mitigated-child process tree."
    Write-Host "[V74.0.16] Result folder: $out"

    $dotnetArgumentLine='"{0}" "{1}"' -f $dll,$Eboot
    $launcher=Start-Process `
        -FilePath "dotnet" `
        -ArgumentList $dotnetArgumentLine `
        -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    while([DateTime]::UtcNow -lt $deadline){
        Start-Sleep -Seconds 5
        $now=[DateTime]::UtcNow
        $elapsed=($now-$started).TotalSeconds

        $sample=Get-ProcessTreeSampleV74015 -RootProcessId $launcher.Id
        $working=[int64]$sample.WorkingBytes
        $private=[int64]$sample.PrivateBytes
        $treeCpu=[double]$sample.CpuSeconds

        $sampleSeconds=[Math]::Max(($now-$previousCpuAt).TotalSeconds,0.001)
        $cpuDelta=[Math]::Max(0.0,$treeCpu-$previousTreeCpu)
        $cpuPct=($cpuDelta/$sampleSeconds) /
            [Math]::Max([Environment]::ProcessorCount,1) * 100.0
        $previousTreeCpu=$treeCpu
        $previousCpuAt=$now

        if($sample.LiveCount -eq 0){
            $zeroProcessSamples++
        }
        else{
            $zeroProcessSamples=0
        }

        $peakTreeWorking=[Math]::Max($peakTreeWorking,$working)
        $peakTreePrivate=[Math]::Max($peakTreePrivate,$private)
        $maxProcessCount=[Math]::Max($maxProcessCount,[int]$sample.LiveCount)

        $logMb=0.0
        if([System.IO.File]::Exists($stderr)){
            $logMb=(Get-Item -LiteralPath $stderr).Length/1MB
        }

        ("{0:F1};{1};{2};{3:F1};{4:F1};{5:F1};{6:F1}" -f
            $elapsed,
            $sample.LiveCount,
            $sample.LargestProcessId,
            ($working/1MB),
            ($private/1MB),
            $cpuPct,
            $logMb) |
            Add-Content -LiteralPath $perfCsv -Encoding ASCII

        $chunk=Read-NewSharedChunkV74015 -Path $stderr -Offset ([ref]$logOffset)
        if(-not [string]::IsNullOrEmpty($chunk)){
            $scan=$lineCarry+$chunk
            $completeLines=[regex]::Split($scan,"\r?\n")
            $endsWithNewLine=$scan.EndsWith("`n")
            if($endsWithNewLine){
                $lineCarry=""
                $lineLimit=$completeLines.Count
            }
            else{
                $lineCarry=$completeLines[$completeLines.Count-1]
                $lineLimit=$completeLines.Count-1
            }

            for($lineIndex=0;$lineIndex -lt $lineLimit;$lineIndex++){
                $line=$completeLines[$lineIndex]
                if([string]::IsNullOrEmpty($line)){continue}

                if($null -eq $mainLoopAt -and
                   $line -match '\[MSG-Init\] Starting main loop:'){
                    $mainLoopAt=$now
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s main_loop {1}" -f $elapsed,$line)
                    Write-Host "[V74.0.16] main loop reached at $([Math]::Round($elapsed,1))s."
                }

                if($line -match '\[V74\.0\.10\]\[NATIVE_LANE\].*tbb_limit=(\d+)'){
                    $limitValue=[int]$Matches[1]
                    if($observedTbbLimit -lt 0){
                        $observedTbbLimit=$limitValue
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                            "{0:F1}s observed_tbb_limit={1}" -f $elapsed,$limitValue)
                        Write-Host "[V74.0.16] runtime reports tbb_limit=$limitValue."
                        if($limitValue -ne 2){
                            $tbbMismatch=$true
                            Write-Host "[V74.0.16] ERROR: runtime limiter mismatch; stopping before another high-load run."
                        }
                    }
                }

                if($line -match 'TEX_CACHE\] add addr=0x000000102A400000'){
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s large_array_320mb {1}" -f $elapsed,$line)
                }

                if($line -match '\[V74\.0\.15\]\[ARRAY_SINGLEFLIGHT\] (owner|reuse)'){
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s array_singleflight {1}" -f $elapsed,$line)
                }

                if($line -match 'TEX_CACHE\] trim'){
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s texture_cache_trim {1}" -f $elapsed,$line)
                }

                if($line -match "bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'"){
                    $movieFile=$Matches[1]
                    if($null -eq $firstNaturalAt){
                        $firstNaturalAt=$now
                        $candidate=Bound-DeadlineV74015 -Candidate $now.AddSeconds(240) -Absolute $absoluteDeadline
                        if($candidate -gt $deadline){$deadline=$candidate}
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                            "{0:F1}s natural_1 {1}" -f $elapsed,$movieFile)
                        Write-Host "[V74.0.16] natural movie #1 at $([Math]::Round($elapsed,1))s: $movieFile"
                    }
                    elseif($null -eq $secondNaturalAt -and
                           [System.IO.Path]::GetFileName($movieFile) -ne "ps_studios_logo.bk2"){
                        $secondNaturalAt=$now
                        $candidate=Bound-DeadlineV74015 -Candidate $now.AddSeconds(180) -Absolute $absoluteDeadline
                        if($candidate -gt $deadline){$deadline=$candidate}
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                            "{0:F1}s natural_2 {1}" -f $elapsed,$movieFile)
                        Write-Host "[V74.0.16] natural movie #2 at $([Math]::Round($elapsed,1))s: $movieFile"
                    }
                }

                if($line -match 'Bink2 bridge completed:'){
                    if($null -eq $firstCompleteAt){
                        $firstCompleteAt=$now
                        $candidate=Bound-DeadlineV74015 -Candidate $now.AddSeconds(240) -Absolute $absoluteDeadline
                        if($candidate -gt $deadline){$deadline=$candidate}
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                            "{0:F1}s completed_1 {1}" -f $elapsed,$line)
                        Write-Host "[V74.0.16] startup movie #1 completed at $([Math]::Round($elapsed,1))s."
                    }
                    elseif($null -eq $secondCompleteAt){
                        $secondCompleteAt=$now
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                            "{0:F1}s completed_2 {1}" -f $elapsed,$line)
                    }
                }

                if($line -match '(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException'){
                    $liveDeviceLost=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s DEVICE_LOST {1}" -f $elapsed,$line)
                }

                if($line -match '(?i)HEAP_CORRUPTION|0xC0000374'){
                    $liveHeapCorruption=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value (
                        "{0:F1}s HEAP_CORRUPTION {1}" -f $elapsed,$line)
                }
            }
        }

        if($now -ge $nextStatus){
            $statusFormat=
                "[V74.0.16] t={0:F0}s procs={1} work={2:F0}MB private={3:F0}MB cpu={4:F0}% " +
                "largest_pid={5} tbb={6} natural={7}/{8} complete={9}/{10}"
            $statusArguments=[object[]]@(
                [double]$elapsed,
                [int]$sample.LiveCount,
                [double]($working/1MB),
                [double]($private/1MB),
                [double]$cpuPct,
                [int]$sample.LargestProcessId,
                [int]$observedTbbLimit,
                [bool]($null -ne $firstNaturalAt),
                [bool]($null -ne $secondNaturalAt),
                [bool]($null -ne $firstCompleteAt),
                [bool]($null -ne $secondCompleteAt))
            $statusLine=[string]::Format(
                [System.Globalization.CultureInfo]::InvariantCulture,
                $statusFormat,
                $statusArguments)
            Write-Host $statusLine
            $nextStatus=$now.AddSeconds(10)
        }

        if($tbbMismatch -or $liveDeviceLost -or $liveHeapCorruption){
            break
        }
        if($zeroProcessSamples -ge 3 -and $elapsed -gt 10){
            break
        }
    }
}
catch{
    $runFailure=$_.Exception.Message
    Write-Host "[V74.0.16] Runner exception: $runFailure"
}
finally{
    if($null -ne $launcher){
        $remaining=Get-ProcessTreeSampleV74015 -RootProcessId $launcher.Id
        if($remaining.LiveCount -gt 0){
            Stop-ProcessTreeV74015 -RootProcessId $launcher.Id
            Start-Sleep -Milliseconds 700
        }
    }

    foreach($name in $variables){
        $previousValue=$oldEnvironment[$name]
        if($null -eq $previousValue){
            [Environment]::SetEnvironmentVariable(
                $name,$null,[EnvironmentVariableTarget]::Process)
        }
        else{
            [Environment]::SetEnvironmentVariable(
                $name,[string]$previousValue,[EnvironmentVariableTarget]::Process)
        }
    }
}

$finalText=Read-SharedTextV74015 -Path $stderr
$stdoutText=Read-SharedTextV74015 -Path $stdout

$naturalMatches=[regex]::Matches(
    $finalText,
    "bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'")
$completionMatches=[regex]::Matches($finalText,'Bink2 bridge completed:')
$handoffMatches=[regex]::Matches(
    $finalText,
    'bink2\.startup_completion_shim|startup_completion_shim_header_fallback')
$fallbackStartMatches=[regex]::Matches(
    $finalText,
    'bink2\.descriptorless_direct_fallback_start')
$fallbackEndMatches=[regex]::Matches(
    $finalText,
    'bink2\.descriptorless_direct_fallback_end')
$trimMatches=[regex]::Matches($finalText,'\[V74\.0\.8\]\[TEX_CACHE\] trim')
$largeArrayMatches=[regex]::Matches(
    $finalText,
    'TEX_CACHE\] add addr=0x000000102A400000[^\r\n]*bytes=335544320')
$deviceLostMatches=[regex]::Matches(
    $finalText,
    '(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException')
$heapCorruptionMatches=[regex]::Matches(
    $finalText,
    '(?i)HEAP_CORRUPTION|0xC0000374')
$tbbMatches=[regex]::Matches(
    $finalText,
    '\[V74\.0\.10\]\[NATIVE_LANE\][^\r\n]*tbb_limit=(\d+)')
$singleFlightOwnerMatches=[regex]::Matches(
    $finalText,
    '\[V74\.0\.15\]\[ARRAY_SINGLEFLIGHT\] owner')
$singleFlightReuseMatches=[regex]::Matches(
    $finalText,
    '\[V74\.0\.15\]\[ARRAY_SINGLEFLIGHT\] reuse')
$allocBurstMatches=[regex]::Matches(
    $finalText,
    '\[V74\.0\.8\.1\]\[MEM\][^\r\n]*alloc2s_mb=(\d+)')
$dccHistorySeedMatches=[regex]::Matches($finalText,'\[V74\.0\.16\]\[DCC_HISTORY\] seed')
$dccHistoryHitMatches=[regex]::Matches($finalText,'\[V74\.0\.16\]\[DCC_HISTORY\] hit')
$dccUnresolvedMatches=[regex]::Matches($finalText,'unresolved_dcc_cpu_snapshot_suppressed')
$dccAliasHitMatches=[regex]::Matches($finalText,'agc\.texture_dcc_alias_hit')
$largeSnapshotAllocMatches=[regex]::Matches($finalText,'large_texture_cpu_snapshot')
$largeSnapshotReuseMatches=[regex]::Matches($finalText,'large_texture_snapshot_reuse')
$maxAlloc2sMb=0
foreach($allocBurstMatch in $allocBurstMatches){
    $alloc2sValue=[int]$allocBurstMatch.Groups[1].Value
    if($alloc2sValue -gt $maxAlloc2sMb){$maxAlloc2sMb=$alloc2sValue}
}

$finalObservedTbb=-1
if($tbbMatches.Count -gt 0){
    $finalObservedTbb=[int]$tbbMatches[0].Groups[1].Value
}

$runtimePeakWorking=0
$runtimePeakPrivate=0
foreach($memoryMatch in [regex]::Matches(
    $finalText,
    '\[V74\.0\.8\.1\]\[MEM\][^\r\n]*working_mb=(\d+)[^\r\n]*private_mb=(\d+)')){
    $runtimeWorking=[int]$memoryMatch.Groups[1].Value
    $runtimePrivate=[int]$memoryMatch.Groups[2].Value
    if($runtimeWorking -gt $runtimePeakWorking){$runtimePeakWorking=$runtimeWorking}
    if($runtimePrivate -gt $runtimePeakPrivate){$runtimePeakPrivate=$runtimePrivate}
}

$movieNames=New-Object 'System.Collections.Generic.List[string]'
foreach($naturalMatch in $naturalMatches){
    $movieName=$naturalMatch.Groups[1].Value
    if(-not $movieNames.Contains($movieName)){
        $movieNames.Add($movieName)
    }
}

$classification="fastboot-no-natural-movie"
if($deviceLostMatches.Count -gt 0 -and $heapCorruptionMatches.Count -gt 0){
    $classification="vulkan-device-lost-heap-corruption"
}
elseif($deviceLostMatches.Count -gt 0){
    $classification="vulkan-device-lost"
}
elseif($finalObservedTbb -ge 0 -and $finalObservedTbb -ne 2){
    $classification="native-tbb-limiter-mismatch"
}
elseif($naturalMatches.Count -ge 2){
    $classification="second-startup-movie-reached"
}
elseif($dccHistoryHitMatches.Count -gt 0){
    $classification="dcc-resident-alias-history-active-no-natural-movie"
}
elseif($singleFlightReuseMatches.Count -gt 0){
    $classification="large-array-singleflight-active-no-natural-movie"
}
elseif($naturalMatches.Count -ge 1 -and
       $completionMatches.Count -ge 1 -and
       $handoffMatches.Count -ge 1){
    $classification="first-startup-handoff-completed"
}
elseif($naturalMatches.Count -ge 1 -and $completionMatches.Count -ge 1){
    $classification="first-startup-movie-completed"
}
elseif($naturalMatches.Count -ge 1){
    $classification="first-startup-movie-reached"
}

$mainLoopSeconds=""
$mainLoopMatch=[regex]::Match(
    $stdoutText,
    '\[MSG-Init\] Starting main loop:\s*([0-9]+(?:[\.,][0-9]+)?)s')
if($mainLoopMatch.Success){
    $mainLoopSeconds=$mainLoopMatch.Groups[1].Value
}

$summaryLines=@(
    "version=74.0.16",
    "classification=$classification",
    "runtime=$runtimeConfig",
    "run_failure=$runFailure",
    "",
    "[verified-runtime-profile]",
    "render_scale=0.25",
    "requested_tbb_limit=2",
    "observed_tbb_limit=$finalObservedTbb",
    "renderer_resource_limit=8",
    "standalone_texture_cache_mb=768",
    "sampled_cache_mb=256",
    "guest_buffer_cache_mb=192",
    "device_buffer_cache_mb=384",
    "",
    "[startup]",
    "main_loop_game_seconds=$mainLoopSeconds",
    "natural_movie_hits=$($naturalMatches.Count)",
    "natural_movie_files=$($movieNames -join ',')",
    "bridge_completed_hits=$($completionMatches.Count)",
    "startup_completion_handoff_hits=$($handoffMatches.Count)",
    "fallback_start_hits=$($fallbackStartMatches.Count)",
    "fallback_end_hits=$($fallbackEndMatches.Count)",
    "",
    "[memory-process-tree]",
    "peak_tree_working_mb=$([Math]::Round($peakTreeWorking/1MB,1))",
    "peak_tree_private_mb=$([Math]::Round($peakTreePrivate/1MB,1))",
    "max_live_processes=$maxProcessCount",
    "",
    "[memory-runtime-internal]",
    "peak_runtime_working_mb=$runtimePeakWorking",
    "peak_runtime_private_mb=$runtimePeakPrivate",
    "max_alloc2s_mb=$maxAlloc2sMb",
    "",
    "[large-array-singleflight]",
    "owner_hits=$($singleFlightOwnerMatches.Count)",
    "reuse_hits=$($singleFlightReuseMatches.Count)",
    "threshold_mb=64",
    "ttl_ms=500",
    "exact_layer_data=True",
    "",
    "[dcc-alias-history]",
    "ttl_ms=2000",
    "seed_hits=$($dccHistorySeedMatches.Count)",
    "history_hits=$($dccHistoryHitMatches.Count)",
    "normal_alias_hits=$($dccAliasHitMatches.Count)",
    "unresolved_dcc_suppressions=$($dccUnresolvedMatches.Count)",
    "",
    "[non-dcc-large-snapshot-reuse]",
    "ttl_ms=10000",
    "cpu_snapshot_alloc_hits=$($largeSnapshotAllocMatches.Count)",
    "snapshot_reuse_hits=$($largeSnapshotReuseMatches.Count)",
    "",
    "[vulkan-regression-guards]",
    "large_320mb_array_hits=$($largeArrayMatches.Count)",
    "texture_cache_trim_hits=$($trimMatches.Count)",
    "device_lost_hits=$($deviceLostMatches.Count)",
    "heap_corruption_hits=$($heapCorruptionMatches.Count)",
    "",
    "[runner-v74016]",
    "process_tree_telemetry=True",
    "shared_stderr_read=True",
    "device_lost_regex_expanded=True",
    "tbb_runtime_verification=True",
    "status_format_stringformat=True",
    "normal_result_zip=True"
)

[System.IO.File]::WriteAllLines(
    $summary,$summaryLines,[System.Text.UTF8Encoding]::new($true))

$zip=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_16_DCC_HISTORY_FASTBOOT_RESULT_$stamp.zip")
try{
    if([System.IO.File]::Exists($zip)){
        Remove-Item -LiteralPath $zip -Force
    }
    Compress-Archive -Path ([System.IO.Path]::Combine($out,"*")) -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "[V74.0.16] RESULT ZIP: $zip"
}
catch{
    Write-Host "[V74.0.16] RESULT ZIP FAILED: $($_.Exception.Message)"
    Write-Host "[V74.0.16] Result folder preserved: $out"
}

Write-Host "[V74.0.16] classification=$classification"
Write-Host "[V74.0.16] tbb requested/observed=2/$finalObservedTbb"
Write-Host "[V74.0.16] tree peak working/private=$([Math]::Round($peakTreeWorking/1MB,1))/$([Math]::Round($peakTreePrivate/1MB,1)) MB"
Write-Host "[V74.0.16] runtime peak working/private=$runtimePeakWorking/$runtimePeakPrivate MB"
Write-Host "[V74.0.16] natural=$($naturalMatches.Count) complete=$($completionMatches.Count) handoff=$($handoffMatches.Count)"
Write-Host "[V74.0.16] texture_trim=$($trimMatches.Count) device_lost=$($deviceLostMatches.Count) heap_corruption=$($heapCorruptionMatches.Count)"
Write-Host "[V74.0.16] array_singleflight owner/reuse=$($singleFlightOwnerMatches.Count)/$($singleFlightReuseMatches.Count) max_alloc2s_mb=$maxAlloc2sMb"
Write-Host "[V74.0.16] dcc history seed/hit=$($dccHistorySeedMatches.Count)/$($dccHistoryHitMatches.Count) unresolved=$($dccUnresolvedMatches.Count)"
Write-Host "[V74.0.16] non-DCC snapshot alloc/reuse=$($largeSnapshotAllocMatches.Count)/$($largeSnapshotReuseMatches.Count)"
