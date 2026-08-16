param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root

$currentSha=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash.ToUpperInvariant()
if($currentSha-ne"0D4DB050177B237149CD55C1F18F0A99EB28A2B0999BA40E5E7F4234AC7BCE66"){
    throw "[V74.0.10] Diagnostic refused: unexpected presenter SHA $currentSha"
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.10] EBOOT missing: $Eboot"
}

$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){
    throw "[V74.0.10] Wrong EBOOT. expected=$expected actual=$actual"
}

$dll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.10] SharpEmu.dll missing: $dll"
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_10_NATIVE_LANE_TRUTH_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null

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
$hardDeadline=$started.AddSeconds(600)
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

    Write-Host "[V74.0.10] RENDERER/RESOURCE NATIVE-LANE FULL TRUTH starting."
    Write-Host "[V74.0.10] One run; all truth domains active together; TBB lane=2, renderer/resource lane=8."
    Write-Host "[V74.0.10] hard horizon=600s; V73.18 natural-Bink reference ended at ~479.5s."
    Write-Host "[V74.0.10] If natural Bink appears, capture continues up to +60s for YUV/compositor evidence."
    Write-Host "[V74.0.10] Targeted low-volume compositor RT trace=0x45D550000."
    Write-Host "[V74.0.10] Safety stop=>18GiB working or >24GiB private for ~10s."

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
                $candidate=$now.AddSeconds(60)
                if($candidate-lt$hardDeadline){
                    $deadline=$candidate
                }
                Write-Host "[V74.0.10] NATURAL GUEST BINK reached at t=$([Math]::Round($elapsed))s; extending capture up to +60s."
            }

            if($progress.FailFast){
                Write-Host "[V74.0.10] CLR FailFast regression detected."
                break
            }

            if($progress.DeviceLost){
                Write-Host "[V74.0.10] Vulkan device lost detected."
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
            Write-Host "[V74.0.10] MEMORY SAFETY STOP: comprehensive samples preserved."
            break
        }

        if($now-ge$lastConsole.AddSeconds(30)){
            $lastConsole=$now
            $p=Get-ProgressTruth $stderr
            $eventIdle=[Math]::Round(($now-$lastEventAdvanceAt).TotalSeconds)
            $timelineIdle=[Math]::Round(($now-$lastTimelineAdvanceAt).TotalSeconds)

            Write-Host (
                "[V74.0.10] t={0:F0}s event={1} timeline={2}/{3} event_idle={4}s timeline_idle={5}s " +
                "45D={6}/{7}/{8} natural={9} yuv={10} work={11:F0}MB private={12:F0}MB " +
                "gpu_ded={13:F0}MB gpu_shared={14:F0}MB gpu={15:F0}% cpu={16:F0}%" -f
                $elapsed,$p.EventN,$p.TimelineCompleted,$p.TimelineSubmit,
                $eventIdle,$timelineIdle,
                $p.CriticalBound,$p.CriticalWriter,$p.CriticalRejected,
                $p.Natural,$p.ComputeYuv,
                ($proc.Working/1MB),($proc.Private/1MB),
                ($gpu.Dedicated/1MB),($gpu.Shared/1MB),$gpu.Util,$proc.CpuPct)
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

$all=New-Object System.Collections.Generic.List[string]
foreach($file in @($stdout,$stderr)){
    if([System.IO.File]::Exists($file)){
        foreach($line in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)){
            $all.Add([string]$line)
        }
    }
}

function Hits([string]$Pattern){
    return @($all|Where-Object{$_ -match $Pattern})
}

function MaxMetric([string[]]$Lines,[string]$Name){
    $max=[int64]0
    foreach($line in $Lines){
        if($line -match ([regex]::Escape($Name)+'=(\d+)')){
            $value=[int64]$Matches[1]
            if($value-gt$max){$max=$value}
        }
    }
    return $max
}

$mem=@(Hits "\[V74\.0\.8\.1\]\[MEM\]")
$events=@(Hits "\[V17\]\[EVENT_FASTPATH\]")
$criticalBound=@(Hits "agc\.rt_bound.*target=0x000000045D550000")
$criticalWriter=@(Hits "agc\.rt_writer_filtered.*target=0x000000045D550000")
$criticalRejected=@(Hits "agc\.rt_writer_rejected.*target=0x000000045D550000")
$contract=@(Hits "\[V74\.0\.2\]\[TEXTURE_CONTRACT\].*45D550000")
$natural=@(Hits "bink2\.natural_guest_movie_observed")
$computeYuv=@(Hits "bink2\.compute_yuv_binding")
$computeFails=@(Hits "Vulkan compute dispatch failed")
$computeNull=@(Hits "compute texture resource remained null")
$failfast=@(Hits "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506")
$deviceLost=@(Hits "VK_ERROR_DEVICE_LOST|DeviceLostException|deviceLost=True")
$shaderErrors=@(Hits "shader.*failed|Unsupported.*opcode|unsupported.*opcode")
$ui=@(Hits "uistartmenu|uifrontend|subscreen_overlay_backing")
$mainLoop=@(Hits "Starting main loop:")
$gather=@(Hits "ResourcePool::GatherResourceFileInfo")
$firstFrame=@(Hits "Vulkan VideoOut presented first frame")
$dcc=@(Hits "\[V74\.0\.4\]\[DCC\]")
$large=@(Hits "\[V74\.0\.4\]\[ALLOC\]")
$threads=@(Hits "guest_thread\.snapshot")
$waits=@(Hits "agc\.wait_suspended")
$gpuWait=@(Hits "\[GPU-WAIT-PROFILE\]|gpu_wait_profile")
$texTrim=@(Hits "\[V74\.0\.8\]\[TEX_CACHE\] trim")

$maxEvent=0
foreach($line in $events){
    if($line -match '\bn=(\d+)'){
        $n=[int]$Matches[1]
        if($n-gt$maxEvent){$maxEvent=$n}
    }
}

$lastTimelineCompleted=0
$lastTimelineSubmit=0
foreach($line in $mem){
    if($line -match 'timeline=(\d+)/(\d+)'){
        $lastTimelineCompleted=[int]$Matches[1]
        $lastTimelineSubmit=[int]$Matches[2]
    }
}

$maxGc=MaxMetric $mem "gc_mb"
$maxHeap=MaxMetric $mem "heap_mb"
$maxFrag=MaxMetric $mem "frag_mb"
$maxAlloc=MaxMetric $mem "alloc2s_mb"
$maxTex=MaxMetric $mem "tex_cache_mb"
$maxDeferred=MaxMetric $mem "tex_deferred_mb"
$maxGuestBuffer=MaxMetric $mem "guest_buffer_mb"
$maxPending=MaxMetric $mem "pending"

$classification="long-horizon-no-natural-bink"
if($failfast.Count-gt 0){
    $classification="clr-failfast-regression"
}elseif($deviceLost.Count-gt 0){
    $classification="device-lost"
}elseif($computeFails.Count-gt 0 -or $computeNull.Count-gt 0){
    $classification="compute-regression"
}elseif($natural.Count-gt 0 -and $computeYuv.Count-gt 0){
    $classification="natural-bink-yuv-binding-reached"
}elseif($natural.Count-gt 0){
    $classification="natural-bink-reached"
}elseif($criticalWriter.Count-gt 0 -and $maxEvent-ge 8192){
    $classification="frontend-gpu-progress-without-bink"
}elseif($maxEvent-ge 8192){
    $classification="gpu-progress-beyond-short-horizon"
}elseif($memoryPressureStop){
    $classification="memory-pressure-long-horizon"
}

@(
    $all |
    Where-Object{
        $_ -match "\[V74\.0\.10\]\[NATIVE_LANE\]|" +
                  "Core\.Res\.TaskManager|NexusRevolution (?:Event|Surveillance)|HighGraphics|" +
                  "\[V74\.0\.8\.1\]\[MEM\]|" +
                  "\[V17\]\[EVENT_FASTPATH\]|" +
                  "agc\.rt_(?:bound|writer_filtered|writer_rejected).*45D550000|" +
                  "\[V74\.0\.2\]\[TEXTURE_CONTRACT\].*45D550000|" +
                  "bink2\.natural_guest_movie_observed|" +
                  "bink2\.compute_yuv_binding|" +
                  "Vulkan compute dispatch failed|" +
                  "compute texture resource remained null|" +
                  "ResourcePool::GatherResourceFileInfo|" +
                  "Starting main loop:|" +
                  "Vulkan VideoOut presented first frame|" +
                  "uistartmenu|uifrontend|subscreen_overlay_backing"
    }
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"LONG_PROGRESS_TIMELINE.txt")) `
    -Encoding UTF8

@(
    "version=74.0.10",
    "classification=$classification",
    "exit_code=$exitCode",
    "memory_pressure_stop=$memoryPressureStop",
    "",
    "[horizon]",
    "configured_hard_horizon_s=600",
    "v7318_reference_natural_result_end_s=479.5",
    "previous_v7408_2_short_horizon_s=120",
    "",
    "[functional]",
    "main_loop_hits=$($mainLoop.Count)",
    "resource_gather_completion_hits=$($gather.Count)",
    "first_frame_hits=$($firstFrame.Count)",
    "max_event_fastpath_n=$maxEvent",
    "final_presenter_timeline=$lastTimelineCompleted/$lastTimelineSubmit",
    "critical_45d_bound_hits=$($criticalBound.Count)",
    "critical_45d_writer_hits=$($criticalWriter.Count)",
    "critical_45d_rejected_hits=$($criticalRejected.Count)",
    "critical_45d_contract_samples=$($contract.Count)",
    "natural_guest_movie_hits=$($natural.Count)",
    "compute_yuv_binding_hits=$($computeYuv.Count)",
    "ui_resource_log_hits=$($ui.Count)",
    "compute_dispatch_fail_hits=$($computeFails.Count)",
    "compute_null_invariant_hits=$($computeNull.Count)",
    "clr_failfast_hits=$($failfast.Count)",
    "device_lost_hits=$($deviceLost.Count)",
    "shader_error_hits=$($shaderErrors.Count)",
    "",
    "[memory]",
    "max_gc_mb=$maxGc",
    "max_heap_mb=$maxHeap",
    "max_fragmented_mb=$maxFrag",
    "max_alloc_per_2s_mb=$maxAlloc",
    "max_texture_cache_mb=$maxTex",
    "max_texture_deferred_mb=$maxDeferred",
    "max_guest_buffer_mb=$maxGuestBuffer",
    "max_pending_submissions=$maxPending",
    "texture_cache_trim_hits=$($texTrim.Count)",
    "dcc_suppression_hits=$($dcc.Count)",
    "large_cpu_snapshot_hits=$($large.Count)",
    ("peak_working_mb={0:F1}" -f ($maxWorking/1MB)),
    ("peak_private_mb={0:F1}" -f ($maxPrivate/1MB)),
    ("peak_gpu_dedicated_mb={0:F1}" -f ($maxGpuDedicated/1MB)),
    ("peak_gpu_shared_mb={0:F1}" -f ($maxGpuShared/1MB)),
    ("peak_system_commit_mb={0:F1}" -f ($maxSystemCommit/1MB)),
    "",
    "[scheduler]",
    "guest_thread_snapshot_lines=$($threads.Count)",
    "suspended_agc_wait_lines=$($waits.Count)",
    "gpu_wait_profile_lines=$($gpuWait.Count)",
    "",
    "[reference-comparison]",
    "V73.18 reached natural ps_studios_logo only at the end of a ~479.5s collection.",
    "V73.18 working/private near 120s was ~14787.5/~20197.4 MiB.",
    "V74.0.8.2 at 120s was ~6100/~11284 MiB steady-state after its transient peak.",
    "The 120s V74.0.8.2 test therefore ended far before the known natural-Bink reference horizon."
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"SUMMARY.txt")) `
    -Encoding UTF8


# V74.0.10 native-lane proof is derived from the same run, not a separate test.
$laneLines=@($all | Where-Object{$_ -match "\[V74\.0\.10\]\[NATIVE_LANE\] enter"})
$taskLines=@($all | Where-Object{$_ -match "guest_thread\.snapshot.*name='Core\.Res\.TaskManager'"})
$nexusEventLines=@($all | Where-Object{$_ -match "guest_thread\.snapshot.*name='NexusRevolution Event'"})
$nexusSurvLines=@($all | Where-Object{$_ -match "guest_thread\.snapshot.*name='NexusRevolution Surveillance'"})
$highExitLines=@($all | Where-Object{$_ -match "Guest thread exited: name='HighGraphics'|name='HighGraphics' state=Exited"})

function Last-ImportsV74010([object[]]$Lines){
    $value=0
    foreach($line in $Lines){
        if(([string]$line) -match '\bimports=(\d+)'){
            $value=[int]$Matches[1]
        }
    }
    return $value
}

$taskFinal=Last-ImportsV74010 $taskLines
$nexusEventFinal=Last-ImportsV74010 $nexusEventLines
$nexusSurvFinal=Last-ImportsV74010 $nexusSurvLines
$laneMax=0
$laneWaitMax=0
foreach($line in $laneLines){
    if(([string]$line) -match '\bmax_observed=(\d+)'){
        $value=[int]$Matches[1]
        if($value-gt$laneMax){$laneMax=$value}
    }
    if(([string]$line) -match '\bwait_ms=(\d+)'){
        $value=[int]$Matches[1]
        if($value-gt$laneWaitMax){$laneWaitMax=$value}
    }
}

@(
    "",
    "[native-lane-v74010]",
    "renderer_lane_enter_logs=$($laneLines.Count)",
    "renderer_lane_max_active=$laneMax",
    "renderer_lane_max_wait_ms=$laneWaitMax",
    "renderer_lane_configured_limit=8",
    "tbb_lane_configured_limit=2",
    "taskmanager_final_imports=$taskFinal",
    "v7409_taskmanager_reference_imports=4",
    "nexus_event_final_imports=$nexusEventFinal",
    "nexus_surveillance_final_imports=$nexusSurvFinal",
    "highgraphics_exit_log_hits=$($highExitLines.Count)",
    "",
    "proof_rule:",
    "- TaskManager >4 proves the old two-slot starvation was removed.",
    "- timeline >1318 / EVENT >2048 / 0x45D writer proves downstream GPU progress.",
    "- natural Bink/YUV is the strongest frontend progression result."
) | Add-Content -LiteralPath (
    [System.IO.Path]::Combine($out,"SUMMARY.txt")) -Encoding UTF8

@(
    $laneLines
    $taskLines
    $nexusEventLines
    $nexusSurvLines
    $highExitLines
) | Set-Content -LiteralPath (
    [System.IO.Path]::Combine($out,"NATIVE_LANE_EVIDENCE.txt")) -Encoding UTF8

$srcDir=[System.IO.Path]::Combine($out,"sources")
[System.IO.Directory]::CreateDirectory($srcDir)|Out-Null
Copy-Item -LiteralPath $presenter `
    -Destination ([System.IO.Path]::Combine($srcDir,"VulkanVideoPresenter.cs")) -Force

$tail=[System.IO.Path]::Combine($out,"RUNTIME_TAIL.txt")
if([System.IO.File]::Exists($stderr)){
    $tailLines=@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)
    if($tailLines.Count-gt 0){
        $start=[Math]::Max(0,$tailLines.Count-1600)
        @($tailLines[$start..($tailLines.Count-1)]) |
            Set-Content -LiteralPath $tail -Encoding UTF8
    }
}

@(
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS=900000",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT=1",
    "SHARPEMU_TRACE_RENDER_TARGET_ADDRESS=0x45D550000",
    "SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB=512",
    "SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB=768",
    "SHARPEMU_VK_GUEST_BUFFER_CACHE_MB=512",
    "SHARPEMU_LOG_DIRECT_MEMORY=1",
    "SHARPEMU_LOG_VMEM=1",
    "SHARPEMU_LOG_VIRTUAL_MEMORY=1",
    "SHARPEMU_LOG_LAZY_COMMIT=1",
    "SHARPEMU_PROFILE_GPU_WAIT=1",
    "SHARPEMU_LOG_VIDEOOUT_FPS=1",
    "SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS=1",
    "bulk AGC/Vulkan per-resource tracing=OFF"
) | Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"TEST_CONFIGURATION.txt")) `
    -Encoding UTF8

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){Remove-Item -LiteralPath $zip -Force}
Compress-Archive `
    -Path ([System.IO.Path]::Combine($out,"*")) `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[V74.0.10] RESULT ZIP: $zip"
Write-Host "[V74.0.10] classification=$classification"
Write-Host "[V74.0.10] event_n=$maxEvent timeline=$lastTimelineCompleted/$lastTimelineSubmit 45D_bound=$($criticalBound.Count) 45D_writer=$($criticalWriter.Count) 45D_rejected=$($criticalRejected.Count) natural=$($natural.Count) yuv=$($computeYuv.Count) compute_fail=$($computeFails.Count) failfast=$($failfast.Count)"
