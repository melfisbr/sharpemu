param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$text=[System.IO.File]::ReadAllText($presenter)

foreach($marker in @(
    "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
    "SHARPEMU_V74_0_8_TEXTURE_RESOURCE_RESIDENCY",
    "SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH",
    "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
    "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
)){
    if(-not $text.Contains($marker)){
        throw "[V74.0.8.1] Diagnostic refused; missing marker: $marker"
    }
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.8.1] EBOOT missing: $Eboot"
}

$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){
    throw "[V74.0.8.1] Wrong EBOOT. expected=$expected actual=$actual"
}

$dll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.8.1] SharpEmu.dll missing: $dll"
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_8_1_FULL_RUNTIME_TRUTH_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$processCsv=[System.IO.Path]::Combine($out,"PROCESS_OS_TRUTH.csv")
$gpuCsv=[System.IO.Path]::Combine($out,"GPU_OS_TRUTH.csv")
$systemCsv=[System.IO.Path]::Combine($out,"SYSTEM_MEMORY_TRUTH.csv")
$nvidiaCsv=[System.IO.Path]::Combine($out,"NVIDIA_GPU_TRUTH.csv")

"elapsed_s;process_count;working_mb;private_mb;virtual_mb;paged_mb;handles;threads;cpu_s;cpu_pct;io_read_mb_s;io_write_mb_s" |
    Set-Content -LiteralPath $processCsv -Encoding ASCII

"elapsed_s;dedicated_mb;shared_mb;total_committed_mb;gpu_util_pct;gpu_counter_available" |
    Set-Content -LiteralPath $gpuCsv -Encoding ASCII

"elapsed_s;available_mb;commit_mb;commit_limit_mb;paged_pool_mb;nonpaged_pool_mb;cache_mb" |
    Set-Content -LiteralPath $systemCsv -Encoding ASCII

"elapsed_s;gpu_util_pct;memory_used_mb;memory_total_mb;temperature_c;power_w;available" |
    Set-Content -LiteralPath $nvidiaCsv -Encoding ASCII

$variables=@(
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT",
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

    $working=0L
    $private=0L
    $virtual=0L
    $paged=0L
    $handles=0L
    $threads=0L
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
        } catch {}
    }

    $cpuPct=0.0
    if($ElapsedSinceSample-gt 0){
        $cpuDelta=[Math]::Max(0.0,$cpu-$PreviousCpu)
        $cpuPct=
            ($cpuDelta/$ElapsedSinceSample) /
            [Math]::Max([Environment]::ProcessorCount,1) * 100.0
    }

    $readRate=0L
    $writeRate=0L
    try{
        $perf=@(
            Get-CimInstance `
                Win32_PerfFormattedData_PerfProc_Process `
                -ErrorAction Stop |
            Where-Object{$ProcessIds -contains [int]$_.IDProcess}
        )

        foreach($row in $perf){
            $readRate += [int64]$row.IOReadBytesPersec
            $writeRate += [int64]$row.IOWriteBytesPersec
        }
    } catch {}

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

    $dedicated=0L
    $shared=0L
    $committed=0L
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
                    if($null-ne$row.DedicatedUsage){
                        $dedicated += [int64]$row.DedicatedUsage
                    }
                    if($null-ne$row.SharedUsage){
                        $shared += [int64]$row.SharedUsage
                    }
                    if($null-ne$row.TotalCommitted){
                        $committed += [int64]$row.TotalCommitted
                    }
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
    } catch {}

    [pscustomobject]@{
        Dedicated=$dedicated
        Shared=$shared
        Committed=$committed
        Util=[Math]::Min($util,100.0)
        Available=$available
    }
}

function Get-SystemMemoryTruth {
    $available=0L
    $committed=0L
    $commitLimit=0L
    $paged=0L
    $nonpaged=0L
    $cache=0L

    try{
        $m=Get-CimInstance `
            Win32_PerfFormattedData_PerfOS_Memory `
            -ErrorAction Stop

        $available=[int64]$m.AvailableMBytes * 1MB
        $committed=[int64]$m.CommittedBytes
        $commitLimit=[int64]$m.CommitLimit
        $paged=[int64]$m.PoolPagedBytes
        $nonpaged=[int64]$m.PoolNonpagedBytes
        $cache=[int64]$m.CacheBytes
    } catch {
        try{
            $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $available=[int64]$os.FreePhysicalMemory * 1KB
        } catch {}
    }

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
            $parts=@($line -split ',' | ForEach-Object{$_.Trim()})
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
    } catch {}

    [pscustomobject]@{
        Available=$available
        Util=$util
        Used=$used
        Total=$total
        Temp=$temp
        Power=$power
    }
}

$started=[DateTime]::UtcNow
$deadline=$started.AddSeconds(120)
$maxWorking=0L
$maxPrivate=0L
$maxGpuDedicated=0L
$maxGpuShared=0L
$maxSystemCommit=0L
$memoryPressureStop=$false
$exitCode=""
$previousCpu=0.0
$previousSample=$started
$zeroSamples=0

try{
    # Functional/cache settings.
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="600000"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="1"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="512"
    $env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    $env:SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="512"

    # Aggregate truths enabled simultaneously.
    $env:SHARPEMU_LOG_DIRECT_MEMORY="1"
    $env:SHARPEMU_LOG_VMEM="1"
    $env:SHARPEMU_LOG_VIRTUAL_MEMORY="1"
    $env:SHARPEMU_LOG_LAZY_COMMIT="1"
    $env:SHARPEMU_PROFILE_GPU_WAIT="1"
    $env:SHARPEMU_PROFILE_GPU_WAIT_REPORT_S="2"
    $env:SHARPEMU_LOG_VIDEOOUT_FPS="1"
    $env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS="1"

    # Explicitly keep high-volume per-resource/per-instruction tracing off.
    # The aggregate counters above answer the same questions without changing
    # the workload enough to invalidate the measurement.
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

    Write-Host "[V74.0.8.1] FULL RUNTIME TRUTH starting."
    Write-Host "[V74.0.8.1] One run measures GC, process commit, system commit, VRAM, GPU utilization, Vulkan caches, direct/virtual memory, GPU waits, scheduler, FPS, compute and Bink."
    Write-Host "[V74.0.8.1] duration=120s."
    Write-Host "[V74.0.8.1] safety stop=>18GiB working or >24GiB private for ~8s."
    Write-Host "[V74.0.8.1] High-volume per-resource traces intentionally OFF; aggregate truth counters are ON."

    $args='"{0}" "{1}"' -f $dll,$Eboot
    $launcher=Start-Process `
        -FilePath "dotnet" `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $pressureSamples=0
    $lastConsole=[DateTime]::MinValue

    while([DateTime]::UtcNow-lt$deadline){
        Start-Sleep -Seconds 1
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
            $elapsed,
            $proc.Count,
            ($proc.Working/1MB),
            ($proc.Private/1MB),
            ($proc.Virtual/1MB),
            ($proc.Paged/1MB),
            $proc.Handles,
            $proc.Threads,
            $proc.Cpu,
            $proc.CpuPct,
            ($proc.ReadRate/1MB),
            ($proc.WriteRate/1MB)) |
            Add-Content -LiteralPath $processCsv -Encoding ASCII

        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5}" -f
            $elapsed,
            ($gpu.Dedicated/1MB),
            ($gpu.Shared/1MB),
            ($gpu.Committed/1MB),
            $gpu.Util,
            $gpu.Available) |
            Add-Content -LiteralPath $gpuCsv -Encoding ASCII

        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1};{5:F1};{6:F1}" -f
            $elapsed,
            ($sys.Available/1MB),
            ($sys.Committed/1MB),
            ($sys.CommitLimit/1MB),
            ($sys.Paged/1MB),
            ($sys.Nonpaged/1MB),
            ($sys.Cache/1MB)) |
            Add-Content -LiteralPath $systemCsv -Encoding ASCII

        ("{0:F1};{1};{2};{3};{4};{5:F1};{6}" -f
            $elapsed,
            $nv.Util,
            $nv.Used,
            $nv.Total,
            $nv.Temp,
            $nv.Power,
            $nv.Available) |
            Add-Content -LiteralPath $nvidiaCsv -Encoding ASCII

        if($proc.Count-eq 0){
            $zeroSamples++
        } else {
            $zeroSamples=0
        }

        if($proc.Working-gt 18GB -or $proc.Private-gt 24GB){
            $pressureSamples++
        } else {
            $pressureSamples=0
        }

        if($pressureSamples-ge 8){
            $memoryPressureStop=$true
            Write-Host "[V74.0.8.1] MEMORY SAFETY STOP: intentionally terminating after comprehensive samples."
            break
        }

        if($now-ge$lastConsole.AddSeconds(10)){
            $lastConsole=$now
            Write-Host (
                "[V74.0.8.1] t={0:F0}s work={1:F0}MB private={2:F0}MB gpu_ded={3:F0}MB gpu_shared={4:F0}MB gpu={5:F0}% sys_commit={6:F0}MB" -f
                $elapsed,
                ($proc.Working/1MB),
                ($proc.Private/1MB),
                ($gpu.Dedicated/1MB),
                ($gpu.Shared/1MB),
                $gpu.Util,
                ($sys.Committed/1MB))
        }

        $logText=""
        if([System.IO.File]::Exists($stderr)){
            try{$logText=[System.IO.File]::ReadAllText($stderr)}catch{}
        }

        if($logText.IndexOf(
                "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code",
                [System.StringComparison]::Ordinal)-ge 0 -or
           $logText.IndexOf("0x80131506",[System.StringComparison]::OrdinalIgnoreCase)-ge 0){
            Write-Host "[V74.0.8.1] CLR FailFast regression detected."
            break
        }

        if($zeroSamples-ge 3 -and $elapsed-gt 10){
            break
        }
    }

    try{
        $launcher.Refresh()
        if($launcher.HasExited){$exitCode=$launcher.ExitCode}else{$exitCode="diagnostic-stop"}
    }catch{$exitCode="unknown"}

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
    $max=0L
    foreach($line in $Lines){
        if($line -match ([regex]::Escape($Name)+'=(\d+)')){
            $value=[int64]$Matches[1]
            if($value-gt$max){$max=$value}
        }
    }
    return $max
}

$mem=@(Hits "\[V74\.0\.8\.1\]\[MEM\]")
$texAdd=@(Hits "\[V74\.0\.8\]\[TEX_CACHE\] add")
$texTrim=@(Hits "\[V74\.0\.8\]\[TEX_CACHE\] trim")
$gimg=@(Hits "\[V74\.0\.7\]\[GIMG_CACHE\]")
$computeFails=@(Hits "Vulkan compute dispatch failed")
$computeNull=@(Hits "compute texture resource remained null")
$events=@(Hits "\[V17\]\[EVENT_FASTPATH\]")
$failfast=@(Hits "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506")
$natural=@(Hits "bink2\.natural_guest_movie_observed")
$computeYuv=@(Hits "bink2\.compute_yuv_binding")
$dcc=@(Hits "\[V74\.0\.4\]\[DCC\]")
$large=@(Hits "\[V74\.0\.4\]\[ALLOC\]")
$direct=@(Hits "\[LOADER\]\[TRACE\] allocate_(?:main_)?direct")
$vmem=@(Hits "Allocated .*0x|Mapped segment:|Backed fixed range gap:")
$lazy=@(Hits "lazy|Lazy")
$gpuWait=@(Hits "\[GPU-WAIT-PROFILE\]|gpu_wait_profile|wait.*suspension")
$threadSnapshots=@(Hits "guest_thread\.snapshot")
$fps=@(Hits "fps|FPS")
$deviceLost=@(Hits "VK_ERROR_DEVICE_LOST|DeviceLostException|deviceLost=True")
$shaderError=@(Hits "shader.*failed|Unsupported.*opcode|unsupported.*opcode|SPIR-V.*fail")
$mainLoop=@(Hits "Starting main loop:")
$firstFrame=@(Hits "Vulkan VideoOut presented first frame")
$uiRead=@(Hits "uistartmenu|uifrontend|subscreen_overlay_backing")
$movie=@(Hits "ps_studios_logo|attract_movie|natural_guest_movie|first_frame_primed")

# Direct memory total requested bytes.
$directRequested=0UL
foreach($line in $direct){
    if($line -match 'len=0x([0-9A-Fa-f]+)'){
        try{
            $directRequested += [Convert]::ToUInt64($Matches[1],16)
        }catch{}
    }
}

# Max raw EVENT_FASTPATH n.
$maxEvent=0
foreach($line in $events){
    if($line -match '\bn=(\d+)'){
        $n=[int]$Matches[1]
        if($n-gt$maxEvent){$maxEvent=$n}
    }
}

$maxGc=MaxMetric $mem "gc_mb"
$maxHeap=MaxMetric $mem "heap_mb"
$maxFrag=MaxMetric $mem "frag_mb"
$maxAlloc=MaxMetric $mem "alloc2s_mb"
$maxTex=MaxMetric $mem "tex_cache_mb"
$maxDeferred=MaxMetric $mem "tex_deferred_mb"
$maxSampled=MaxMetric $mem "sampled_mb"
$maxGuestBuffer=MaxMetric $mem "guest_buffer_mb"
$maxPendingImg=MaxMetric $mem "pending_img_mb"
$maxPending=MaxMetric $mem "pending"
$maxAbandoned=MaxMetric $mem "abandoned"
$maxBatch=MaxMetric $mem "batch_resources"
$maxVirtual=MaxMetric $mem "virtual_mb"

$class="full-runtime-truth-captured"
if($failfast.Count-gt 0){
    $class="clr-failfast-regression"
}elseif($deviceLost.Count-gt 0){
    $class="device-lost"
}elseif($computeFails.Count-gt 0 -or $computeNull.Count-gt 0){
    $class="compute-regression"
}elseif($memoryPressureStop){
    $class="memory-pressure-with-full-truth"
}elseif($natural.Count-gt 0 -and $computeYuv.Count-gt 0){
    $class="natural-bink-compute-yuv-active"
}

@(
    $all |
    Where-Object{
        $_ -match "\[V74\.0\.8\.1\]\[MEM\]|" +
                  "\[V74\.0\.8\]\[TEX_CACHE\]|" +
                  "\[V74\.0\.7\]\[GIMG_CACHE\]|" +
                  "\[V74\.0\.4\]\[(?:DCC|ALLOC)\]|" +
                  "\[GPU-WAIT-PROFILE\]|" +
                  "guest_thread\.snapshot|" +
                  "allocate_(?:main_)?direct|" +
                  "Vulkan compute dispatch failed|" +
                  "compute texture resource remained null|" +
                  "\[V17\]\[EVENT_FASTPATH\]|" +
                  "Vulkan VideoOut presented first frame|" +
                  "Starting main loop:|" +
                  "bink2\.natural_guest_movie_observed|" +
                  "bink2\.compute_yuv_binding|" +
                  "uistartmenu|uifrontend|subscreen_overlay_backing"
    }
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"FULL_RUNTIME_TIMELINE.txt")) `
    -Encoding UTF8

@(
    "version=74.0.8.1",
    "classification=$class",
    "exit_code=$exitCode",
    "memory_pressure_stop=$memoryPressureStop",
    "",
    "[functional]",
    "main_loop_hits=$($mainLoop.Count)",
    "first_frame_hits=$($firstFrame.Count)",
    "max_event_fastpath_n=$maxEvent",
    "compute_dispatch_fail_hits=$($computeFails.Count)",
    "compute_null_invariant_hits=$($computeNull.Count)",
    "clr_failfast_hits=$($failfast.Count)",
    "device_lost_hits=$($deviceLost.Count)",
    "shader_error_hits=$($shaderError.Count)",
    "natural_guest_movie_hits=$($natural.Count)",
    "compute_yuv_binding_hits=$($computeYuv.Count)",
    "ui_resource_log_hits=$($uiRead.Count)",
    "movie_lifecycle_log_hits=$($movie.Count)",
    "",
    "[memory-internal]",
    "mem_telemetry_lines=$($mem.Count)",
    "max_gc_mb=$maxGc",
    "max_gc_heap_mb=$maxHeap",
    "max_gc_fragmented_mb=$maxFrag",
    "max_alloc_per_2s_mb=$maxAlloc",
    "max_texture_cache_mb=$maxTex",
    "max_texture_deferred_mb=$maxDeferred",
    "texture_cache_add_logs=$($texAdd.Count)",
    "texture_cache_trim_logs=$($texTrim.Count)",
    "max_sampled_guest_image_mb=$maxSampled",
    "guest_image_cache_logs=$($gimg.Count)",
    "max_guest_buffer_mb=$maxGuestBuffer",
    "max_pending_guest_image_data_mb=$maxPendingImg",
    "max_pending_submissions=$maxPending",
    "max_abandoned_submissions=$maxAbandoned",
    "max_batch_resources=$maxBatch",
    "max_process_virtual_mb_internal=$maxVirtual",
    "",
    "[guest-memory]",
    "direct_memory_allocation_calls=$($direct.Count)",
    "direct_memory_requested_mb=$([Math]::Round($directRequested/1MB,1))",
    "vmem_mapping_log_hits=$($vmem.Count)",
    "lazy_commit_log_hits=$($lazy.Count)",
    "",
    "[scheduler-gpu]",
    "guest_thread_snapshot_lines=$($threadSnapshots.Count)",
    "gpu_wait_profile_lines=$($gpuWait.Count)",
    "video_fps_log_hits=$($fps.Count)",
    "",
    "[texture-provenance]",
    "dcc_suppression_hits=$($dcc.Count)",
    "large_cpu_snapshot_hits=$($large.Count)",
    "",
    "[os-peak]",
    ("peak_process_tree_working_mb={0:F1}" -f ($maxWorking/1MB)),
    ("peak_process_tree_private_mb={0:F1}" -f ($maxPrivate/1MB)),
    ("peak_gpu_dedicated_mb={0:F1}" -f ($maxGpuDedicated/1MB)),
    ("peak_gpu_shared_mb={0:F1}" -f ($maxGpuShared/1MB)),
    ("peak_system_commit_mb={0:F1}" -f ($maxSystemCommit/1MB)),
    "",
    "CSV_FILES:",
    "PROCESS_OS_TRUTH.csv",
    "GPU_OS_TRUTH.csv",
    "SYSTEM_MEMORY_TRUTH.csv",
    "NVIDIA_GPU_TRUTH.csv",
    "",
    "Interpretation rule:",
    "- GC high -> managed allocation producer.",
    "- tex_cache/deferred high -> Vulkan image lifetime/fence.",
    "- GPU dedicated/shared high with low internal caches -> other Vulkan/native allocation.",
    "- process private high with GC/GPU caches low -> guest direct-memory/native commit.",
    "- pending/batch/timeline divergence -> GPU submission/back-pressure.",
    "- all memory stable but black -> functional render/provenance/UI blocker."
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"SUMMARY.txt")) `
    -Encoding UTF8

# Source + environment truth.
$srcDir=[System.IO.Path]::Combine($out,"sources")
[System.IO.Directory]::CreateDirectory($srcDir)|Out-Null
Copy-Item -LiteralPath $presenter `
    -Destination ([System.IO.Path]::Combine($srcDir,"VulkanVideoPresenter.cs")) -Force

Get-ChildItem Env:SHARPEMU_* |
    Sort-Object Name |
    Format-Table -AutoSize |
    Out-String -Width 4096 |
    Set-Content -LiteralPath (
        [System.IO.Path]::Combine($out,"SHARPEMU_ENV_EFFECTIVE.txt")) -Encoding UTF8

$tail=[System.IO.Path]::Combine($out,"RUNTIME_TAIL.txt")
if([System.IO.File]::Exists($stderr)){
    $lines=@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)
    if($lines.Count-gt 0){
        $start=[Math]::Max(0,$lines.Count-1200)
        @($lines[$start..($lines.Count-1)]) |
            Set-Content -LiteralPath $tail -Encoding UTF8
    }
}

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive `
    -Path ([System.IO.Path]::Combine($out,"*")) `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[V74.0.8.1] RESULT ZIP: $zip"
Write-Host "[V74.0.8.1] classification=$class"
Write-Host "[V74.0.8.1] gc_max=${maxGc}MB tex_max=${maxTex}MB deferred_max=${maxDeferred}MB guestbuf_max=${maxGuestBuffer}MB pending_img_max=${maxPendingImg}MB gpu_ded_peak=$([Math]::Round($maxGpuDedicated/1MB))MB direct_requested=$([Math]::Round($directRequested/1MB))MB event_n=$maxEvent compute_fail=$($computeFails.Count) failfast=$($failfast.Count) natural=$($natural.Count)"
