param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_18_1_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_18_1_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_18_1_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_18_1_DEV_BUILD_$stamp.log")

$bc = Join-Path $backupRoot $CliRel
New-Item -ItemType Directory -Force -Path (Split-Path $bc -Parent) | Out-Null
Copy-Item -LiteralPath $CliPath -Destination $bc -Force
Compress-Archive `
    -Path (Join-Path $backupRoot '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $bc -Destination $CliPath -Force
}

try {
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.18.1][MAX_THROUGHPUT_PROFILE]')) {
        $needle = '"[V76.3.18.0][RPCS3_QUEUE_MERGE] " +'
        $markerPos = $t.IndexOf($needle,[StringComparison]::Ordinal)
        if ($markerPos -lt 0) {
            Fail 'V18 runtime marker ausente'
        }

        $consoleStart = $t.LastIndexOf(
            '        Console.Error.WriteLine(',
            $markerPos,
            [StringComparison]::Ordinal)
        if ($consoleStart -lt 0) {
            Fail 'V18 Console marker anchor ausente'
        }

        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $block = @(
            '        // V76.3.18.1 - consolidated maximum-throughput profile.',
            '        // SAFE_MODE keeps V18 queue architecture but disables the',
            '        // new residency/cache aggressiveness and restores 16ms wait fallback.',
            '        var safeModeV763181 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763181_SAFE_MODE"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '',
            '        // ------------------------------------------------------------',
            '        // GPU feed / batching — preserve validated queue semantics.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", safeModeV763181 ? "8" : "16");',
            '        Set("SHARPEMU_PRESERVE_PAYLOAD_BATCH", "1");',
            '        Set("SHARPEMU_COMPUTE_RESOURCE_SETUP_COALESCE", "1");',
            '        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH", "1");',
            '        Set("SHARPEMU_BARRIERED_COMPUTE_BATCH_LIMIT", "4");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '',
            '        // ------------------------------------------------------------',
            '        // Resident shader / pipeline state.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");',
            '        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", safeModeV763181 ? "4096" : "8192");',
            '        Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeModeV763181 ? "512" : "1024");',
            '        Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeModeV763181 ? "256" : "512");',
            '        Set("SHARPEMU_VK_PIPELINE_CACHE", "1");',
            '        Set("SHARPEMU_VK_PIPELINE_CACHE_SAVE_INTERVAL_S", "600");',
            '',
            '        // ------------------------------------------------------------',
            '        // Descriptor/layout hot path.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
            '        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", safeModeV763181 ? "512" : "1024");',
            '',
            '        // ------------------------------------------------------------',
            '        // Immutable shader globals: DEVICE_LOCAL + selective residency.',
            '        // V76.3.3 source comments already encode the safe hot-set learned',
            '        // from the rejected 1024-entry/512MiB experiment.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");',
            '        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");',
            '        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "16");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", safeModeV763181 ? "0" : "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "256");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "128");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MIN_KB", "64");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "4");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "3");',
            '',
            '        // ------------------------------------------------------------',
            '        // VRAM / reusable resource working set. These remain hard byte',
            '        // budgets; they do not preallocate or pin the whole amount.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", safeModeV763181 ? "32" : "128");',
            '        Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeModeV763181 ? "512" : "1024");',
            '        Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeModeV763181 ? "3072" : "4096");',
            '        Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", safeModeV763181 ? "256" : "512");',
            '        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", safeModeV763181 ? "512" : "1024");',
            '',
            '        // ------------------------------------------------------------',
            '        // Avoid blocking the GPU feed on CPU refresh of a still-in-flight',
            '        // writable global. The existing exact timeline decides readiness.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_NONBLOCKING_GLOBAL_REFRESH", safeModeV763181 ? "0" : "1");',
            '',
            '        // ------------------------------------------------------------',
            '        // Wait path: producer-backed wake remains exact/immediate. Only',
            '        // producer-less CPU-write recovery scan is relaxed in MAX mode.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", safeModeV763181 ? "16" : "32");',
            '        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
            '        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_KYTY_CAPACITY_PROBE_US", safeModeV763181 ? "100" : "50");',
            '',
            '        // ------------------------------------------------------------',
            '        // Keep the V18 physical queue/resource policy authoritative.',
            '        // ------------------------------------------------------------',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
            '',
            '        // ------------------------------------------------------------',
            '        // Remove diagnostic/census work from the hot path. V18.1 keeps',
            '        // its own concise runtime markers and PERF counters.',
            '        // ------------------------------------------------------------',
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
            '            "[V76.3.18.1][MAX_THROUGHPUT_PROFILE] " +',
            '            $"mode={(safeModeV763181 ? "safe-v18" : "max")} " +',
            '            "dual_physical=capability-driven async_agc=1 compute_chain=4 " +',
            '            $"draw_train={(safeModeV763181 ? 8 : 16)} cb_pool=256 " +',
            '            $"resident_globals={(safeModeV763181 ? 0 : 1)} resident_shader_max={(safeModeV763181 ? 4096 : 8192)} " +',
            '            $"descriptor_cache={(safeModeV763181 ? 512 : 1024)} pipeline_cache=1024/512 " +',
            '            $"resource_cache_mb=host{(safeModeV763181 ? 32 : 128)}/sampled{(safeModeV763181 ? 512 : 1024)}/standalone{(safeModeV763181 ? 3072 : 4096)}/guest{(safeModeV763181 ? 256 : 512)}/device{(safeModeV763181 ? 512 : 1024)} " +',
            '            $"wait_fallback_ms={(safeModeV763181 ? 16 : 32)} nonblocking_refresh={(safeModeV763181 ? 0 : 1)} traces=hotpath-off");',
            ''
        ) -join $nl

        # Insert before V18 marker, so V18.1's block is after old policies but
        # immediately before the provenance marker it supersedes.
        $t = $t.Insert($consoleStart,$block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.18.1][MAX_THROUGHPUT_PROFILE]',
        'SHARPEMU_V763181_SAFE_MODE',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", safeModeV763181 ? "0" : "1");',
        'Set("SHARPEMU_NONBLOCKING_GLOBAL_REFRESH", safeModeV763181 ? "0" : "1");',
        'Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", safeModeV763181 ? "8" : "16");',
        'Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", safeModeV763181 ? "512" : "1024");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");'
    )) {
        if (-not $check.Contains($m)) {
            Fail "post-merge contract ausente: $m"
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
    Write-Host "[$Tag] presenter_sha256=$(Get-HashLower $PresenterPath)"
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
        Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
