param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_2_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_2_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_2_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_2_DEV_BUILD_$stamp.log")

$bp = Join-Path $backupRoot $PresenterRel
$bc = Join-Path $backupRoot $CliRel

New-Item -ItemType Directory -Force -Path (Split-Path $bp -Parent) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $bc -Parent) | Out-Null

Copy-Item -LiteralPath $PresenterPath -Destination $bp -Force
Copy-Item -LiteralPath $CliPath -Destination $bc -Force

Compress-Archive `
    -Path (Join-Path $backupRoot '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $bp -Destination $PresenterPath -Force
    Copy-Item -LiteralPath $bc -Destination $CliPath -Force
}

try {
    $c = Read-Utf8Preserve $PresenterPath
    $t = $c.Text
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

    if (-not $t.Contains('V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS')) {
        # ----------------------------------------------------------
        # 1) One sparse diagnostic counter.
        # ----------------------------------------------------------
        $fieldAnchor =
            '        private static long _v74051GlobalRefreshDeferTraceCount;' + $nl

        if (-not $t.Contains($fieldAnchor)) {
            Fail 'field anchor _v74051GlobalRefreshDeferTraceCount ausente'
        }

        $fieldReplacement =
            $fieldAnchor +
            '        // V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS' + $nl +
            '        private static long _v763212PartialGlobalSnapshotCount;' + $nl

        $t = Replace-Unique `
            $t `
            $fieldAnchor `
            $fieldReplacement `
            'global-refresh-counter'

        # ----------------------------------------------------------
        # 2) Crash site: partial snapshot must never create
        #    Data.AsSpan(0, logical Length).
        # ----------------------------------------------------------
        $oldRefresh = Normalize-Newlines @'
                var sourceV74051 =
                    guestBuffer.Data.AsSpan(
                        0,
                        guestBuffer.Length);
                var shadowV74051 =
                    allocationV74051.Shadow.AsSpan(
                        checked((int)guestOffsetV74051),
                        guestBuffer.Length);

                var needsRefreshV74051 =
                    !sourceV74051.SequenceEqual(shadowV74051);

                if (!needsRefreshV74051 &&
                    _guestMemory is not null &&
                    guestBuffer.Length > 0)
'@ $nl

        $newRefresh = Normalize-Newlines @'
                // V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS
                //
                // A global binding can describe the complete guest range while
                // carrying only a prefix/deferred CPU snapshot. Treat every
                // Data.Length < Length descriptor like V117.12's zero-byte
                // deferred descriptor and consult live guest memory instead.
                var partialSnapshotV763212 =
                    guestBuffer.Length > 0 &&
                    guestBuffer.Data.Length < guestBuffer.Length;
                ReadOnlySpan<byte> sourceV74051 =
                    partialSnapshotV763212
                        ? ReadOnlySpan<byte>.Empty
                        : guestBuffer.Data.AsSpan(
                            0,
                            guestBuffer.Length);
                var shadowV74051 =
                    allocationV74051.Shadow.AsSpan(
                        checked((int)guestOffsetV74051),
                        guestBuffer.Length);

                var needsRefreshV74051 =
                    partialSnapshotV763212
                        ? _guestMemory?.TryCompare(
                            guestBuffer.BaseAddress,
                            shadowV74051) != true
                        : !sourceV74051.SequenceEqual(shadowV74051);

                if (partialSnapshotV763212)
                {
                    var partialCountV763212 = Interlocked.Increment(
                        ref _v763212PartialGlobalSnapshotCount);
                    if (partialCountV763212 <= 64 ||
                        (partialCountV763212 &
                         (partialCountV763212 - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V76.3.21.2][GLOBAL_SNAPSHOT_REPAIR] " +
                            $"count={partialCountV763212} " +
                            $"phase=refresh-check " +
                            $"queue={_activeGuestQueue.Name} " +
                            $"submission={_activeGuestQueue.SubmissionId} " +
                            $"base=0x{guestBuffer.BaseAddress:X16} " +
                            $"snapshot_bytes={guestBuffer.Data.Length} " +
                            $"logical_bytes={guestBuffer.Length} " +
                            $"action=live-guest-compare");
                    }
                }

                if (!needsRefreshV74051 &&
                    !partialSnapshotV763212 &&
                    _guestMemory is not null &&
                    guestBuffer.Length > 0)
'@ $nl

        $t = Replace-Unique `
            $t `
            $oldRefresh `
            $newRefresh `
            'TryPrepareWritableGlobalRefresh-partial-snapshot'

        # ----------------------------------------------------------
        # 3) Writable resource creation: generalize the existing
        #    V117.12 deferred-live-read path from Data.Length==0 to
        #    every partial snapshot.
        # ----------------------------------------------------------
        $oldDeferred = Normalize-Newlines @'
            var deferredLiveReadV11712 =
                guestBuffer.Data.Length == 0 &&
                guestBuffer.Length > 0;
'@ $nl

        $newDeferred = Normalize-Newlines @'
            // V76.3.21.2: a non-empty prefix is still a deferred
            // snapshot when the logical shader range is larger.
            var deferredLiveReadV11712 =
                guestBuffer.Length > 0 &&
                guestBuffer.Data.Length < guestBuffer.Length;
'@ $nl

        $t = Replace-Unique `
            $t `
            $oldDeferred `
            $newDeferred `
            'CreateGlobalBufferResource-deferred-partial'

        # ----------------------------------------------------------
        # 4) Read-only resource creation: route partial snapshots into
        #    the existing live-read / persistent-residency path.
        # ----------------------------------------------------------
        $oldReadOnly = Normalize-Newlines @'
            if (guestBuffer.Data.Length == 0 &&
                guestBuffer.Length > 0)
'@ $nl

        $newReadOnly = Normalize-Newlines @'
            if (guestBuffer.Length > 0 &&
                guestBuffer.Data.Length < guestBuffer.Length)
'@ $nl

        $t = Replace-Unique `
            $t `
            $oldReadOnly `
            $newReadOnly `
            'CreateVersionedReadOnlyGlobalBufferResource-partial'

        Write-Utf8Preserve $PresenterPath $t $c.HasBom
    }

    # --------------------------------------------------------------
    # 5) Add a final profile marker only. Do NOT alter V21.1 tuning.
    # --------------------------------------------------------------
    $cc = Read-Utf8Preserve $CliPath
    $cli = $cc.Text
    $cliNl = if ($cli.Contains("`r`n")) { "`r`n" } else { "`n" }

    if (-not $cli.Contains('[V76.3.21.2][GLOBAL_SNAPSHOT_BOUNDS]')) {
        $needle = '"[V76.3.21.1][MAX_CRITICAL_PATH_MERGE] " +'
        $pos = $cli.IndexOf($needle, [StringComparison]::Ordinal)
        if ($pos -lt 0) {
            Fail 'V21.1 profile marker ausente'
        }

        $consoleStart = $cli.LastIndexOf(
            '        Console.Error.WriteLine(',
            $pos,
            [StringComparison]::Ordinal)

        if ($consoleStart -lt 0) {
            Fail 'V21.1 Console marker anchor ausente'
        }

        $marker = @(
            '        Console.Error.WriteLine(',
            '            "[V76.3.21.2][GLOBAL_SNAPSHOT_BOUNDS] " +',
            '            "partial_snapshot=live-deferred no_span_overrun=1 " +',
            '            "nonblocking_global_refresh=preserved " +',
            '            "dual_queue=preserved async_agc=preserved compute_chain8=preserved " +',
            '            "residency1536=preserved draw_cb32=preserved waits=preserved");',
            ''
        ) -join $cliNl

        $cli = $cli.Insert($consoleStart, $marker)
        Write-Utf8Preserve $CliPath $cli $cc.HasBom
    }

    # --------------------------------------------------------------
    # Structural post-check.
    # --------------------------------------------------------------
    $presenterCheck = [IO.File]::ReadAllText($PresenterPath)
    foreach ($m in @(
        'V76.3.21.2_GLOBAL_SNAPSHOT_BOUNDS',
        '_v763212PartialGlobalSnapshotCount',
        'partialSnapshotV763212',
        'guestBuffer.Data.Length < guestBuffer.Length',
        '[V76.3.21.2][GLOBAL_SNAPSHOT_REPAIR]',
        'TryPrepareWritableGlobalRefreshV74051(',
        'CreateGlobalBufferResource(',
        'CreateVersionedReadOnlyGlobalBufferResource('
    )) {
        if (-not $presenterCheck.Contains($m)) {
            Fail "post-transform Presenter contract ausente: $m"
        }
    }

    $cliCheck = [IO.File]::ReadAllText($CliPath)
    foreach ($m in @(
        '[V76.3.21.2][GLOBAL_SNAPSHOT_BOUNDS]',
        '[V76.3.21.1][MAX_CRITICAL_PATH_MERGE]',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");'
    )) {
        if (-not $cliCheck.Contains($m)) {
            Fail "post-transform CLI contract ausente: $m"
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
