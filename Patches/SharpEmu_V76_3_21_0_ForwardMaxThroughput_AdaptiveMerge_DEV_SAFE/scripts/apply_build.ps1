param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_0_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_0_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_0_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_0_DEV_BUILD_$stamp.log")

$bp = Join-Path $backupRoot $PresenterRel
$ba = Join-Path $backupRoot $AgcRel
$bc = Join-Path $backupRoot $CliRel

foreach ($p in @($bp,$ba,$bc)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
}

Copy-Item -LiteralPath $PresenterPath -Destination $bp -Force
Copy-Item -LiteralPath $AgcPath -Destination $ba -Force
Copy-Item -LiteralPath $CliPath -Destination $bc -Force

Compress-Archive `
    -Path (Join-Path $backupRoot '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $bp -Destination $PresenterPath -Force
    Copy-Item -LiteralPath $ba -Destination $AgcPath -Force
    Copy-Item -LiteralPath $bc -Destination $CliPath -Force
}

try {
    # ==============================================================
    # A. PRESENTER FORWARD MERGE
    # ==============================================================
    $p = Read-Utf8Preserve $PresenterPath
    $pt = $p.Text

    # A1. Keep RPCS3-style reusable host pools at least 256.
    $pt = [regex]::Replace(
        $pt,
        'private\s+const\s+int\s+MaxRecycledGuestCommandBuffers\s*=\s*(\d+)\s*;',
        {
            param($m)
            $v = [int]$m.Groups[1].Value
            $n = [Math]::Max(256,$v)
            return "private const int MaxRecycledGuestCommandBuffers = $n;"
        },
        1)

    $pt = [regex]::Replace(
        $pt,
        'private\s+const\s+int\s+MaxRecycledGuestFences\s*=\s*(\d+)\s*;',
        {
            param($m)
            $v = [int]$m.Groups[1].Value
            $n = [Math]::Max(256,$v)
            return "private const int MaxRecycledGuestFences = $n;"
        },
        1)

    # A2. Three host frames in flight in MAX mode; exact fences/timelines still
    # protect slot reuse. SAFE mode keeps the historical value 2.
    if (-not $pt.Contains('V76.3.21.0_FRAMES_IN_FLIGHT')) {
        $old = '        private const int MaxFramesInFlight = 2;'
        if ($pt.Contains($old)) {
            $nl = if ($pt.Contains("`r`n")) { "`r`n" } else { "`n" }
            $new = @(
                '        // V76.3.21.0_FRAMES_IN_FLIGHT',
                '        // Increase host CPU/GPU overlap without removing the existing',
                '        // per-slot fence/timeline reuse contract.',
                '        private static readonly int MaxFramesInFlight =',
                '            Math.Clamp(',
                '                int.TryParse(',
                '                    Environment.GetEnvironmentVariable(',
                '                        "SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210"),',
                '                    out var framesInFlightV763210)',
                '                    ? framesInFlightV763210',
                '                    : 2,',
                '                2,',
                '                4);'
            ) -join $nl
            $pt = $pt.Replace($old,$new)
        }
        elseif (-not $pt.Contains('SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210')) {
            Fail 'MaxFramesInFlight anchor mudou; recusando patch estrutural'
        }
    }

    Write-Utf8Preserve $PresenterPath $pt $p.HasBom

    # ==============================================================
    # B. FINAL AUTHORITATIVE TITLE PROFILE
    # ==============================================================
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.21.0][FORWARD_MAX_MERGE]')) {
        $methodAnchor = '    private static bool IsDemonsSoulsLaunch()'
        $methodPos = $t.IndexOf($methodAnchor,[StringComparison]::Ordinal)
        if ($methodPos -lt 0) {
            Fail 'CLI final Apply() anchor ausente'
        }

        $insertPos = $t.LastIndexOf(
            '    }',
            $methodPos,
            [StringComparison]::Ordinal)
        if ($insertPos -lt 0) {
            Fail 'CLI Apply() closing brace nao localizada'
        }

        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $block = @(
            '',
            '        // ============================================================',
            '        // V76.3.21.0 - FORWARD MAX THROUGHPUT ADAPTIVE MERGE',
            '        // Final authoritative profile after every historical bootstrap.',
            '        // ============================================================',
            '        var safeModeV763210 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763210_SAFE_MODE"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '',
            '        // Physical queue architecture: keep V18/V20 real dual queue.',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");',
            '',
            '        // Queue envelope proven stable across V20.3-V20.5.',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
            '        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
            '        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
            '        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");',
            '        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");',
            '',
            '        // Guest CPU -> async AGC CP separation.',
            '        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '',
            '        // Persistent command recording / bounded compute continuity.',
            '        Set("SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210", safeModeV763210 ? "2" : "3");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", safeModeV763210 ? "8" : "16");',
            '        Set("SHARPEMU_COMPUTE_SHARED_BATCH", "1");',
            '        Set("SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE", "1");',
            '        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");',
            '        Set("SHARPEMU_CLOSED_COMPUTE_GROUP", "0");',
            '',
            '        // Collapse large 27x15x72-style dispatches into fewer host',
            '        // command records. Device workgroup limits remain authoritative.',
            '        Set("SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE", "1");',
            '        Set("SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE_MAX_GROUPS", "65536");',
            '        Set("SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION", safeModeV763210 ? "64" : "128");',
            '',
            '        // V20.4 watched producer fastpath: exact producer evidence first.',
            '        Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");',
            '        Set("SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE", "1");',
            '        Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");',
            '        Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
            '        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");',
            '',
            '        // Event/evidence-driven wait path. Full memory scan remains a',
            '        // producer-less CPU-write/watchdog fallback, not normal progress.',
            '        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
            '        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", safeModeV763210 ? "16" : "32");',
            '        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");',
            '        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");',
            '        Set("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");',
            '        Set("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");',
            '        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
            '',
            '        // Dependency-driven producer continuation.',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
            '        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");',
            '',
            '        // V20.5 resident global hot set / prepared immutable resources.',
            '        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");',
            '        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");',
            '        Set("SHARPEMU_SHADER_RESOURCE_SINGLEFLIGHT", "1");',
            '        Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");',
            '        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");',
            '        Set("SHARPEMU_NONBLOCKING_GLOBAL_REFRESH", "1");',
            '',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", safeModeV763210 ? "1024" : "1536");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");',
            '',
            '        // Resident shaders + descriptor/pipeline state.',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
            '        Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeModeV763210 ? "512" : "1024");',
            '        Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeModeV763210 ? "256" : "512");',
            '        Set("SHARPEMU_VK_PIPELINE_CACHE", "1");',
            '        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "600");',
            '',
            '        // Shader frontend caches / compilation separation.',
            '        Set("SHARPEMU_SHADER_RESOURCE_THREAD_CACHE", "4096");',
            '        Set("SHARPEMU_SHADER_SHARED_DECODE_CACHE_ENTRIES", "4096");',
            '        Set("SHARPEMU_SHADER_SHARED_METADATA_CACHE_ENTRIES", "4096");',
            '        Set("SHARPEMU_VK_PARALLEL_STAGE_COMPILE", "1");',
            '        Set("SHARPEMU_SPIRV_PREWARM_MAX", "512");',
            '        Set("SHARPEMU_SPIRV_PREWARM_MB", "128");',
            '',
            '        // Reusable host/VRAM working sets. These are caps, not eager',
            '        // allocation requests; guest visibility rules still choose memory.',
            '        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
            '        Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeModeV763210 ? "768" : "1024");',
            '        Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeModeV763210 ? "3072" : "4096");',
            '        Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", safeModeV763210 ? "384" : "512");',
            '        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");',
            '',
            '        // Ryzen 9 3900: keep proven compact policy rather than spreading',
            '        // shader workers over every SMT lane.',
            '        Set("SHARPEMU_CPU_CACHE_POLICY", "compact");',
            '        Set("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT", "16");',
            '        Set("SHARPEMU_RENDERER_RESOURCE_NATIVE_WORKER_MAX_CONCURRENT", "8");',
            '',
            '        // Failed/obsolete experiments remain explicitly disabled.',
            '        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
            '',
            '        // Remove census/debug work from normal hot paths.',
            '        Set("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "0");',
            '        Set("SHARPEMU_TRACE_RESOURCE_DEPENDENCIES", "0");',
            '        Set("SHARPEMU_COMPUTE_PAIR_HAZARD_CENSUS", "0");',
            '        Set("SHARPEMU_COMPUTE_RESOURCE_OVERLAP_CENSUS", "0");',
            '        Set("SHARPEMU_TRACE_DRAW_RESOURCE_PHASES", "0");',
            '        Set("SHARPEMU_TRACE_GUEST_IMAGE_SHADER_ADDRS", "0");',
            '        Set("SHARPEMU_LOG_AGC_SHADER", "0");',
            '        Set("SHARPEMU_LOG_VK_SHADER", "0");',
            '        Set("SHARPEMU_LOG_VK_COMPUTE_RESOURCES", "0");',
            '        Set("SHARPEMU_LOG_VK_RESOURCES", "0");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.21.0][FORWARD_MAX_MERGE] " +',
            '            $"mode={(safeModeV763210 ? "safe" : "max")} " +',
            '            $"frames_in_flight={(safeModeV763210 ? 2 : 3)} dual_queue=resource-timeline async_agc=1 " +',
            '            $"draw_cb={(safeModeV763210 ? 8 : 16)} chain4=1 compute_z={(safeModeV763210 ? 64 : 128)} " +',
            '            $"wait_fullscan_ms={(safeModeV763210 ? 16 : 32)} watched_producer=1 " +',
            '            $"residency_entries={(safeModeV763210 ? 1024 : 1536)} residency_mb=512 " +',
            '            "resident_shader=2048 descriptors=4096 pipeline_cache=1024/512 " +',
            '            "prewarm=512/128MB resource_cache=256/1024/4096/512/1024 " +',
            '            "nonblocking_global_refresh=1 cpu=compact16/8 hot_traces=off");',
            ''
        ) -join $nl

        $t = $t.Insert($insertPos,$block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    # ==============================================================
    # C. POST-MERGE VALIDATION
    # ==============================================================
    $presenterCheck = [IO.File]::ReadAllText($PresenterPath)
    foreach ($m in @(
        'SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210',
        'MaxRecycledGuestCommandBuffers',
        'MaxRecycledGuestFences',
        'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH',
        'SHARPEMU_SHADER_GLOBAL_RESIDENCY',
        'SHARPEMU_GPU_RESIDENT_SHADER_V1180'
    )) {
        Require-Marker $presenterCheck $m 'post-merge Presenter'
    }

    $cliCheck = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.21.0][FORWARD_MAX_MERGE]',
        'SHARPEMU_V763210_SAFE_MODE',
        'Set("SHARPEMU_VK_FRAMES_IN_FLIGHT_V763210", safeModeV763210 ? "2" : "3");',
        'Set("SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION", safeModeV763210 ? "64" : "128");',
        'Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", safeModeV763210 ? "1024" : "1536");',
        'Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
        'Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
        'Set("SHARPEMU_NONBLOCKING_GLOBAL_REFRESH", "1");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");'
    )) {
        Require-Marker $cliCheck $m 'post-merge CLI'
    }

    Push-Location $Repo
    try {
        & dotnet restore $Project -r win-x64 *>&1 |
            Tee-Object -FilePath $restoreLog
        if ($LASTEXITCODE -ne 0) {
            throw "restore falhou exit=$LASTEXITCODE"
        }

        & dotnet build `
            $Project `
            -c Debug `
            -r win-x64 `
            --no-restore *>&1 |
            Tee-Object -FilePath $buildLog
        if ($LASTEXITCODE -ne 0) {
            throw "build Debug falhou exit=$LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug"
    Write-Host "[$Tag] presenter_before_sha256=$(Get-HashLower $bp)"
    Write-Host "[$Tag] presenter_after_sha256=$(Get-HashLower $PresenterPath)"
    Write-Host "[$Tag] agc_sha256=$(Get-HashLower $AgcPath)"
    Write-Host "[$Tag] cli_sha256=$(Get-HashLower $CliPath)"
    Write-Host "[$Tag] backup=$backupZip"
    Write-Host "[$Tag] build_log=$buildLog"
}
catch {
    Restore-Source
    Write-Host "[$Tag] rollback=completed backup=$backupZip" -ForegroundColor Yellow
    throw
}
finally {
    if (Test-Path -LiteralPath $backupRoot) {
        Remove-Item -LiteralPath $backupRoot `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
}
