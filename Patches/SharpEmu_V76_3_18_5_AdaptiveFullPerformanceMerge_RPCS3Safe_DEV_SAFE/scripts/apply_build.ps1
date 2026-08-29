param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_18_5_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_18_5_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_18_5_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_18_5_DEV_BUILD_$stamp.log")

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
    # A. PRESENTER — adaptive, no full-source replacement.
    #
    # Recycle command buffers/fences deeply enough to avoid allocator churn
    # while graphics + compute lanes overlap.
    # ==============================================================
    $p = Read-Utf8Preserve $PresenterPath
    $pt = $p.Text

    if (-not $pt.Contains('V76.3.18.5_ADAPTIVE_FULL_PERFORMANCE_MERGE')) {
        $cb = Replace-IntConstantMinimum `
            $pt `
            'MaxRecycledGuestCommandBuffers' `
            256
        $pt = $cb.Text

        $fence = Replace-IntConstantMinimum `
            $pt `
            'MaxRecycledGuestFences' `
            256
        $pt = $fence.Text

        $markerAnchorPattern =
            '(?m)^(?<indent>[ \t]*)private\s+const\s+int\s+' +
            'MaxRecycledGuestCommandBuffers\s*=\s*\d+\s*;[ \t]*$'

        $markerMatch = [regex]::Match($pt, $markerAnchorPattern)
        if (-not $markerMatch.Success) {
            Fail 'Presenter marker insertion anchor ausente'
        }

        $nl = if ($pt.Contains("`r`n")) { "`r`n" } else { "`n" }
        $marker =
            $markerMatch.Value + $nl +
            $markerMatch.Groups['indent'].Value +
            '// V76.3.18.5_ADAPTIVE_FULL_PERFORMANCE_MERGE' + $nl +
            $markerMatch.Groups['indent'].Value +
            '// Deep recycled CB/fence pools; queue/timeline semantics unchanged.'

        $pt =
            $pt.Substring(0, $markerMatch.Index) +
            $marker +
            $pt.Substring($markerMatch.Index + $markerMatch.Length)

        Write-Utf8Preserve $PresenterPath $pt $p.HasBom

        Write-Host (
            "[$Tag] Presenter merge: " +
            "command_buffers=$($cb.Old)->$($cb.New) " +
            "fences=$($fence.Old)->$($fence.New)"
        )
    }

    # ==============================================================
    # B. CLI — final authoritative performance contract at END of Apply().
    # This intentionally supersedes historical tuning flags without deleting
    # provenance markers.
    # ==============================================================
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.18.5][ADAPTIVE_FULL_MERGE]')) {
        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $anchorPattern =
            '(?s)(\r?\n    \}\r?\n\r?\n    private static bool IsDemonsSoulsLaunch\(\))'

        $matches = [regex]::Matches($t, $anchorPattern)
        if ($matches.Count -ne 1) {
            Fail "CLI Apply-end anchor count inesperado: $($matches.Count)"
        }

        $block = @(
            '',
            '        // ============================================================',
            '        // V76.3.18.5 - ADAPTIVE FULL PERFORMANCE MERGE',
            '        // Final title-authoritative policy. Historical markers above',
            '        // remain for provenance, but these values are the active contract.',
            '        // ============================================================',
            '        var forceSingleV763185 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763185_FORCE_SINGLE"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '        var conservativeWait16V763185 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763185_WAIT_SCAN_16MS"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '',
            '        // REAL GPU QUEUE TOPOLOGY',
            '        // Presenter still capability-checks queue-count/compute/timeline.',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleV763185 ? "0" : "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");',
            '',
            '        // FEED ENVELOPE — preserve stable V15-V17 contract.',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
            '        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
            '        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
            '        Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");',
            '        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");',
            '        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '        Set("SHARPEMU_COMPUTE_WRITE_OVERLAP_PAIR_BARRIER", "1");',
            '        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "0");',
            '        Set("SHARPEMU_CLOSED_COMPUTE_SUBMIT_GROUP", "0");',
            '',
            '        // ASYNC AGC — guest submit publishes, dedicated CP parses.',
            '        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '',
            '        // WAIT / PRODUCER — normal path is evidence/latch driven.',
            '        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
            '        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_GATE_QUANTUM_PACKETS", "32");',
            '        Set("SHARPEMU_AGC_GATE_QUANTUM_MS", "1");',
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", conservativeWait16V763185 ? "16" : "32");',
            '        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");',
            '        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
            '        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
            '        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");',
            '',
            '        // The failed V16 sideband stays disabled.',
            '        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '',
            '        // SHADER FRONTEND / RESIDENCY',
            '        Set("SHARPEMU_SHADER_PVM_READ_ACCESS_CACHE", "1");',
            '        Set("SHARPEMU_SHADER_DEFER_GLOBAL_READS", "1");',
            '        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");',
            '        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");',
            '',
            '        // V17.1 saturated global residency at 512 entries (~206 MiB)',
            '        // with thousands of budget fallbacks. Keep the proven hot-admit',
            '        // policy but double the bounded entry/VRAM budget.',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "5");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "3");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "4");',
            '',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
            '        Set("SHARPEMU_SHADER_THREAD_CACHE_SLOTS", "4096");',
            '        Set("SHARPEMU_SHADER_DECODE_CACHE_MAX", "4096");',
            '        Set("SHARPEMU_SHADER_METADATA_CACHE_MAX", "4096");',
            '',
            '        // Parallel compile/prewarm and allocation caches.',
            '        Set("SHARPEMU_VK_PARALLEL_STAGE_COMPILE", "1");',
            '        Set("SHARPEMU_SPIRV_PREWARM_MAX", "512");',
            '        Set("SHARPEMU_SPIRV_PREWARM_MB", "128");',
            '        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
            '        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "600");',
            '',
            '        // CPU guest lanes: proven compact policy, not spread.',
            '        Set("SHARPEMU_CPU_CACHE_AWARE", "1");',
            '        Set("SHARPEMU_CPU_CACHE_POLICY", "compact");',
            '        Set("SHARPEMU_CPU_CACHE_VERIFY", "0");',
            '        Set("SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT", "16");',
            '        Set("SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT", "8");',
            '',
            '        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
            '        Set("SHARPEMU_HOST_TARGET_FPS", "60");',
            '',
            '        // Normal gameplay must not pay diagnostic/logging cost.',
            '        // RUN_4 explicitly overrides the small set needed for profiling.',
            '        SetDefault("SHARPEMU_PROFILE_RENDER", "0");',
            '        SetDefault("SHARPEMU_TRACE_FRAME_STATS", "0");',
            '        SetDefault("SHARPEMU_TRACE_SPIRV_CACHE", "0");',
            '        SetDefault("SHARPEMU_TRACE_COMPUTE_PHASES", "0");',
            '        SetDefault("SHARPEMU_TRACE_DRAW_PHASES", "0");',
            '        SetDefault("SHARPEMU_TRACE_DRAW_RESOURCE_PHASES", "0");',
            '        SetDefault("SHARPEMU_TRACE_ORDERED_ACTION_LATENCY", "0");',
            '        SetDefault("SHARPEMU_TRACE_GPU_SUBMISSION_LATENCY", "0");',
            '        SetDefault("SHARPEMU_TRACE_GUEST_WORK_COMPLETION", "0");',
            '        SetDefault("SHARPEMU_TRACE_RESOURCE_DEPENDENCIES", "0");',
            '        SetDefault("SHARPEMU_TRACE_QUEUE_OPTIMIZER", "0");',
            '        SetDefault("SHARPEMU_TRACE_PM4_PREINDEX_BULK", "0");',
            '        SetDefault("SHARPEMU_TRACE_PRESENT_CADENCE", "0");',
            '        SetDefault("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "0");',
            '        SetDefault("SHARPEMU_TRACE_VULKAN_HOTPATH_DIAGNOSTICS", "0");',
            '        SetDefault("SHARPEMU_TRACE_AGC_HOTPATH_DIAGNOSTICS", "0");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.18.5][ADAPTIVE_FULL_MERGE] " +',
            '            $"queue_mode={(forceSingleV763185 ? "single-safe" : "dual-capability-resource")} " +',
            '            $"wait_fullscan_ms={(conservativeWait16V763185 ? 16 : 32)} " +',
            '            "async_agc=1 chain4=1 cb_pool=256 fence_pool=256 " +',
            '            "global_residency=1024/512MB descriptor_cache=4096 " +',
            '            "resident_shader=2048 parallel_compile=1 prewarm=512/128MB " +',
            '            "host_buffer_cache_mb=256 cpu=compact16/8 " +',
            '            "sideband=off microbatch=on safe_memcpy=1");'
        ) -join $nl

        $m = $matches[0]
        $t =
            $t.Substring(0, $m.Index) +
            $nl +
            $block +
            $m.Value +
            $t.Substring($m.Index + $m.Length)

        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    # ==============================================================
    # C. Final structural proof.
    # ==============================================================
    $presenterCheck = [IO.File]::ReadAllText($PresenterPath)
    foreach ($m in @(
        'V76.3.18.5_ADAPTIVE_FULL_PERFORMANCE_MERGE',
        'MaxRecycledGuestCommandBuffers = 256;',
        'MaxRecycledGuestFences = 256;',
        'selectedFamilyQueueCountV1131',
        '_computeQueueTimelineSemaphoreV1131',
        'SHARPEMU_COMPUTE_CHAIN_MAX_V763171'
    )) {
        if (-not $presenterCheck.Contains($m)) {
            Fail "post-merge Presenter contract ausente: $m"
        }
    }

    $cliCheck = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.18.5][ADAPTIVE_FULL_MERGE]',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleV763185 ? "0" : "1");',
        'Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
        'Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", conservativeWait16V763185 ? "16" : "32");',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");',
        'Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
        'Set("SHARPEMU_VK_PARALLEL_STAGE_COMPILE", "1");',
        'Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
        'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");'
    )) {
        if (-not $cliCheck.Contains($m)) {
            Fail "post-merge CLI contract ausente: $m"
        }
    }

    $agcCheck = [IO.File]::ReadAllText($AgcPath)
    foreach ($m in @(
        'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
        'QueueAsyncAgcSubmissionV763170'
    )) {
        if (-not $agcCheck.Contains($m)) {
            Fail "post-merge AGC contract ausente: $m"
        }
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
    Write-Host "[$Tag] presenter_before_sha256=$RequiredPresenterBaseline"
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
