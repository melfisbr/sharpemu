param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_18_0_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_18_0_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_18_0_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_18_0_DEV_BUILD_$stamp.log")

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
    # --------------------------------------------------------------
    # 1. Presenter: exact V17.1 -> V18 queue-capability merge.
    # --------------------------------------------------------------
    $presenterHash = Get-HashLower $PresenterPath
    if ($presenterHash -ne $ExpectedPresenterResult) {
        if ($presenterHash -ne $ExpectedPresenterBaseline) {
            Fail "Presenter mudou apos precheck: $presenterHash"
        }

        $payload = Join-Path $PackageRoot `
            'files\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
        Copy-Item -LiteralPath $payload -Destination $PresenterPath -Force
    }

    if ((Get-HashLower $PresenterPath) -ne $ExpectedPresenterResult) {
        Fail 'Presenter result hash divergente'
    }

    # --------------------------------------------------------------
    # 2. CLI: one final authoritative scheduler block.
    #
    # Old historical markers are intentionally left in source for provenance.
    # This block executes after them and becomes the active title contract.
    # --------------------------------------------------------------
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text

    if (-not $t.Contains('[V76.3.18.0][RPCS3_QUEUE_MERGE]')) {
        $needle = '"[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE] " +'
        $markerPos = $t.IndexOf($needle, [StringComparison]::Ordinal)
        if ($markerPos -lt 0) {
            Fail 'V17.1 marker anchor ausente'
        }

        $consoleStart = $t.LastIndexOf(
            '        Console.Error.WriteLine(',
            $markerPos,
            [StringComparison]::Ordinal)
        if ($consoleStart -lt 0) {
            Fail 'V17.1 Console marker anchor ausente'
        }

        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

        $block = @(
            '        // V76.3.18.0 - consolidated queue architecture.',
            '        // The GPU decides whether dual-physical is possible: Presenter',
            '        // requires >=2 queues in the selected family + compute + timeline.',
            '        // SHARPEMU_V763180_FORCE_SINGLE=1 is the emergency A/B fallback.',
            '        var forceSingleQueueV763180 = string.Equals(',
            '            Environment.GetEnvironmentVariable("SHARPEMU_V763180_FORCE_SINGLE"),',
            '            "1",',
            '            StringComparison.Ordinal);',
            '',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleQueueV763180 ? "0" : "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '        Set("SHARPEMU_BINK_STRICT_RESOURCE_SCOPE", "1");',
            '',
            '        // Preserve the proven V15-V17 execution contract.',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
            '        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
            '        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
            '        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
            '        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
            '        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
            '        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");',
            '        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
            '        Set("SHARPEMU_DEFER_RELEASE_QUEUE_COMPLETION", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
            '        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
            '        Set("SHARPEMU_DISJOINT_COMPUTE_PAIR2", "1");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.18.0][RPCS3_QUEUE_MERGE] " +',
            '            $"mode={(forceSingleQueueV763180 ? "single-safe" : "capability-dual-resource-safe")} " +',
            '            "dcb=graphics-lane acb=compute-lane timeline=1 range_hazards=1 " +',
            '            "async_agc=1 compute_chain=4 cb_pool=256 " +',
            '            "wait_fallback=16ms sideband=off microbatch=on " +',
            '            "queue=192/96 burst=4 inflight=16");',
            ''
        ) -join $nl

        $t = $t.Insert($consoleStart, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    # --------------------------------------------------------------
    # 3. Post-merge contract checks.
    # --------------------------------------------------------------
    $cliCheck = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
        'SHARPEMU_V763180_FORCE_SINGLE',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", forceSingleQueueV763180 ? "0" : "1");',
        'Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
        'Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
        'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
        'Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
        'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");'
    )) {
        if (-not $cliCheck.Contains($m)) {
            Fail "post-merge CLI contract ausente: $m"
        }
    }

    $presenterCheck = [IO.File]::ReadAllText($PresenterPath)
    foreach ($m in @(
        '[V76.3.18.0][QUEUE_ARCHITECTURE]',
        'MaxRecycledGuestCommandBuffers = 256',
        'selectedFamilyQueueCountV1131 >= 2',
        '_computeQueueTimelineSemaphoreV1131'
    )) {
        if (-not $presenterCheck.Contains($m)) {
            Fail "post-merge Presenter contract ausente: $m"
        }
    }

    $agcCheck = [IO.File]::ReadAllText($AgcPath)
    foreach ($m in @(
        'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
        'QueueAsyncAgcSubmissionV763170'
    )) {
        if (-not $agcCheck.Contains($m)) {
            Fail "post-merge Async AGC contract ausente: $m"
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
        Remove-Item -LiteralPath $backupRoot `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
}
