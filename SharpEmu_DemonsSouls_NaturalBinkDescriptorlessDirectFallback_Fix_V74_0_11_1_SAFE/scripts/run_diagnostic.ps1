param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin",
    [switch]$ForceNewRun
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$native=Get-NativeWorkerPathV74010 $root
$nativeText=[System.IO.File]::ReadAllText($native)

if(-not $nativeText.Contains("SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE")){
    throw "[V74.0.11.1] Diagnostic refused: V74.0.10 native-lane source is not installed."
}

function Get-LastElapsedSeconds {
    param([string]$CsvPath)

    if(-not [System.IO.File]::Exists($CsvPath)){return 0.0}

    $last=$null
    foreach($line in Get-Content -LiteralPath $CsvPath -ErrorAction SilentlyContinue){
        if(-not [string]::IsNullOrWhiteSpace($line) -and
           -not $line.StartsWith("elapsed_s;")){
            $last=$line
        }
    }

    if($null-eq$last){return 0.0}
    $first=($last -split ';')[0]
    $value=0.0

    if([double]::TryParse(
            $first,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$value)){
        return $value
    }

    if([double]::TryParse(
            $first,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::CurrentCulture,
            [ref]$value)){
        return $value
    }

    return 0.0
}

function Find-RecoverableFolder {
    param([string]$Root)

    $folders=@(
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object{
            $_.Name -like "SharpEmu_V74_0_11_NATURAL_BINK_FALLBACK_RESULT_*"
        } |
        Sort-Object LastWriteTime -Descending
    )

    foreach($folder in $folders){
        $stderr=[System.IO.Path]::Combine($folder.FullName,"stderr.log")
        $proc=[System.IO.Path]::Combine($folder.FullName,"PROCESS_OS_TRUTH.csv")

        if([System.IO.File]::Exists($stderr) -and
           [System.IO.File]::Exists($proc)){
            $elapsed=Get-LastElapsedSeconds $proc
            $size=(Get-Item -LiteralPath $stderr).Length

            if($elapsed-ge 60 -and $size-gt 0){
                return [pscustomobject]@{
                    Path=$folder.FullName
                    Elapsed=$elapsed
                    StderrBytes=$size
                }
            }
        }
    }

    return $null
}

function Get-MaxCsv {
    param([string]$Path,[string]$Column)

    if(-not [System.IO.File]::Exists($Path)){return 0.0}
    $rows=@(Import-Csv -LiteralPath $Path -Delimiter ';')
    $max=0.0

    foreach($row in $rows){
        $prop=$row.PSObject.Properties[$Column]
        if($null-eq$prop){continue}
        $raw=[string]$prop.Value
        $value=0.0

        $ok=[double]::TryParse(
            $raw,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$value)

        if(-not $ok){
            $ok=[double]::TryParse(
                $raw,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::CurrentCulture,
                [ref]$value)
        }

        if($ok -and $value-gt$max){$max=$value}
    }

    return $max
}

function Last-RegexInt {
    param(
        [string]$Text,
        [string]$Pattern,
        [int]$Group=1
    )

    $matches=[regex]::Matches($Text,$Pattern)
    if($matches.Count-eq 0){return 0}
    return [int]$matches[$matches.Count-1].Groups[$Group].Value
}

function Max-RegexInt {
    param(
        [string]$Text,
        [string]$Pattern,
        [int]$Group=1
    )

    $max=0
    foreach($m in [regex]::Matches($Text,$Pattern)){
        $value=[int]$m.Groups[$Group].Value
        if($value-gt$max){$max=$value}
    }
    return $max
}

function Finalize-NativeLaneTruth {
    param(
        [string]$Out,
        [double]$Elapsed
    )

    $stderr=[System.IO.Path]::Combine($Out,"stderr.log")
    $stdout=[System.IO.Path]::Combine($Out,"stdout.log")
    $processCsv=[System.IO.Path]::Combine($Out,"PROCESS_OS_TRUTH.csv")
    $gpuCsv=[System.IO.Path]::Combine($Out,"GPU_OS_TRUTH.csv")
    $systemCsv=[System.IO.Path]::Combine($Out,"SYSTEM_MEMORY_TRUTH.csv")
    $nvidiaCsv=[System.IO.Path]::Combine($Out,"NVIDIA_GPU_TRUTH.csv")

    Write-Host "[V74.0.11.1] Finalizing existing logs with single-pass regex analysis..."
    $text=[System.IO.File]::ReadAllText($stderr)

    $eventN=Max-RegexInt $text '\[V17\]\[EVENT_FASTPATH\] n=(\d+)'

    $timelineMatches=[regex]::Matches(
        $text,
        '\[V74\.0\.8\.1\]\[MEM\][^\r\n]*timeline=(\d+)/(\d+)')
    $timelineCompleted=0
    $timelineSubmit=0
    if($timelineMatches.Count-gt 0){
        $last=$timelineMatches[$timelineMatches.Count-1]
        $timelineCompleted=[int]$last.Groups[1].Value
        $timelineSubmit=[int]$last.Groups[2].Value
    }

    $taskMatches=[regex]::Matches(
        $text,
        "guest_thread\.snapshot[^\r\n]*name='Core\.Res\.TaskManager'[^\r\n]*state=(\w+)[^\r\n]*executor=(\w+)[^\r\n]*imports=(\d+)")
    $taskState="missing"
    $taskExecutor="missing"
    $taskFirst=0
    $taskLast=0
    $taskMax=0
    if($taskMatches.Count-gt 0){
        $first=$taskMatches[0]
        $last=$taskMatches[$taskMatches.Count-1]
        $taskFirst=[int]$first.Groups[3].Value
        $taskLast=[int]$last.Groups[3].Value
        $taskState=$last.Groups[1].Value
        $taskExecutor=$last.Groups[2].Value
        foreach($m in $taskMatches){
            $v=[int]$m.Groups[3].Value
            if($v-gt$taskMax){$taskMax=$v}
        }
    }

    $nexusEventLast=Last-RegexInt $text "guest_thread\.snapshot[^\r\n]*name='NexusRevolution Event'[^\r\n]*imports=(\d+)"
    $nexusSurvLast=Last-RegexInt $text "guest_thread\.snapshot[^\r\n]*name='NexusRevolution Surveillance'[^\r\n]*imports=(\d+)"

    $laneEnter=[regex]::Matches($text,'\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*')
    $laneExit=[regex]::Matches($text,'\[V74\.0\.10\]\[NATIVE_LANE\] exit[^\r\n]*')
    $laneMax=Max-RegexInt $text '\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*max_observed=(\d+)'
    $laneWait=Max-RegexInt $text '\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*wait_ms=(\d+)'

    $laneTask=[regex]::Matches(
        $text,
        "\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*name='Core\.Res\.TaskManager'")
    $laneNexusEvent=[regex]::Matches(
        $text,
        "\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*name='NexusRevolution Event'")
    $laneNexusSurv=[regex]::Matches(
        $text,
        "\[V74\.0\.10\]\[NATIVE_LANE\] enter[^\r\n]*name='NexusRevolution Surveillance'")

    $writer45d=[regex]::Matches(
        $text,
        'agc\.rt_writer_filtered[^\r\n]*target=0x000000045D550000').Count
    $bound45d=[regex]::Matches(
        $text,
        'agc\.rt_bound[^\r\n]*target=0x000000045D550000').Count
    $rejected45d=[regex]::Matches(
        $text,
        'agc\.rt_writer_rejected[^\r\n]*target=0x000000045D550000').Count

    $naturalMatches=[regex]::Matches(
        $text,
        "bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'")
    $natural=$naturalMatches.Count
    $naturalFiles=@($naturalMatches | ForEach-Object{$_.Groups[1].Value})
    $yuv=[regex]::Matches($text,'bink2\.compute_yuv_binding').Count

    $fallbackStart=[regex]::Matches(
        $text,
        '\[V74\.0\.11\]\[BINK\] bink2\.descriptorless_direct_fallback_start').Count
    $fallbackFrames=[regex]::Matches(
        $text,
        '\[V74\.0\.11\]\[BINK\] bink2\.descriptorless_direct_frame').Count
    $fallbackEnd=[regex]::Matches(
        $text,
        '\[V74\.0\.11\]\[BINK\] bink2\.descriptorless_direct_fallback_end').Count

    $yuvMissZero=[regex]::Matches(
        $text,
        'bink2\.yuv_pair_not_found[^\r\n]*textures=0 \[\]').Count
    $computeFail=[regex]::Matches($text,'Vulkan compute dispatch failed').Count
    $computeNull=[regex]::Matches($text,'compute texture resource remained null').Count
    $failfast=[regex]::Matches(
        $text,
        'Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506').Count
    $deviceLost=[regex]::Matches(
        $text,
        'VK_ERROR_DEVICE_LOST|DeviceLostException|deviceLost=True').Count

    $highExit=[regex]::Matches(
        $text,
        "Guest thread exited: name='HighGraphics'|name='HighGraphics' state=Exited").Count

    $peakWorking=Get-MaxCsv $processCsv "working_mb"
    $peakPrivate=Get-MaxCsv $processCsv "private_mb"
    $peakGpuDed=Get-MaxCsv $gpuCsv "dedicated_mb"
    $peakGpuShared=Get-MaxCsv $gpuCsv "shared_mb"

    $classification="native-lane-no-downstream-progress"
    if($failfast-gt 0){
        $classification="clr-failfast-regression"
    } elseif($deviceLost-gt 0){
        $classification="device-lost"
    } elseif($computeFail-gt 0 -or $computeNull-gt 0){
        $classification="compute-regression"
    } elseif($natural-gt 1){
        $classification="natural-bink-fallback-advanced-to-next-movie"
    } elseif($natural-gt 0 -and $yuv-gt 0){
        $classification="natural-bink-yuv-bound"
    } elseif($fallbackFrames-ge 8){
        $classification="descriptorless-direct-fallback-rendering"
    } elseif($fallbackStart-gt 0){
        $classification="descriptorless-direct-fallback-started"
    } elseif($natural-gt 0){
        $classification="natural-bink-observed-no-fallback-frames"
    } elseif($writer45d-gt 0){
        $classification="native-lane-restored-45d-producer"
    } elseif($taskMax-gt 4 -and ($eventN-gt 2048 -or $timelineSubmit-gt 1318)){
        $classification="native-lane-starvation-fixed-downstream-progress"
    } elseif($taskMax-gt 4){
        $classification="native-lane-starvation-fixed-taskmanager-only"
    } elseif($laneEnter.Count-gt 0){
        $classification="native-lane-active-taskmanager-still-frozen"
    }

    @(
        "version=74.0.11.1",
        "classification=$classification",
        "recovered_existing_collection=True",
        ("collection_elapsed_s={0:F1}" -f $Elapsed),
        "",
        "[native-lane]",
        "lane_enter_logs=$($laneEnter.Count)",
        "lane_exit_logs=$($laneExit.Count)",
        "lane_max_active=$laneMax",
        "lane_max_wait_ms=$laneWait",
        "lane_taskmanager_enter_hits=$($laneTask.Count)",
        "lane_nexus_event_enter_hits=$($laneNexusEvent.Count)",
        "lane_nexus_surveillance_enter_hits=$($laneNexusSurv.Count)",
        "configured_renderer_resource_limit=8",
        "configured_tbb_limit=2",
        "",
        "[critical-threads]",
        "taskmanager_snapshot_count=$($taskMatches.Count)",
        "taskmanager_first_imports=$taskFirst",
        "taskmanager_last_imports=$taskLast",
        "taskmanager_max_imports=$taskMax",
        "taskmanager_final_state=$taskState",
        "taskmanager_final_executor=$taskExecutor",
        "v7409_taskmanager_reference_imports=4",
        "nexus_event_last_imports=$nexusEventLast",
        "nexus_surveillance_last_imports=$nexusSurvLast",
        "highgraphics_exit_hits=$highExit",
        "",
        "[gpu-frontend]",
        "max_event_fastpath_n=$eventN",
        "v7409_event_reference_n=2048",
        "final_presenter_timeline=$timelineCompleted/$timelineSubmit",
        "v7409_timeline_reference=1318/1318",
        "critical_45d_bound_hits=$bound45d",
        "critical_45d_writer_hits=$writer45d",
        "critical_45d_rejected_hits=$rejected45d",
        "natural_guest_movie_hits=$natural",
        "natural_guest_movie_files=$([string]::Join(',', $naturalFiles))",
        "compute_yuv_binding_hits=$yuv",
        "descriptorless_yuv_miss_textures0_hits=$yuvMissZero",
        "direct_fallback_start_hits=$fallbackStart",
        "direct_fallback_frame_log_hits=$fallbackFrames",
        "direct_fallback_end_hits=$fallbackEnd",
        "",
        "[regression-guards]",
        "compute_dispatch_fail_hits=$computeFail",
        "compute_null_invariant_hits=$computeNull",
        "clr_failfast_hits=$failfast",
        "device_lost_hits=$deviceLost",
        "",
        "[os-peaks]",
        ("peak_working_mb={0:F1}" -f $peakWorking),
        ("peak_private_mb={0:F1}" -f $peakPrivate),
        ("peak_gpu_dedicated_mb={0:F1}" -f $peakGpuDed),
        ("peak_gpu_shared_mb={0:F1}" -f $peakGpuShared)
    ) | Set-Content -LiteralPath (
        [System.IO.Path]::Combine($Out,"SUMMARY.txt")) -Encoding UTF8

    # Extract only the load-bearing evidence without repeatedly scanning in PowerShell.
    $evidenceLines=New-Object System.Collections.Generic.List[string]
    foreach($m in $laneEnter){$evidenceLines.Add($m.Value)}
    foreach($m in $taskMatches){$evidenceLines.Add($m.Value)}
    foreach($m in [regex]::Matches(
            $text,
            "guest_thread\.snapshot[^\r\n]*name='NexusRevolution (?:Event|Surveillance)'[^\r\n]*")){
        $evidenceLines.Add($m.Value)
    }

    $evidenceLines |
        Set-Content -LiteralPath (
            [System.IO.Path]::Combine($Out,"NATIVE_LANE_EVIDENCE.txt")) -Encoding UTF8

    $tailLines=@([System.IO.File]::ReadAllLines($stderr))
    if($tailLines.Count-gt 0){
        $start=[Math]::Max(0,$tailLines.Count-1200)
        @($tailLines[$start..($tailLines.Count-1)]) |
            Set-Content -LiteralPath (
                [System.IO.Path]::Combine($Out,"RUNTIME_TAIL.txt")) -Encoding UTF8
    }

    $zip="$Out.zip"
    if([System.IO.File]::Exists($zip)){
        Remove-Item -LiteralPath $zip -Force
    }

    Write-Host "[V74.0.11.1] Compressing recovered result..."
    Compress-Archive `
        -Path ([System.IO.Path]::Combine($Out,"*")) `
        -DestinationPath $zip `
        -CompressionLevel Optimal

    Write-Host "[V74.0.11.1] RESULT ZIP: $zip"
    Write-Host "[V74.0.11.1] classification=$classification"
    Write-Host "[V74.0.11.1] elapsed=$([Math]::Round($Elapsed))s lane=$($laneEnter.Count) lane_max=$laneMax wait_max=${laneWait}ms TaskManager=$taskFirst->$taskLast(max=$taskMax) Nexus=$nexusEventLast/$nexusSurvLast event=$eventN timeline=$timelineCompleted/$timelineSubmit 45D_writer=$writer45d natural=$natural yuv=$yuv fallback=$fallbackStart/$fallbackFrames/$fallbackEnd compute_fail=$computeFail failfast=$failfast"
}

$recover=$null
if(-not $ForceNewRun){
    $recover=Find-RecoverableFolder $root
}

if($null-ne$recover){
    Write-Host "[V74.0.11.1] RECOVERABLE COLLECTION FOUND:"
    Write-Host "[V74.0.11.1] $($recover.Path)"
    Write-Host "[V74.0.11.1] elapsed=$([Math]::Round($recover.Elapsed,1))s stderr=$([Math]::Round($recover.StderrBytes/1MB,1))MB"
    Write-Host "[V74.0.11.1] The game will NOT run again. Finalizing existing logs."
    Finalize-NativeLaneTruth -Out $recover.Path -Elapsed $recover.Elapsed
    exit 0
}

Write-Host "[V74.0.11.1] No recoverable >=60s collection found."
Write-Host "[V74.0.11.1] Starting a fresh raw collection. Logs are written continuously."

& (Join-Path $PSScriptRoot "run_raw_collection.ps1") `
    -RepositoryRoot $root `
    -Eboot $Eboot

$rc=$LASTEXITCODE

$recover=Find-RecoverableFolder $root
if($null-ne$recover){
    Finalize-NativeLaneTruth -Out $recover.Path -Elapsed $recover.Elapsed
}

exit $rc
