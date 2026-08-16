param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root

$currentSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
if($currentSha-ne"B837FD073B69E1656F4CA3475259CF911DFA011F161E45450F8D19822A6C4F41"){
    throw "[V74.0.11.1] Diagnostic refused: unexpected presenter SHA $currentSha"
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.11.1] EBOOT missing: $Eboot"
}

$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){
    throw "[V74.0.11.1] Wrong EBOOT. expected=$expected actual=$actual"
}

$dll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.11.1] SharpEmu.dll missing: $dll"
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_11_NATURAL_BINK_FALLBACK_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null
Write-Host "[V74.0.11.1] LIVE RESULT FOLDER: $out"

$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$processCsv=[System.IO.Path]::Combine($out,"PROCESS_OS_TRUTH.csv")
$gpuCsv=[System.IO.Path]::Combine($out,"GPU_OS_TRUTH.csv")
$systemCsv=[System.IO.Path]::Combine($out,"SYSTEM_MEMORY_TRUTH.csv")
$nvidiaCsv=[System.IO.Path]::Combine($out,"NVIDIA_GPU_TRUTH.csv")
$progressCsv=[System.IO.Path]::Combine($out,"PROGRESS_MILESTONES.csv")

"elapsed_s;process_count;working_mb;private_mb;virtual_mb;paged_mb;handles;threads;cpu_s;cpu_pct;io_read_mb_s;io_write_mb_s" |
    Set-Content -LiteralPath $processCsv -Encoding ASCII
"elapsed_s;dedicated_mb;shared_mb;total_committed_mb;gpu_util_pct;gpu_counter_available" |
    Set-Content -LiteralPath $gpuCsv -Encoding ASCII
"elapsed_s;available_mb;commit_mb;commit_limit_mb;paged_pool_mb;nonpaged_pool_mb;cache_mb" |
    Set-Content -LiteralPath $systemCsv -Encoding ASCII
"elapsed_s;gpu_util_pct;memory_used_mb;memory_total_mb;temperature_c;power_w;available" |
    Set-Content -LiteralPath $nvidiaCsv -Encoding ASCII
"elapsed_s;event_n;presenter_timeline_completed;presenter_timeline_submit;critical_45d_bound;critical_45d_writer;critical_45d_rejected;natural_bink;compute_yuv;ui_hits;stderr_mb" |
    Set-Content -LiteralPath $progressCsv -Encoding ASCII

$variables=@(
    "SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT",
    "SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT",
    "SHARPEMU_LOG_GUEST_THREADS",
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT",
    "SHARPEMU_TRACE_RENDER_TARGET_ADDRESS",
    "SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB",
    "SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB",
    "SHARPEMU_VK_GUEST_BUFFER_CACHE_MB",
    "SHARPEMU_PROFILE_GPU_WAIT",
    "SHARPEMU_PROFILE_GPU_WAIT_REPORT_S",
    "SHARPEMU_LOG_DIRECT_MEMORY",
    "SHARPEMU_LOG_VMEM",
    "SHARPEMU_LOG_VIRTUAL_MEMORY",
    "SHARPEMU_LOG_LAZY_COMMIT",
    "SHARPEMU_LOG_VIDEOOUT_FPS",
    "SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS",
    "SHARPEMU_LOG_AGC_SHADER",
    "SHARPEMU_TRACE_DCC_ALIAS",
    "SHARPEMU_TRACE_SCANOUT_LINEAGE",
    "SHARPEMU_TRACE_RESOURCE_DEPENDENCIES",
    "SHARPEMU_LOG_VK_RESOURCES",
    "SHARPEMU_LOG_VK_COMPUTE_RESOURCES",
    "SHARPEMU_BINK_INTRO_HARNESS",
    "SHARPEMU_TRACE_MOVIE_IO",
    "SHARPEMU_RENDER_CHECKPOINTS",
    "SHARPEMU_DISABLE_NATIVE_GUEST_WORKERS",
    "SHARPEMU_VEH_HOST_MANAGED"
)

$old=@{}
foreach($name in $variables){
    $old[$name]=[Environment]::GetEnvironmentVariable(
        $name,[EnvironmentVariableTarget]::Process)
}

function Get-SharpEmuProcessTree {
    param([int]$LauncherProcessId)

    $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $ids=New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$ids.Add($LauncherProcessId)

    $changed=$true
    while($changed){
        $changed=$false
        foreach($wp in $all){
            $child=[int]$wp.ProcessId
            $parent=[int]$wp.ParentProcessId
            if($ids.Contains($parent)-and-not $ids.Contains($child)){
                [void]$ids.Add($child)
                $changed=$true
            }
        }
    }

    foreach($wp in $all){
        if($null-ne$wp.CommandLine -and
           $wp.CommandLine.IndexOf(
               "SharpEmu.dll",
               [System.StringComparison]::OrdinalIgnoreCase)-ge 0){
            [void]$ids.Add([int]$wp.ProcessId)
        }
    }

    return @($ids)
}

function Get-ProcessTruth {
    param(
        [int[]]$ProcessIds,
        [double]$PreviousCpu,
        [double]$ElapsedSinceSample
    )

    $working=[int64]0
    $private=[int64]0
    $virtual=[int64]0
    $paged=[int64]0
    $handles=[int64]0
    $threads=[int64]0
    $cpu=0.0
    $alive=0

    foreach($processIdValue in $ProcessIds){
        try{
            $p=Get-Process -Id $processIdValue -ErrorAction Stop
            $working += [int64]$p.WorkingSet64
            $private += [int64]$p.PrivateMemorySize64
            $virtual += [int64]$p.VirtualMemorySize64
            $paged += [int64]$p.PagedMemorySize64
            $handles += [int64]$p.HandleCount
            $threads += [int64]$p.Threads.Count
            $cpu += [double]$p.CPU
            $alive++
        }catch{}
    }

    $cpuPct=0.0
    if($ElapsedSinceSample-gt 0){
        $cpuDelta=[Math]::Max(0.0,$cpu-$PreviousCpu)
        $cpuPct=
            ($cpuDelta/$ElapsedSinceSample) /
            [Math]::Max([Environment]::ProcessorCount,1) * 100.0
    }

    $readRate=[int64]0
    $writeRate=[int64]0
    try{
        $perf=@(
            Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop |
            Where-Object{$ProcessIds -contains [int]$_.IDProcess}
        )
        foreach($row in $perf){
            $readRate += [int64]$row.IOReadBytesPersec
            $writeRate += [int64]$row.IOWriteBytesPersec
        }
    }catch{}

    [pscustomobject]@{
        Count=$alive
        Working=$working
        Private=$private
        Virtual=$virtual
        Paged=$paged
        Handles=$handles
        Threads=$threads
        Cpu=$cpu
        CpuPct=$cpuPct
        ReadRate=$readRate
        WriteRate=$writeRate
    }
}

function Get-GpuTruth {
    param([int[]]$ProcessIds)

    $dedicated=[int64]0
    $shared=[int64]0
    $committed=[int64]0
    $util=0.0
    $available=$false

    try{
        $rows=@(
            Get-CimInstance `
                Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory `
                -ErrorAction Stop
        )
        foreach($row in $rows){
            if($row.Name -match 'pid_(\d+)'){
                $rowProcessId=[int]$Matches[1]
                if($ProcessIds -contains $rowProcessId){
                    $available=$true
                    if($null-ne$row.DedicatedUsage){$dedicated += [int64]$row.DedicatedUsage}
                    if($null-ne$row.SharedUsage){$shared += [int64]$row.SharedUsage}
                    if($null-ne$row.TotalCommitted){$committed += [int64]$row.TotalCommitted}
                }
            }
        }

        $engines=@(
            Get-CimInstance `
                Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine `
                -ErrorAction Stop
        )
        foreach($row in $engines){
            if($row.Name -match 'pid_(\d+)'){
                $rowProcessId=[int]$Matches[1]
                if($ProcessIds -contains $rowProcessId){
                    $available=$true
                    if($null-ne$row.UtilizationPercentage){
                        $util += [double]$row.UtilizationPercentage
                    }
                }
            }
        }
    }catch{}

    [pscustomobject]@{
        Dedicated=$dedicated
        Shared=$shared
        Committed=$committed
        Util=[Math]::Min($util,100.0)
        Available=$available
    }
}

function Get-SystemMemoryTruth {
    $available=[int64]0
    $committed=[int64]0
    $commitLimit=[int64]0
    $paged=[int64]0
    $nonpaged=[int64]0
    $cache=[int64]0

    try{
        $m=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $available=[int64]$m.AvailableMBytes*1MB
        $committed=[int64]$m.CommittedBytes
        $commitLimit=[int64]$m.CommitLimit
        $paged=[int64]$m.PoolPagedBytes
        $nonpaged=[int64]$m.PoolNonpagedBytes
        $cache=[int64]$m.CacheBytes
    }catch{}

    [pscustomobject]@{
        Available=$available
        Committed=$committed
        CommitLimit=$commitLimit
        Paged=$paged
        Nonpaged=$nonpaged
        Cache=$cache
    }
}

function Get-NvidiaTruth {
    $available=$false
    $util=0
    $used=0
    $total=0
    $temp=0
    $power=0.0

    try{
        $command=Get-Command nvidia-smi.exe -ErrorAction Stop
        $line=& $command.Source `
            --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw `
            --format=csv,noheader,nounits 2>$null |
            Select-Object -First 1

        if($null-ne$line){
            $parts=@($line -split ','|ForEach-Object{$_.Trim()})
            if($parts.Count-ge 5){
                $available=$true
                [void][int]::TryParse($parts[0],[ref]$util)
                [void][int]::TryParse($parts[1],[ref]$used)
                [void][int]::TryParse($parts[2],[ref]$total)
                [void][int]::TryParse($parts[3],[ref]$temp)
                [void][double]::TryParse(
                    $parts[4],
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$power)
            }
        }
    }catch{}

    [pscustomobject]@{
        Available=$available
        Util=$util
        Used=$used
        Total=$total
        Temp=$temp
        Power=$power
    }
}

function Get-ProgressTruth {
    param([string]$StderrPath)

    $eventN=0
    $timelineCompleted=0
    $timelineSubmit=0
    $criticalBound=0
    $criticalWriter=0
    $criticalRejected=0
    $natural=0
    $computeYuv=0
    $uiHits=0
    $length=0L
    $hasFailFast=$false
    $hasDeviceLost=$false
    $computeFails=0

    if(-not [System.IO.File]::Exists($StderrPath)){
        return [pscustomobject]@{
            EventN=0; TimelineCompleted=0; TimelineSubmit=0;
            CriticalBound=0; CriticalWriter=0; CriticalRejected=0;
            Natural=0; ComputeYuv=0; UiHits=0; Bytes=0;
            FailFast=$false; DeviceLost=$false; ComputeFails=0
        }
    }

    try{
        $length=(Get-Item -LiteralPath $StderrPath).Length
        $text=[System.IO.File]::ReadAllText($StderrPath)

        foreach($match in [regex]::Matches(
                    $text,
                    '\[V17\]\[EVENT_FASTPATH\] n=(\d+)')){
            $n=[int]$match.Groups[1].Value
            if($n-gt$eventN){$eventN=$n}
        }

        $memMatches=[regex]::Matches(
            $text,
            '\[V74\.0\.8\.1\]\[MEM\].*?timeline=(\d+)/(\d+)')
        if($memMatches.Count-gt 0){
            $last=$memMatches[$memMatches.Count-1]
            $timelineCompleted=[int]$last.Groups[1].Value
            $timelineSubmit=[int]$last.Groups[2].Value
        }

        $criticalBound=[regex]::Matches(
            $text,
            'agc\.rt_bound[^\r\n]*target=0x000000045D550000').Count
        $criticalWriter=[regex]::Matches(
            $text,
            'agc\.rt_writer_filtered[^\r\n]*target=0x000000045D550000').Count
        $criticalRejected=[regex]::Matches(
            $text,
            'agc\.rt_writer_rejected[^\r\n]*target=0x000000045D550000').Count
        $natural=[regex]::Matches($text,'bink2\.natural_guest_movie_observed').Count
        $computeYuv=[regex]::Matches($text,'bink2\.compute_yuv_binding').Count
        $directFallbackFrames=[regex]::Matches(
            $text,
            '\[V74\.0\.11\]\[BINK\] bink2\.descriptorless_direct_frame').Count
        $directFallbackStarts=[regex]::Matches(
            $text,
            '\[V74\.0\.11\]\[BINK\] bink2\.descriptorless_direct_fallback_start').Count
        $uiHits=[regex]::Matches(
            $text,
            'uistartmenu|uifrontend|subscreen_overlay_backing',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
        $computeFails=[regex]::Matches($text,'Vulkan compute dispatch failed').Count

        $hasFailFast=
            $text.IndexOf(
                "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code",
                [System.StringComparison]::Ordinal)-ge 0 -or
            $text.IndexOf(
                "0x80131506",
                [System.StringComparison]::OrdinalIgnoreCase)-ge 0

        $hasDeviceLost=
            $text.IndexOf(
                "VK_ERROR_DEVICE_LOST",
                [System.StringComparison]::OrdinalIgnoreCase)-ge 0 -or
            $text.IndexOf(
                "DeviceLostException",
                [System.StringComparison]::OrdinalIgnoreCase)-ge 0
    }catch{}

    [pscustomobject]@{
        EventN=$eventN
        TimelineCompleted=$timelineCompleted
        TimelineSubmit=$timelineSubmit
        CriticalBound=$criticalBound
        CriticalWriter=$criticalWriter
        CriticalRejected=$criticalRejected
        Natural=$natural
        ComputeYuv=$computeYuv
        UiHits=$uiHits
        Bytes=$length
        FailFast=$hasFailFast
        DeviceLost=$hasDeviceLost
        ComputeFails=$computeFails
    }
}

$started=[DateTime]::UtcNow
$hardDeadline=$started.AddSeconds(660)
$deadline=$hardDeadline
$naturalAt=$null
$previousCpu=0.0
$previousSample=$started
$maxWorking=[int64]0
$maxPrivate=[int64]0
$maxGpuDedicated=[int64]0
$maxGpuShared=[int64]0
$maxSystemCommit=[int64]0
$memoryPressureStop=$false
$exitCode=""
$zeroSamples=0
$pressureSamples=0
$lastConsole=[DateTime]::MinValue
$lastProgressSample=[DateTime]::MinValue
$lastEventN=0
$lastEventAdvanceAt=$started
$lastTimelineSubmit=0
$lastTimelineAdvanceAt=$started

try{
    # Preserve the historical TBB protection while opening an independent
    # long-lived renderer/resource lane.
    $env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    $env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"
    $env:SHARPEMU_LOG_GUEST_THREADS="1"

    # Preserve all current correction policies.
    # Natural path only: do not let the old timed host auto-boot race the
    # guest request near the 600-second mark.
    $env:SHARPEMU_BINK_AUTO_BOOT="0"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="900000"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="1"
    $env:SHARPEMU_TRACE_RENDER_TARGET_ADDRESS="0x45D550000"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="512"
    $env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    $env:SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="512"

    # Simultaneous aggregate truth domains.
    $env:SHARPEMU_LOG_DIRECT_MEMORY="1"
    $env:SHARPEMU_LOG_VMEM="1"
    $env:SHARPEMU_LOG_VIRTUAL_MEMORY="1"
    $env:SHARPEMU_LOG_LAZY_COMMIT="1"
    $env:SHARPEMU_PROFILE_GPU_WAIT="1"
    $env:SHARPEMU_PROFILE_GPU_WAIT_REPORT_S="5"
    $env:SHARPEMU_LOG_VIDEOOUT_FPS="1"
    $env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS="1"

    # Keep workload-distorting bulk traces off.
    $env:SHARPEMU_LOG_AGC_SHADER="0"
    $env:SHARPEMU_TRACE_DCC_ALIAS="0"
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE="0"
    $env:SHARPEMU_TRACE_RESOURCE_DEPENDENCIES="0"
    $env:SHARPEMU_LOG_VK_RESOURCES="0"
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES="0"
    $env:SHARPEMU_BINK_INTRO_HARNESS="0"
    $env:SHARPEMU_TRACE_MOVIE_IO="0"

    Remove-Item Env:SHARPEMU_RENDER_CHECKPOINTS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_DISABLE_NATIVE_GUEST_WORKERS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_VEH_HOST_MANAGED -ErrorAction SilentlyContinue

    Write-Host "[V74.0.11.1] NATURAL-BINK DESCRIPTORLESS FALLBACK FULL TRUTH starting."
    Write-Host "[V74.0.11.1] One run; all truth domains active together; TBB lane=2, renderer/resource lane=8."
    Write-Host "[V74.0.11.1] hard horizon=660s; V73.18 natural-Bink reference ended at ~479.5s."
    Write-Host "[V74.0.11.1] If natural Bink appears, capture continues up to +60s for YUV/compositor evidence."
    Write-Host "[V74.0.11.1] Targeted low-volume compositor RT trace=0x45D550000."
    Write-Host "[V74.0.11.1] Safety stop=>18GiB working or >24GiB private for ~10s."

    $args='"{0}" "{1}"' -f $dll,$Eboot
    $launcher=Start-Process `
        -FilePath "dotnet" `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    while([DateTime]::UtcNow-lt$deadline){
        Start-Sleep -Seconds 2
        $now=[DateTime]::UtcNow
        $elapsed=($now-$started).TotalSeconds
        $sampleSeconds=[Math]::Max(($now-$previousSample).TotalSeconds,0.001)

        $ids=@(Get-SharpEmuProcessTree -LauncherProcessId $launcher.Id)
        $proc=Get-ProcessTruth `
            -ProcessIds $ids `
            -PreviousCpu $previousCpu `
            -ElapsedSinceSample $sampleSeconds
        $gpu=Get-GpuTruth -ProcessIds $ids
        $sys=Get-SystemMemoryTruth
        $nv=Get-NvidiaTruth

        $previousCpu=$proc.Cpu
        $previousSample=$now

        $maxWorking=[Math]::Max($maxWorking,[int64]$proc.Working)
        $maxPrivate=[Math]::Max($maxPrivate,[int64]$proc.Private)
        $maxGpuDedicated=[Math]::Max($maxGpuDedicated,[int64]$gpu.Dedicated)
        $maxGpuShared=[Math]::Max($maxGpuShared,[int64]$gpu.Shared)
        $maxSystemCommit=[Math]::Max($maxSystemCommit,[int64]$sys.Committed)

        ("{0:F1};{1};{2:F1};{3:F1};{4:F1};{5:F1};{6};{7};{8:F2};{9:F1};{10:F1};{11:F1}" -f
            $elapsed,$proc.Count,($proc.Working/1MB),($proc.Private/1MB),
            ($proc.Virtual/1MB),($proc.Paged/1MB),$proc.Handles,$proc.Threads,
            $proc.Cpu,$proc.CpuPct,($proc.ReadRate/1MB),($proc.WriteRate/1MB)) |
            Add-Content -LiteralPath $processCsv -Encoding ASCII

        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5}" -f
            $elapsed,($gpu.Dedicated/1MB),($gpu.Shared/1MB),
            ($gpu.Committed/1MB),$gpu.Util,$gpu.Available) |
            Add-Content -LiteralPath $gpuCsv -Encoding ASCII

        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5:F1};{6:F1}" -f
            $elapsed,($sys.Available/1MB),($sys.Committed/1MB),
            ($sys.CommitLimit/1MB),($sys.Paged/1MB),($sys.Nonpaged/1MB),
            ($sys.Cache/1MB)) |
            Add-Content -LiteralPath $systemCsv -Encoding ASCII

        ("{0:F1};{1};{2};{3};{4};{5:F1};{6}" -f
            $elapsed,$nv.Util,$nv.Used,$nv.Total,$nv.Temp,$nv.Power,$nv.Available) |
            Add-Content -LiteralPath $nvidiaCsv -Encoding ASCII

        if($now-ge$lastProgressSample.AddSeconds(10)){
            $lastProgressSample=$now
            $progress=Get-ProgressTruth $stderr

            if($progress.EventN-gt$lastEventN){
                $lastEventN=$progress.EventN
                $lastEventAdvanceAt=$now
            }

            if($progress.TimelineSubmit-gt$lastTimelineSubmit){
                $lastTimelineSubmit=$progress.TimelineSubmit
                $lastTimelineAdvanceAt=$now
            }

            ("{0:F1};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10:F1}" -f
                $elapsed,$progress.EventN,$progress.TimelineCompleted,
                $progress.TimelineSubmit,$progress.CriticalBound,
                $progress.CriticalWriter,$progress.CriticalRejected,
                $progress.Natural,$progress.ComputeYuv,$progress.UiHits,
                ($progress.Bytes/1MB)) |
                Add-Content -LiteralPath $progressCsv -Encoding ASCII

            if($progress.Natural-gt 0 -and $null-eq$naturalAt){
                $naturalAt=$now
                $candidate=$now.AddSeconds(30)
                if($candidate-lt$hardDeadline){
                    $deadline=$candidate
                }
                Write-Host "[V74.0.11.1] NATURAL GUEST BINK reached at t=$([Math]::Round($elapsed))s; capturing up to +30s post-natural."
            }

            if($progress.FailFast){
                Write-Host "[V74.0.11.1] CLR FailFast regression detected."
                break
            }

            if($progress.DeviceLost){
                Write-Host "[V74.0.11.1] Vulkan device lost detected."
                break
            }
        }

        if($proc.Count-eq 0){$zeroSamples++}else{$zeroSamples=0}
        if($proc.Working-gt 18GB -or $proc.Private-gt 24GB){
            $pressureSamples++
        }else{
            $pressureSamples=0
        }

        if($pressureSamples-ge 5){
            $memoryPressureStop=$true
            Write-Host "[V74.0.11.1] MEMORY SAFETY STOP: comprehensive samples preserved."
            break
        }

        if($now-ge$lastConsole.AddSeconds(30)){
            $lastConsole=$now
            $p=Get-ProgressTruth $stderr
            $eventIdle=[Math]::Round(($now-$lastEventAdvanceAt).TotalSeconds)
            $timelineIdle=[Math]::Round(($now-$lastTimelineAdvanceAt).TotalSeconds)

            $statusFormat = (
                "[V74.0.11.1] t={0:F0}s event={1} timeline={2}/{3} event_idle={4}s timeline_idle={5}s " +
                "45D={6}/{7}/{8} natural={9} yuv={10} work={11:F0}MB private={12:F0}MB " +
                "gpu_ded={13:F0}MB gpu_shared={14:F0}MB gpu={15:F0}% cpu={16:F0}%")
            $status = $statusFormat -f
                $elapsed,$p.EventN,$p.TimelineCompleted,$p.TimelineSubmit,
                $eventIdle,$timelineIdle,
                $p.CriticalBound,$p.CriticalWriter,$p.CriticalRejected,
                $p.Natural,$p.ComputeYuv,
                ($proc.Working/1MB),($proc.Private/1MB),
                ($gpu.Dedicated/1MB),($gpu.Shared/1MB),$gpu.Util,$proc.CpuPct
            Write-Host $status

            @(
                "version=74.0.11.1",
                "elapsed_s=$([Math]::Round($elapsed,1))",
                "event_n=$($p.EventN)",
                "timeline=$($p.TimelineCompleted)/$($p.TimelineSubmit)",
                "event_idle_s=$eventIdle",
                "timeline_idle_s=$timelineIdle",
                "critical_45d_bound=$($p.CriticalBound)",
                "critical_45d_writer=$($p.CriticalWriter)",
                "critical_45d_rejected=$($p.CriticalRejected)",
                "natural_bink=$($p.Natural)",
                "compute_yuv=$($p.ComputeYuv)",
                ("working_mb={0:F1}" -f ($proc.Working/1MB)),
                ("private_mb={0:F1}" -f ($proc.Private/1MB)),
                ("gpu_dedicated_mb={0:F1}" -f ($gpu.Dedicated/1MB)),
                ("gpu_shared_mb={0:F1}" -f ($gpu.Shared/1MB)),
                ("gpu_util_pct={0:F1}" -f $gpu.Util),
                ("cpu_pct={0:F1}" -f $proc.CpuPct),
                "",
                "This file is rewritten every ~30 seconds and survives Ctrl+C."
            ) | Set-Content -LiteralPath (
                [System.IO.Path]::Combine($out,"LIVE_STATUS.txt")) -Encoding UTF8
        }

        if($zeroSamples-ge 3 -and $elapsed-gt 10){
            break
        }
    }

    try{
        $launcher.Refresh()
        if($launcher.HasExited){$exitCode=$launcher.ExitCode}else{$exitCode="diagnostic-stop"}
    }catch{
        $exitCode="unknown"
    }

    $ids=@(Get-SharpEmuProcessTree -LauncherProcessId $launcher.Id)
    foreach($processIdValue in $ids){
        try{& taskkill.exe /PID $processIdValue /T /F 2>$null|Out-Null}catch{}
    }
}
finally{
    foreach($name in $variables){
        if($null-eq$old[$name]){
            Remove-Item ("Env:"+$name) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $name,[string]$old[$name],[EnvironmentVariableTarget]::Process)
        }
    }
}


@(
    "version=74.0.11.1",
    "collection_completed=True",
    "exit_code=$exitCode",
    "memory_pressure_stop=$memoryPressureStop",
    "completed_utc=$([DateTime]::UtcNow.ToString('o'))"
) | Set-Content -LiteralPath (
    [System.IO.Path]::Combine($out,"COLLECTION_DONE.txt")) -Encoding UTF8

Write-Host "[V74.0.11.1] RAW COLLECTION COMPLETE."
Write-Host "[V74.0.11.1] Folder retained for fast finalization: $out"
