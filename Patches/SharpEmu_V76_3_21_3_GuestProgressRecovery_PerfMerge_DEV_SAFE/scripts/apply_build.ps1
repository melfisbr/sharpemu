param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $Patches ("V76_3_21_3_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_3_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_3_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_3_DEV_BUILD_$stamp.log")

$backupCli = Join-Path $backupDir $CliRel
New-Item -ItemType Directory -Force -Path (Split-Path $backupCli -Parent) |
    Out-Null
Copy-Item -LiteralPath $CliPath -Destination $backupCli -Force

Compress-Archive `
    -Path (Join-Path $backupDir '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $backupCli -Destination $CliPath -Force
}

try {
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.21.3][GUEST_PROGRESS_RECOVERY]')) {
        $anchor = '    private static bool IsDemonsSoulsLaunch()'
        $pos = $t.IndexOf($anchor, [StringComparison]::Ordinal)
        if ($pos -lt 0) {
            Fail 'anchor final do Apply nao encontrado'
        }

        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $block = @(
            '        // V76.3.21.3 - guest progress recovery.',
            '        // V21.2 drains Vulkan cleanly but stops guest DCB/ACB production',
            '        // before the first natural ps_studios_logo.bk2 open. Restore the',
            '        // V17.1 scheduler envelope that reached natural Bink requests,',
            '        // while preserving V18+ dual queues and all V21.2 safety fixes.',
            '        Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS", "48");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "300");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_ITEMS", "128");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "32");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER", "1");',
            '        Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");',
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");',
            '',
            '        // Keep the structural improvements that are already proven safe.',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
            '        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
            '        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '        Set("SHARPEMU_SAFE_MEMCOPY_V763151", "1");',
            '',
            '        // Do not mask the regression with host-injected boot movies.',
            '        // The success condition is the guest opening the Bink naturally.',
            '        Set("SHARPEMU_BINK_AUTO_BOOT", "0");',
            '        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");',
            '        Set("SHARPEMU_DS_TITLE_TIMELINE_PASSTHROUGH", "1");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.21.3][GUEST_PROGRESS_RECOVERY] " +',
            '            "work_per_render=1024 producer_scan=512 " +',
            '            "closure=300ms/8x128/1000us microbatch=32 " +',
            '            "compute_chain=4 draw_cb=8 wait_fullscan=16ms " +',
            '            "dual_queue=preserved async_agc=preserved " +',
            '            "snapshot_v212=preserved residency=preserved " +',
            '            "bink=natural-request-only auto_boot=off");',
            '',
            '    }',
            ''
        ) -join $nl

        # We are immediately before the next helper method. The current Apply()
        # closing brace is directly before this anchor. Replace that one brace
        # with our block + closing brace so the new settings are last/authoritative.
        $before = $t.Substring(0, $pos)
        $closePos = $before.LastIndexOf('    }', [StringComparison]::Ordinal)
        if ($closePos -lt 0) {
            Fail 'closing brace do Apply nao encontrado'
        }

        $t = $t.Remove($closePos, 5)
        $t = $t.Insert($closePos, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.21.3][GUEST_PROGRESS_RECOVERY]',
        'Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", "1024");',
        'Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
        'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_AGE_MS", "300");',
        'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
        'Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
        'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH_MAX", "32");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
        'Set("SHARPEMU_DRAW_COMMAND_BUFFER_MAX", "8");',
        'Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_BINK_AUTO_BOOT", "0");'
    )) {
        if (-not $check.Contains($m)) {
            Fail "post-apply contract ausente: $m"
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
    Write-Host "[$Tag] cli_sha256=$(HashLower $CliPath)"
    Write-Host "[$Tag] backup=$backupZip"
    Write-Host "[$Tag] build_log=$buildLog"
}
catch {
    Restore-Source
    Write-Host "[$Tag] rollback=completed backup=$backupZip" `
        -ForegroundColor Yellow
    throw
}
finally {
    if (Test-Path -LiteralPath $backupDir) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}
