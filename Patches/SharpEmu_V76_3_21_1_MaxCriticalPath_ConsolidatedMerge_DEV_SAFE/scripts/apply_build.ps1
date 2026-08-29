param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_1_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_1_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_1_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_1_DEV_BUILD_$stamp.log")

$backupAgc = Join-Path $backupRoot $AgcRel
$backupCli = Join-Path $backupRoot $CliRel

New-Item -ItemType Directory -Force `
    -Path (Split-Path $backupAgc -Parent) | Out-Null
New-Item -ItemType Directory -Force `
    -Path (Split-Path $backupCli -Parent) | Out-Null

Copy-Item -LiteralPath $AgcPath -Destination $backupAgc -Force
Copy-Item -LiteralPath $CliPath -Destination $backupCli -Force

Compress-Archive `
    -Path (Join-Path $backupRoot '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $backupAgc -Destination $AgcPath -Force
    Copy-Item -LiteralPath $backupCli -Destination $CliPath -Force
}

try {
    # ==============================================================
    # 1. AGC: widen only the read-only planned-producer discovery.
    #    No packet is reordered or executed here.
    # ==============================================================
    $a = Read-Utf8Preserve $AgcPath
    $at = $a.Text

    if (-not $at.Contains('V76.3.21.1_PLANNED_PRODUCER_QUERY_DEPTH')) {
        $fieldAnchor = '    public static long V11714PlannedProducerQueryCount;'
        if (-not $at.Contains($fieldAnchor)) {
            Fail 'AGC producer query field anchor ausente'
        }

        $nl = if ($at.Contains("`r`n")) { "`r`n" } else { "`n" }

        $fields = @(
            '    // V76.3.21.1_PLANNED_PRODUCER_QUERY_DEPTH',
            '    // The previous 64-entry read-only provenance window can miss a',
            '    // still-planned WRITE_DATA/RELEASE_MEM when the producer history',
            '    // is larger than the window. Expand discovery without changing',
            '    // PM4 FIFO, label values or producer completion semantics.',
            '    private static readonly int _plannedProducerQueryScanV763211 =',
            '        Math.Clamp(',
            '            int.TryParse(',
            '                Environment.GetEnvironmentVariable(',
            '                    "SHARPEMU_PLANNED_PRODUCER_QUERY_SCAN"),',
            '                out var plannedProducerQueryScanV763211) &&',
            '                plannedProducerQueryScanV763211 > 0',
            '                ? plannedProducerQueryScanV763211',
            '                : 64,',
            '            64,',
            '            4096);',
            '    private static readonly int _agedProducerQueryScanV763211 =',
            '        Math.Clamp(',
            '            int.TryParse(',
            '                Environment.GetEnvironmentVariable(',
            '                    "SHARPEMU_AGED_PRODUCER_QUERY_SCAN"),',
            '                out var agedProducerQueryScanV763211) &&',
            '                agedProducerQueryScanV763211 > 0',
            '                ? agedProducerQueryScanV763211',
            '                : 64,',
            '            64,',
            '            4096);',
            ''
        ) -join $nl

        $at = $at.Replace(
            $fieldAnchor,
            $fields + $fieldAnchor)

        $oldLoop = 'for (var probe = 0; probe < 64; probe++)'

        $at = Replace-InMethodOnce `
            $at `
            'public static bool HasLivePlannedWaitProducerV11714(' `
            $oldLoop `
            'for (var probe = 0; probe < _plannedProducerQueryScanV763211; probe++)' `
            'HasLivePlannedWaitProducerV11714'

        $at = Replace-InMethodOnce `
            $at `
            'public static bool TryGetAgedLivePlannedWaitProducerV76380(' `
            $oldLoop `
            'for (var probe = 0; probe < _agedProducerQueryScanV763211; probe++)' `
            'TryGetAgedLivePlannedWaitProducerV76380'

        Write-Utf8Preserve $AgcPath $at $a.HasBom
    }

    # ==============================================================
    # 2. CLI: final authoritative V21.1 profile.
    #    V20.2 deep-feed and V20.1 100ms wait experiments stay reverted.
    # ==============================================================
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]')) {
        $markerNeedle = '"[V76.3.21.0][FORWARD_MAX_MERGE] " +'
        $markerPos = $t.IndexOf(
            $markerNeedle,
            [StringComparison]::Ordinal)

        if ($markerPos -lt 0) {
            Fail 'V21.0 marker ausente para merge'
        }

        # Insert after the entire V21 Console.Error.WriteLine statement so
        # V21.1 is the last authoritative policy in this title profile.
        $statementEnd = $t.IndexOf(
            ');',
            $markerPos,
            [StringComparison]::Ordinal)

        if ($statementEnd -lt 0) {
            Fail 'fim do marker V21.0 nao encontrado'
        }

        $insertPos = $statementEnd + 2
        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $block = @(
            '',
            '',
            '        // V76.3.21.1 - consolidated maximum critical-path profile.',
            '        // SHARPEMU_V763211_DISABLE=1 restores the V21.0 policy',
            '        // without source rollback for immediate A/B.',
            '        var disableV763211 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763211_DISABLE"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '',
            '        if (!disableV763211)',
            '        {',
            '            // Keep the proven balanced queue envelope. V20.2 deep feed',
            '            // (256/128, burst8, inflight24) remains intentionally reverted.',
            '            Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
            '            Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
            '            Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
            '            Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '            Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
            '',
            '            // Real dual Vulkan lanes + range/timeline synchronization.',
            '            Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
            '            Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '            Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '            Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");',
            '',
            '            // Async AGC command processor remains authoritative.',
            '            Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '            Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '',
            '            // Producer critical path: discover earlier and keep the',
            '            // exact producer queue moving FIFO until the watched packet.',
            '            Set("SHARPEMU_PLANNED_PRODUCER_QUERY_SCAN", "256");',
            '            Set("SHARPEMU_AGED_PRODUCER_QUERY_SCAN", "1024");',
            '            Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
            '            Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "4096");',
            '            Set("SHARPEMU_PLANNED_PRODUCER_QUEUE_PRIORITY", "1");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE", "1");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "50");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_LIFETIME_MS", "5000");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN", "4096");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "16");',
            '            Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "250");',
            '',
            '            // Event-first wait wakeups. Full scan remains only a bounded',
            '            // producer-less/CPU-write recovery path.',
            '            Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "32");',
            '            Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
            '            Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
            '            Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
            '            Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");',
            '            Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");',
            '            Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");',
            '            Set("SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER", "1");',
            '            Set("SHARPEMU_KYTY_INLINE_WRITE_DATA", "1");',
            '',
            '            // Larger safe command trains. Every compute edge still passes',
            '            // the existing hazard proof and retains the broad barrier.',
            '            Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "8");',
            '            Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");',
            '            Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "32");',
            '            Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");',
            '            Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '            Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "64");',
            '            Set("SHARPEMU_FIFO_PAYLOAD_TRAIN_MAX", "1");',
            '            Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '            Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");',
            '            Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "4096");',
            '            Set("SHARPEMU_COMPUTE_Z_SLICES_PER_SUBMISSION", "128");',
            '            Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
            '            Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");',
            '            Set("SHARPEMU_DEFERRED_FOLLOWUP_SPIN_BREAK", "1");',
            '            Set("SHARPEMU_RELEASE_MEM_QUEUE_COMPLETION_ONLY", "1");',
            '            Set("SHARPEMU_LOCAL_TEXTURE_PAYLOAD_DEDUP", "1");',
            '',
            '            // Keep V21 cache/residency capacities. Current traces show',
            '            // these caches are not capacity-bound, so no blind VRAM growth.',
            '            Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");',
            '            Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");',
            '            Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", "1024");',
            '            Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", "512");',
            '            Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
            '            Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1536");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");',
            '            Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");',
            '            Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
            '            Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");',
            '            Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", "512");',
            '            Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", "1024");',
            '            Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", "4096");',
            '            Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");',
            '            Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
            '            Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");',
            '',
            '            // Preserve the title-specific memory safety fix.',
            '            Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
            '        }',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.21.1][MAX_CRITICAL_PATH_MERGE] " +',
            '            $"mode={(disableV763211 ? "V21-baseline" : "max-critical")} " +',
            '            "queue=192/96 burst=4 inflight=16 dual=resource-timeline async_agc=1 " +',
            '            "producer_query=256/1024 producer_scan=4096 closure_age_ms=50 " +',
            '            "closure=16x128/250us wait_fullscan_ms=32 " +',
            '            "compute_chain=8 draw_cb=32 ordered_microbatch=64 " +',
            '            "residency=1536/512MB shaders=2048 descriptors=4096 " +',
            '            "sideband=off control_lane=off safe_memcpy=1");'
        ) -join $nl

        $t = $t.Insert($insertPos, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    # ==============================================================
    # 3. Structural proof
    # ==============================================================
    $agcCheck = [IO.File]::ReadAllText($AgcPath)
    foreach ($m in @(
        'V76.3.21.1_PLANNED_PRODUCER_QUERY_DEPTH',
        'SHARPEMU_PLANNED_PRODUCER_QUERY_SCAN',
        'SHARPEMU_AGED_PRODUCER_QUERY_SCAN',
        'probe < _plannedProducerQueryScanV763211',
        'probe < _agedProducerQueryScanV763211'
    )) {
        if (-not $agcCheck.Contains($m)) {
            Fail "post-apply AGC contract ausente: $m"
        }
    }

    $cliCheck = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]',
        'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "50");',
        'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "16");',
        'Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "4096");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "8");',
        'Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "32");',
        'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "64");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
        'Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");'
    )) {
        if (-not $cliCheck.Contains($m)) {
            Fail "post-apply CLI contract ausente: $m"
        }
    }

    # ==============================================================
    # 4. Debug build
    # ==============================================================
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
    Write-Host "[$Tag] agc_sha256=$(Get-HashLower $AgcPath)"
    Write-Host "[$Tag] presenter_sha256=$(Get-HashLower $PresenterPath)"
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
