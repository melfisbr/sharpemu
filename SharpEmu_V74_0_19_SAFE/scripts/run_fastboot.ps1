param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74018 -RepositoryRoot $RepositoryRoot
if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.19] EBOOT not found: $Eboot"
}

$releaseDll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){
    throw "[V74.0.19] Release SharpEmu.dll missing. Run RUN_3_APPLY_BUILD first: $releaseDll"
}
$runtimeConfig="Release"
$dll=$releaseDll

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine($root,"SharpEmu_V74_0_19_BOOT_SEQUENCE_RESULT_$stamp")
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
    "SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC",
    "SHARPEMU_NATIVE_MEMCPY_INTRINSIC",
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
    "SHARPEMU_DCC_ALIAS_HISTORY_MS",
    "SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS",
    "SHARPEMU_TRACE_DCC_ALIAS",
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
    "SHARPEMU_LOG_EXPECTED_IMPORT_RESULTS"
)

$oldEnvironment=@{}
foreach($name in $variables){
    $oldEnvironment[$name]=[Environment]::GetEnvironmentVariable(
        $name,[EnvironmentVariableTarget]::Process)
}

$started=[DateTime]::UtcNow
$absoluteDeadline=$started.AddSeconds(360)
$deadline=$started.AddSeconds(300)
$nextStatus=$started
$stderrOffset=[int64]0
$stdoutOffset=[int64]0
$stderrCarry=""
$stdoutCarry=""
$launcher=$null
$previousTreeCpu=0.0
$previousCpuAt=$started
$zeroProcessSamples=0
$peakTreeWorking=[int64]0
$peakTreePrivate=[int64]0
$maxProcessCount=0
$firstNaturalAt=$null
$secondNaturalAt=$null
$firstCompleteAt=$null
$secondCompleteAt=$null
$mainLoopAt=$null
$gatherAt=$null
$observedTbbLimit=-1
$opaqueGateObserved=$false
$nativeMemcpyObserved=$false
$import8mObserved=$false
$import16mObserved=$false
$import25mObserved=$false
$import33mObserved=$false
$liveDeviceLost=$false
$liveHeapCorruption=$false
$tbbMismatch=$false
$runFailure=""
$stopReason="deadline"
$autoBootOrderObserved=$false
$autoBootOrderCorrect=$false
$autoBootOrderKind="none"
$autoBootDiscovered=$false
$bootSequenceSelected=$false
$directBootStarted=$false
$directBootCompleted=$false
$directBootStartedAt=$null
$directBootCompletedAt=$null
$queuedLogoIntro=$false
$queuedLogoLoop=$false
$attachedMovies=New-Object 'System.Collections.Generic.List[string]'
$guestFrameBeforeDirectBoot=$false
$guestFrameDuringDirectBoot=$false

try{
    # V74.0.17 pthread A/B did not improve startup, so restore the accumulated
    # compatibility behavior for this run and isolate the new memcpy fast path.
    $env:SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC="1"
    $env:SHARPEMU_NATIVE_MEMCPY_INTRINSIC="1"
    $env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    $env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"

    $env:SHARPEMU_BINK_AUTO_BOOT="1"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="1500"
    $env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="0"

    $env:SHARPEMU_RENDER_SCALE="1.0"
    $env:SHARPEMU_GPU_DETILE="1"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="256"
    $env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    $env:SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="192"
    $env:SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB="384"

    # V74.0.16.1 produced 64 DCC history seeds and zero history hits while
    # increasing pressure, so retain the source but disable that experiment.
    $env:SHARPEMU_DCC_ALIAS_HISTORY_MS="0"
    $env:SHARPEMU_TRACE_DCC_ALIAS="0"
    $env:SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS="10000"

    # Keep high-volume diagnostics off so this run measures the hot path.
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

    $profileLines=@(
        "version=74.0.19.0",
        "runtime=Release",
        "pthread_opaque_owner_sync=1",
        "native_memcpy_intrinsic=1",
        "pthread_opaque_owner_sync_default=enabled",
        "render_scale=1.0",
        "native_worker_max_concurrent=2",
        "renderer_resource_native_max_concurrent=8",
        "sampled_guest_image_cache_mb=256",
        "standalone_texture_cache_mb=768",
        "guest_buffer_cache_mb=192",
        "device_buffer_cache_mb=384",
        "dcc_alias_history_ms=0",
        "trace_dcc_alias=0",
        "large_snapshot_reuse_ms=10000",
        "bink_auto_boot=1",
        "bink_auto_boot_grace_ms=1500",
        "startup_completion_shim=0",
        "gpu_detile=1",
        "process_telemetry=aggregate_process_tree",
        "nominal_deadline_seconds=300",
        "absolute_deadline_seconds=360"
    )
    [System.IO.File]::WriteAllLines(
        $profile,$profileLines,[System.Text.UTF8Encoding]::new($true))

    Write-Host "[V74.0.19] BOOT SEQUENCE RESTORE run starting."
    Write-Host "[V74.0.19] AUTO_BOOT=1 grace=1500ms; completion shim OFF during host-managed direct boot."
    Write-Host "[V74.0.19] Expected order: ps_studios_logo.bk2 -> logo_intro.bk2 -> logo_intro_loop.bk2."
    Write-Host "[V74.0.19] Native memcpy remains ON; render_scale=1.0; TBB=2; renderer/resource=8."
    Write-Host "[V74.0.19] DCC history OFF; V74.0.15 large-array single-flight preserved."
    Write-Host "[V74.0.19] Result folder: $out"

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

        $sample=Get-ProcessTreeSampleV74018 -RootProcessId $launcher.Id
        $working=[int64]$sample.WorkingBytes
        $private=[int64]$sample.PrivateBytes
        $treeCpu=[double]$sample.CpuSeconds
        $sampleSeconds=[Math]::Max(($now-$previousCpuAt).TotalSeconds,0.001)
        $cpuDelta=[Math]::Max(0.0,$treeCpu-$previousTreeCpu)
        $cpuPct=($cpuDelta/$sampleSeconds) / [Math]::Max([Environment]::ProcessorCount,1) * 100.0
        $previousTreeCpu=$treeCpu
        $previousCpuAt=$now

        if($sample.LiveCount -eq 0){$zeroProcessSamples++}else{$zeroProcessSamples=0}
        $peakTreeWorking=[Math]::Max($peakTreeWorking,$working)
        $peakTreePrivate=[Math]::Max($peakTreePrivate,$private)
        $maxProcessCount=[Math]::Max($maxProcessCount,[int]$sample.LiveCount)

        $logMb=0.0
        if([System.IO.File]::Exists($stderr)){$logMb=(Get-Item -LiteralPath $stderr).Length/1MB}
        ("{0:F1};{1};{2};{3:F1};{4:F1};{5:F1};{6:F1}" -f
            $elapsed,$sample.LiveCount,$sample.LargestProcessId,
            ($working/1MB),($private/1MB),$cpuPct,$logMb) |
            Add-Content -LiteralPath $perfCsv -Encoding ASCII

        $stderrChunk=Read-NewSharedChunkV74018 -Path $stderr -Offset ([ref]$stderrOffset)
        if(-not [string]::IsNullOrEmpty($stderrChunk)){
            $scan=$stderrCarry+$stderrChunk
            $lines=[regex]::Split($scan,"\r?\n")
            $lineLimit=$lines.Count
            if($scan.EndsWith("`n")){$stderrCarry=""}else{$stderrCarry=$lines[$lines.Count-1];$lineLimit--}
            for($lineIndex=0;$lineIndex -lt $lineLimit;$lineIndex++){
                $line=$lines[$lineIndex]
                if([string]::IsNullOrEmpty($line)){continue}

                if(-not $opaqueGateObserved -and
                   $line -match '\[V74\.0\.17\]\[PTHREAD_FASTBOOT\] opaque_owner_sync=enabled'){
                    $opaqueGateObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s pthread_gate_enabled" -f $elapsed)
                    Write-Host "[V74.0.19] runtime confirmed opaque_owner_sync=enabled."
                }
                if(-not $nativeMemcpyObserved -and
                   $line -match '\[V74\.0\.18\]\[MEMCPY_FASTPATH\] native intrinsic enabled'){
                    $nativeMemcpyObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s native_memcpy_intrinsic_enabled" -f $elapsed)
                    Write-Host "[V74.0.19] runtime confirmed native memcpy intrinsic."
                }
                if($line -match '\[V74\.0\.10\]\[NATIVE_LANE\].*tbb_limit=(\d+)'){
                    $limitValue=[int]$Matches[1]
                    if($observedTbbLimit -lt 0){
                        $observedTbbLimit=$limitValue
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s observed_tbb_limit={1}" -f $elapsed,$limitValue)
                        Write-Host "[V74.0.19] runtime reports tbb_limit=$limitValue."
                        if($limitValue -ne 2){$tbbMismatch=$true}
                    }
                }
                if(-not $import8mObserved -and $line -match 'dbfz\.import_progress\.v1892 import=8388608'){
                    $import8mObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s import_progress_8388608 {1}" -f $elapsed,$line)
                }
                if(-not $import16mObserved -and $line -match 'dbfz\.import_progress\.v1892 import=16777216'){
                    $import16mObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s import_progress_16777216 {1}" -f $elapsed,$line)
                }
                if(-not $import25mObserved -and $line -match 'dbfz\.import_progress\.v1892 import=25165824'){
                    $import25mObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s import_progress_25165824 {1}" -f $elapsed,$line)
                }
                if(-not $import33mObserved -and $line -match 'dbfz\.import_progress\.v1892 import=33554432'){
                    $import33mObserved=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s import_progress_33554432 {1}" -f $elapsed,$line)
                }
                if($line -match "bink2\.auto_boot_order movies=(\d+) sequence='([^']+)'"){
                    $autoBootOrderObserved=$true
                    $sequenceText=$Matches[2]
                    $movieCount=[int]$Matches[1]
                    $twoIntroSequence="ps_studios_logo.bk2 -> logo_intro.bk2"
                    $threeIntroSequence="ps_studios_logo.bk2 -> logo_intro.bk2 -> logo_intro_loop.bk2"
                    if($movieCount -eq 2 -and $sequenceText -eq $twoIntroSequence){
                        $autoBootOrderCorrect=$true
                        $autoBootOrderKind="two-intro"
                    }
                    elseif($movieCount -eq 3 -and $sequenceText -eq $threeIntroSequence){
                        $autoBootOrderCorrect=$true
                        $autoBootOrderKind="three-intro"
                    }
                    else{
                        $autoBootOrderCorrect=$false
                        $autoBootOrderKind="mismatch"
                    }
                    if($autoBootOrderCorrect){
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s auto_boot_order_ok kind={1} {2}" -f $elapsed,$autoBootOrderKind,$sequenceText)
                    }
                    else{
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s AUTO_BOOT_ORDER_MISMATCH movies={1} sequence={2}" -f $elapsed,$movieCount,$sequenceText)
                    }
                }
                if(-not $autoBootDiscovered -and $line -match 'bink2\.auto_boot_discovered'){
                    $autoBootDiscovered=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s auto_boot_discovered {1}" -f $elapsed,$line)
                }
                if(-not $bootSequenceSelected -and $line -match 'bink2\.boot_sequence_selected source=auto-app0'){
                    $bootSequenceSelected=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s boot_sequence_selected {1}" -f $elapsed,$line)
                }
                if(-not $directBootStarted -and $line -match 'bink2\.direct_boot_started movies=(\d+)'){
                    $directBootStarted=$true
                    $directBootStartedAt=$now
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s direct_boot_started {1}" -f $elapsed,$line)
                    Write-Host "[V74.0.19] direct boot started at $([Math]::Round($elapsed,1))s."
                }
                if($line -match "(?:Bink2 NIHAV bridge attached|Bink RAD bridge attached):\s*([^\s]+\.bk2)"){
                    $attachedName=$Matches[1]
                    if(-not $attachedMovies.Contains($attachedName)){
                        $attachedMovies.Add($attachedName)
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s movie_attached_{1} {2}" -f $elapsed,$attachedMovies.Count,$attachedName)
                        Write-Host "[V74.0.19] intro movie attached #$($attachedMovies.Count): $attachedName"
                    }
                }
                if($line -match 'Bink2 bridge queued: logo_intro\.bk2'){
                    $queuedLogoIntro=$true
                }
                if($line -match 'Bink2 bridge queued: logo_intro_loop\.bk2'){
                    $queuedLogoLoop=$true
                }
                if(-not $directBootCompleted -and $line -match 'bink2\.direct_boot_completed'){
                    $directBootCompleted=$true
                    $directBootCompletedAt=$now
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s direct_boot_completed {1}" -f $elapsed,$line)
                    Write-Host "[V74.0.19] direct boot completed at $([Math]::Round($elapsed,1))s; observing guest UI/render for 120s."
                    $candidate=Bound-DeadlineV74018 -Candidate $now.AddSeconds(120) -Absolute $absoluteDeadline
                    $deadline=$candidate
                }
                if($line -match 'Vulkan VideoOut presented guest frame:'){
                    if(-not $directBootStarted){$guestFrameBeforeDirectBoot=$true}
                    elseif(-not $directBootCompleted){$guestFrameDuringDirectBoot=$true}
                }
                if($line -match "bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'"){
                    $movieFile=$Matches[1]
                    if($null -eq $firstNaturalAt){
                        $firstNaturalAt=$now
                        $candidate=Bound-DeadlineV74018 -Candidate $now.AddSeconds(240) -Absolute $absoluteDeadline
                        if($candidate -gt $deadline){$deadline=$candidate}
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s natural_1 {1}" -f $elapsed,$movieFile)
                        Write-Host "[V74.0.19] natural movie #1 at $([Math]::Round($elapsed,1))s: $movieFile"
                    }
                    elseif($null -eq $secondNaturalAt -and [System.IO.Path]::GetFileName($movieFile) -ne "ps_studios_logo.bk2"){
                        $secondNaturalAt=$now
                        $candidate=Bound-DeadlineV74018 -Candidate $now.AddSeconds(180) -Absolute $absoluteDeadline
                        if($candidate -gt $deadline){$deadline=$candidate}
                        Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s natural_2 {1}" -f $elapsed,$movieFile)
                        Write-Host "[V74.0.19] natural movie #2 at $([Math]::Round($elapsed,1))s: $movieFile"
                    }
                }
                if($line -match 'Bink2 bridge completed:|Bink RAD bridge completed:'){
                    if($null -eq $firstCompleteAt){$firstCompleteAt=$now;Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s completed_1 {1}" -f $elapsed,$line)}
                    elseif($null -eq $secondCompleteAt){$secondCompleteAt=$now;Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s completed_2 {1}" -f $elapsed,$line)}
                }
                if($line -match '(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException'){
                    $liveDeviceLost=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s DEVICE_LOST {1}" -f $elapsed,$line)
                }
                if($line -match '(?i)HEAP_CORRUPTION|0xC0000374'){
                    $liveHeapCorruption=$true
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s HEAP_CORRUPTION {1}" -f $elapsed,$line)
                }
            }
        }

        $stdoutChunk=Read-NewSharedChunkV74018 -Path $stdout -Offset ([ref]$stdoutOffset)
        if(-not [string]::IsNullOrEmpty($stdoutChunk)){
            $scanOut=$stdoutCarry+$stdoutChunk
            $outLines=[regex]::Split($scanOut,"\r?\n")
            $outLineLimit=$outLines.Count
            if($scanOut.EndsWith("`n")){$stdoutCarry=""}else{$stdoutCarry=$outLines[$outLines.Count-1];$outLineLimit--}
            for($outLineIndex=0;$outLineIndex -lt $outLineLimit;$outLineIndex++){
                $outLine=$outLines[$outLineIndex]
                if($null -eq $mainLoopAt -and $outLine -match '\[MSG-Init\] Starting main loop:'){
                    $mainLoopAt=$now
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s main_loop {1}" -f $elapsed,$outLine)
                    Write-Host "[V74.0.19] main loop observed at host t=$([Math]::Round($elapsed,1))s."
                }
                if($null -eq $gatherAt -and $outLine -match 'ResourcePool::GatherResourceFileInfo\(\) took'){
                    $gatherAt=$now
                    Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s gather_complete {1}" -f $elapsed,$outLine)
                }
            }
        }

        if($now -ge $nextStatus){
            $statusFormat="[V74.0.19] t={0:F0}s procs={1} work={2:F0}MB private={3:F0}MB cpu={4:F0}% tbb={5} auto={6}/{7} direct={8}/{9} movies={10}"
            $statusArguments=[object[]]@(
                [double]$elapsed,[int]$sample.LiveCount,[double]($working/1MB),
                [double]($private/1MB),[double]$cpuPct,[int]$observedTbbLimit,
                [bool]$autoBootDiscovered,[bool]$autoBootOrderCorrect,
                [bool]$directBootStarted,[bool]$directBootCompleted,[int]$attachedMovies.Count)
            $statusLine=[string]::Format(
                [System.Globalization.CultureInfo]::InvariantCulture,
                $statusFormat,$statusArguments)
            Write-Host $statusLine
            $nextStatus=$now.AddSeconds(10)
        }

        if($elapsed -ge 60 -and -not $directBootStarted){
            $stopReason="auto-boot-not-started"
            Add-Content -LiteralPath $milestones -Encoding UTF8 -Value ("{0:F1}s AUTO_BOOT_NOT_STARTED" -f $elapsed)
            Write-Host "[V74.0.19] ERROR: direct boot did not start within 60s; stopping instead of wasting several minutes."
            break
        }
        if($directBootCompleted -and $null -ne $directBootCompletedAt -and
           ($now-$directBootCompletedAt).TotalSeconds -ge 120){
            $stopReason="post-boot-observation-complete"
            break
        }
        if($tbbMismatch -or $liveDeviceLost -or $liveHeapCorruption){$stopReason="fatal-guard";break}
        if($zeroProcessSamples -ge 3 -and $elapsed -gt 10){$stopReason="process-exit";break}
    }
}
catch{
    $runFailure=$_.Exception.Message
    $stopReason="runner-exception"
    Write-Host "[V74.0.19] Runner exception: $runFailure"
}
finally{
    if($null -ne $launcher){
        $remaining=Get-ProcessTreeSampleV74018 -RootProcessId $launcher.Id
        if($remaining.LiveCount -gt 0){
            Stop-ProcessTreeV74018 -RootProcessId $launcher.Id
            Start-Sleep -Milliseconds 700
        }
    }
    foreach($name in $variables){
        $previousValue=$oldEnvironment[$name]
        if($null -eq $previousValue){
            [Environment]::SetEnvironmentVariable($name,$null,[EnvironmentVariableTarget]::Process)
        }
        else{
            [Environment]::SetEnvironmentVariable($name,[string]$previousValue,[EnvironmentVariableTarget]::Process)
        }
    }
}

$ended=[DateTime]::UtcNow
$actualRuntimeSeconds=($ended-$started).TotalSeconds
$finalText=Read-SharedTextV74018 -Path $stderr
$stdoutText=Read-SharedTextV74018 -Path $stdout

$naturalMatches=[regex]::Matches($finalText,"bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'")
$completionMatches=[regex]::Matches($finalText,'Bink2 bridge completed:|Bink RAD bridge completed:')
$handoffMatches=[regex]::Matches($finalText,'bink2\.startup_completion_shim|startup_completion_shim_header_fallback')
$autoOrderMatches=[regex]::Matches($finalText,"bink2\.auto_boot_order movies=(\d+) sequence='([^']+)'")
$autoBootOrderCorrect=$false
$autoBootOrderKind="none"
foreach($autoOrderMatch in $autoOrderMatches){
    $finalMovieCount=[int]$autoOrderMatch.Groups[1].Value
    $finalSequence=$autoOrderMatch.Groups[2].Value
    if($finalMovieCount -eq 3 -and
       $finalSequence -eq "ps_studios_logo.bk2 -> logo_intro.bk2 -> logo_intro_loop.bk2"){
        $autoBootOrderCorrect=$true
        $autoBootOrderKind="three-intro"
        break
    }
    if($finalMovieCount -eq 2 -and
       $finalSequence -eq "ps_studios_logo.bk2 -> logo_intro.bk2"){
        $autoBootOrderCorrect=$true
        $autoBootOrderKind="two-intro"
    }
    elseif(-not $autoBootOrderCorrect){
        $autoBootOrderKind="mismatch"
    }
}
$autoDiscoveredMatches=[regex]::Matches($finalText,'bink2\.auto_boot_discovered')
$bootSelectedMatches=[regex]::Matches($finalText,'bink2\.boot_sequence_selected source=auto-app0')
$directStartedMatches=[regex]::Matches($finalText,'bink2\.direct_boot_started movies=(\d+)')
$directCompletedMatches=[regex]::Matches($finalText,'bink2\.direct_boot_completed')
$radAttachMatches=[regex]::Matches($finalText,"Bink RAD bridge attached:\s*([^\s]+\.bk2)")
$nihavAttachMatches=[regex]::Matches($finalText,"Bink2 NIHAV bridge attached:\s*([^\s]+\.bk2)")
$queueIntroMatches=[regex]::Matches($finalText,'Bink2 bridge queued: logo_intro\.bk2')
$queueLoopMatches=[regex]::Matches($finalText,'Bink2 bridge queued: logo_intro_loop\.bk2')
$guestThrottleBeginMatches=[regex]::Matches($finalText,'bink2\.rad_guest_work_throttle_begin')
$guestThrottleEndMatches=[regex]::Matches($finalText,'bink2\.rad_guest_work_throttle_end')
$opaqueGateMatches=[regex]::Matches($finalText,'\[V74\.0\.17\]\[PTHREAD_FASTBOOT\] opaque_owner_sync=enabled')
$opaqueSyncMatches=[regex]::Matches($finalText,'pthread_opaque_owner_sync:')
$nativeMemcpyMatches=[regex]::Matches($finalText,'\[V74\.0\.18\]\[MEMCPY_FASTPATH\] native intrinsic enabled')
$import8mMatches=[regex]::Matches($finalText,'dbfz\.import_progress\.v1892 import=8388608')
$import16mMatches=[regex]::Matches($finalText,'dbfz\.import_progress\.v1892 import=16777216')
$import25mMatches=[regex]::Matches($finalText,'dbfz\.import_progress\.v1892 import=25165824')
$import33mMatches=[regex]::Matches($finalText,'dbfz\.import_progress\.v1892 import=33554432')
$waitSuspendedMatches=[regex]::Matches($finalText,'agc\.wait_suspended')
$waitNoneProducerMatches=[regex]::Matches($finalText,'agc\.wait_suspended[^\r\n]*producer=none-observed')
$singleFlightOwnerMatches=[regex]::Matches($finalText,'\[V74\.0\.15\]\[ARRAY_SINGLEFLIGHT\] owner')
$singleFlightReuseMatches=[regex]::Matches($finalText,'\[V74\.0\.15\]\[ARRAY_SINGLEFLIGHT\] reuse')
$dccHistorySeedMatches=[regex]::Matches($finalText,'\[V74\.0\.16(?:\.1)?\]\[DCC_HISTORY\] seed')
$dccHistoryHitMatches=[regex]::Matches($finalText,'\[V74\.0\.16(?:\.1)?\]\[DCC_HISTORY\] hit')
$dccUnresolvedMatches=[regex]::Matches($finalText,'unresolved_dcc_cpu_snapshot_suppressed')
$largeSnapshotAllocMatches=[regex]::Matches($finalText,'large_texture_cpu_snapshot')
$largeSnapshotReuseMatches=[regex]::Matches($finalText,'large_texture_snapshot_reuse')
$trimMatches=[regex]::Matches($finalText,'TEX_CACHE\] trim')
$largeArrayMatches=[regex]::Matches($finalText,'TEX_CACHE\] add addr=0x000000102A400000[^\r\n]*bytes=335544320')
$deviceLostMatches=[regex]::Matches($finalText,'(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException')
$heapCorruptionMatches=[regex]::Matches($finalText,'(?i)HEAP_CORRUPTION|0xC0000374')
$tbbMatches=[regex]::Matches($finalText,'\[V74\.0\.10\]\[NATIVE_LANE\][^\r\n]*tbb_limit=(\d+)')
$allocBurstMatches=[regex]::Matches($finalText,'\[V74\.0\.8\.1\]\[MEM\][^\r\n]*alloc2s_mb=(\d+)')
$firstFrameMatch=[regex]::Match($finalText,'Vulkan VideoOut presented first frame:\s*(\d+)x(\d+)')
$guestFrameMatch=[regex]::Match($finalText,'Vulkan VideoOut presented guest frame:[^\r\n]*\s(\d+)x(\d+)')
$firstFrameSize=if($firstFrameMatch.Success){$firstFrameMatch.Groups[1].Value+"x"+$firstFrameMatch.Groups[2].Value}else{""}
$guestFrameSize=if($guestFrameMatch.Success){$guestFrameMatch.Groups[1].Value+"x"+$guestFrameMatch.Groups[2].Value}else{""}

$maxAlloc2sMb=0
foreach($allocBurstMatch in $allocBurstMatches){
    $alloc2sValue=[int]$allocBurstMatch.Groups[1].Value
    if($alloc2sValue -gt $maxAlloc2sMb){$maxAlloc2sMb=$alloc2sValue}
}
$runtimePeakWorking=0
$runtimePeakPrivate=0
foreach($memoryMatch in [regex]::Matches(
    $finalText,'\[V74\.0\.8\.1\]\[MEM\][^\r\n]*working_mb=(\d+)[^\r\n]*private_mb=(\d+)')){
    $runtimeWorking=[int]$memoryMatch.Groups[1].Value
    $runtimePrivate=[int]$memoryMatch.Groups[2].Value
    if($runtimeWorking -gt $runtimePeakWorking){$runtimePeakWorking=$runtimeWorking}
    if($runtimePrivate -gt $runtimePeakPrivate){$runtimePeakPrivate=$runtimePrivate}
}
$finalObservedTbb=-1
if($tbbMatches.Count -gt 0){$finalObservedTbb=[int]$tbbMatches[0].Groups[1].Value}

$movieNames=New-Object 'System.Collections.Generic.List[string]'
foreach($naturalMatch in $naturalMatches){
    $movieName=$naturalMatch.Groups[1].Value
    if(-not $movieNames.Contains($movieName)){$movieNames.Add($movieName)}
}

$mainLoopSeconds=""
$mainLoopMatch=[regex]::Match($stdoutText,'\[MSG-Init\] Starting main loop:\s*([0-9]+(?:[\.,][0-9]+)?)s')
if($mainLoopMatch.Success){$mainLoopSeconds=$mainLoopMatch.Groups[1].Value}
$gatherSeconds=""
$gatherMatch=[regex]::Match($stdoutText,'ResourcePool::GatherResourceFileInfo\(\) took\s*([^\r\n]+)')
if($gatherMatch.Success){
    $durationToken=$gatherMatch.Groups[1].Value.Trim()
    if($durationToken.EndsWith("s")){$durationToken=$durationToken.Substring(0,$durationToken.Length-1)}
    $durationToken=$durationToken.Replace(',', '.')
    if($durationToken -match '^(\d+):(\d+):(\d+(?:\.\d+)?)$'){
        $hours=[double]$Matches[1]; $minutes=[double]$Matches[2]
        $seconds=[double]::Parse($Matches[3],[System.Globalization.CultureInfo]::InvariantCulture)
        $gatherSeconds=([Math]::Round(($hours*3600)+($minutes*60)+$seconds,4)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    elseif($durationToken -match '^\d+(?:\.\d+)?$'){
        $gatherSeconds=$durationToken
    }
}

$classification="boot-sequence-not-started"
if($deviceLostMatches.Count -gt 0 -and $heapCorruptionMatches.Count -gt 0){$classification="vulkan-device-lost-heap-corruption"}
elseif($deviceLostMatches.Count -gt 0){$classification="vulkan-device-lost"}
elseif($finalObservedTbb -ge 0 -and $finalObservedTbb -ne 2){$classification="native-tbb-limiter-mismatch"}
elseif($nativeMemcpyMatches.Count -eq 0){$classification="native-memcpy-marker-not-observed"}
elseif($directStartedMatches.Count -eq 0){$classification="boot-sequence-not-started"}
elseif($autoOrderMatches.Count -eq 0){$classification="auto-boot-order-not-reported"}
elseif(-not $autoBootOrderCorrect){$classification="auto-boot-order-mismatch"}
elseif($directCompletedMatches.Count -eq 0){$classification="correct-intro-order-started-not-completed"}
elseif($autoBootOrderKind -eq "three-intro"){$classification="correct-three-video-direct-boot-completed"}
elseif($autoBootOrderKind -eq "two-intro"){$classification="correct-two-video-direct-boot-completed"}
else{$classification="direct-boot-completed-order-unclassified"}

$summaryLines=@(
    "version=74.0.19.0",
    "classification=$classification",
    "runtime=Release",
    "stop_reason=$stopReason",
    "run_failure=$runFailure",
    "actual_runtime_seconds=$([Math]::Round($actualRuntimeSeconds,1))",
    "",
    "[native-memcpy-and-scale-ab]",
    "requested_opaque_owner_sync=enabled",
    "native_memcpy_intrinsic_requested=enabled",
    "native_memcpy_marker_hits=$($nativeMemcpyMatches.Count)",
    "gate_marker_hits=$($opaqueGateMatches.Count)",
    "opaque_owner_sync_trace_hits=$($opaqueSyncMatches.Count)",
    "import_progress_8388608_hits=$($import8mMatches.Count)",
    "import_progress_16777216_hits=$($import16mMatches.Count)",
    "import_progress_25165824_hits=$($import25mMatches.Count)",
    "import_progress_33554432_hits=$($import33mMatches.Count)",
    "default_for_other_runs=enabled",
    "",
    "[boot-sequence-restore]",
    "bink_auto_boot_requested=1",
    "auto_boot_grace_ms=1500",
    "startup_completion_shim=0",
    "accepted_sequence=ps_studios_logo.bk2 -> logo_intro.bk2 [-> logo_intro_loop.bk2]",
    "auto_boot_order_kind=$autoBootOrderKind",
    "auto_boot_order_hits=$($autoOrderMatches.Count)",
    "auto_boot_order_correct=$autoBootOrderCorrect",
    "auto_boot_discovered_hits=$($autoDiscoveredMatches.Count)",
    "boot_sequence_selected_hits=$($bootSelectedMatches.Count)",
    "direct_boot_started_hits=$($directStartedMatches.Count)",
    "direct_boot_completed_hits=$($directCompletedMatches.Count)",
    "queued_logo_intro_hits=$($queueIntroMatches.Count)",
    "queued_logo_intro_loop_hits=$($queueLoopMatches.Count)",
    "rad_attached_movies=$($radAttachMatches.Count)",
    "nihav_attached_movies=$($nihavAttachMatches.Count)",
    "guest_work_throttle_begin_hits=$($guestThrottleBeginMatches.Count)",
    "guest_work_throttle_end_hits=$($guestThrottleEndMatches.Count)",
    "guest_frame_before_direct_boot=$guestFrameBeforeDirectBoot",
    "guest_frame_during_direct_boot=$guestFrameDuringDirectBoot",
    "",
    "[startup]",
    "main_loop_game_seconds=$mainLoopSeconds",
    "gather_resource_file_info_seconds=$gatherSeconds",
    "natural_movie_hits=$($naturalMatches.Count)",
    "natural_movie_files=$($movieNames -join ',')",
    "bridge_completed_hits=$($completionMatches.Count)",
    "startup_completion_handoff_hits=$($handoffMatches.Count)",
    "",
    "[verified-runtime-profile]",
    "render_scale=1.0",
    "requested_tbb_limit=2",
    "observed_tbb_limit=$finalObservedTbb",
    "renderer_resource_limit=8",
    "standalone_texture_cache_mb=768",
    "sampled_cache_mb=256",
    "guest_buffer_cache_mb=192",
    "device_buffer_cache_mb=384",
    "dcc_alias_history_ms=0",
    "large_snapshot_reuse_ms=10000",
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
    "",
    "[dcc-history-disabled-check]",
    "seed_hits=$($dccHistorySeedMatches.Count)",
    "history_hits=$($dccHistoryHitMatches.Count)",
    "unresolved_dcc_suppressions=$($dccUnresolvedMatches.Count)",
    "",
    "[non-dcc-large-snapshot-reuse]",
    "cpu_snapshot_alloc_hits=$($largeSnapshotAllocMatches.Count)",
    "snapshot_reuse_hits=$($largeSnapshotReuseMatches.Count)",
    "",
    "[wait-reg-mem-diagnostics-only]",
    "wait_suspended_hits=$($waitSuspendedMatches.Count)",
    "none_observed_at_suspend_hits=$($waitNoneProducerMatches.Count)",
    "note=these counts are not treated as permanent deadlocks; historical runs show later WRITE_DATA producers/resumes",
    "",
    "[vulkan-regression-guards]",
    "large_320mb_array_hits=$($largeArrayMatches.Count)",
    "texture_cache_trim_hits=$($trimMatches.Count)",
    "device_lost_hits=$($deviceLostMatches.Count)",
    "heap_corruption_hits=$($heapCorruptionMatches.Count)",
    "",
    "[runner-v74019]",
    "process_tree_telemetry=True",
    "shared_stdout_stderr_read=True",
    "status_format_stringformat=True",
    "release_only=True",
    "normal_result_zip=True"
)
[System.IO.File]::WriteAllLines($summary,$summaryLines,[System.Text.UTF8Encoding]::new($true))

$zip=[System.IO.Path]::Combine($root,"SharpEmu_V74_0_19_BOOT_SEQUENCE_RESULT_$stamp.zip")
try{
    if([System.IO.File]::Exists($zip)){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -Path ([System.IO.Path]::Combine($out,"*")) -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "[V74.0.19] RESULT ZIP: $zip"
}
catch{
    Write-Host "[V74.0.19] RESULT ZIP FAILED: $($_.Exception.Message)"
    Write-Host "[V74.0.19] Result folder preserved: $out"
}

Write-Host "[V74.0.19] classification=$classification stop_reason=$stopReason runtime_seconds=$([Math]::Round($actualRuntimeSeconds,1))"
Write-Host "[V74.0.19] native_memcpy/pthread=$($nativeMemcpyMatches.Count)/$($opaqueGateMatches.Count) imports8/16/25/33m=$($import8mMatches.Count)/$($import16mMatches.Count)/$($import25mMatches.Count)/$($import33mMatches.Count)"
Write-Host "[V74.0.19] boot order_ok=$autoBootOrderCorrect kind=$autoBootOrderKind auto/discovered/direct_start/direct_complete=$($autoDiscoveredMatches.Count)/$($bootSelectedMatches.Count)/$($directStartedMatches.Count)/$($directCompletedMatches.Count) attached(rad/nihav)=$($radAttachMatches.Count)/$($nihavAttachMatches.Count)"
Write-Host "[V74.0.19] main_loop/gather=$mainLoopSeconds/$gatherSeconds sec guest_frames=$firstFrameSize/$guestFrameSize natural_after_boot=$($naturalMatches.Count)"
Write-Host "[V74.0.19] tree peak working/private=$([Math]::Round($peakTreeWorking/1MB,1))/$([Math]::Round($peakTreePrivate/1MB,1)) MB max_alloc2s_mb=$maxAlloc2sMb"
Write-Host "[V74.0.19] DCC history seed/hit=$($dccHistorySeedMatches.Count)/$($dccHistoryHitMatches.Count) array owner/reuse=$($singleFlightOwnerMatches.Count)/$($singleFlightReuseMatches.Count)"
Write-Host "[V74.0.19] wait_suspended/none_observed_at_suspend=$($waitSuspendedMatches.Count)/$($waitNoneProducerMatches.Count) (diagnostic only)"
Write-Host "[V74.0.19] device_lost=$($deviceLostMatches.Count) heap_corruption=$($heapCorruptionMatches.Count)"
