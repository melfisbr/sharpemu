param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_20_2_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_20_2_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_20_2_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_20_2_DEV_BUILD_$stamp.log")

$backupCli = Join-Path $backupRoot $CliRel
New-Item -ItemType Directory -Force -Path (Split-Path $backupCli -Parent) | Out-Null
Copy-Item -LiteralPath $CliPath -Destination $backupCli -Force
Compress-Archive `
    -Path (Join-Path $backupRoot '*') `
    -DestinationPath $backupZip `
    -CompressionLevel Optimal `
    -Force

function Restore-Source {
    Copy-Item -LiteralPath $backupCli -Destination $CliPath -Force
}

try {
    $c = Read-Utf8Preserve $CliPath
    $t = $c.Text
    $already = $t.Contains('[V76.3.20.2][DUAL_QUEUE_DEEP_FEED')

    if (-not $already) {
        $markerNeedle = '"[V76.3.20.1][EVENT_FIRST_WAIT]'
        $pos = $t.IndexOf($markerNeedle, [StringComparison]::Ordinal)
        if ($pos -lt 0) {
            Fail "insertion marker ausente: $markerNeedle"
        }
        $consoleStart = $t.LastIndexOf(
            '        Console.Error.WriteLine(',
            $pos,
            [StringComparison]::Ordinal)
        if ($consoleStart -lt 0) {
            Fail 'Console insertion anchor ausente'
        }

        $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = @(
            '        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "256");',
            '        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "128");',
            '        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "8");',
            '        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "24");',
            '        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
            '        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "1024");',
            '        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
            '        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
            '        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
            '        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.20.2][DUAL_QUEUE_DEEP_FEED] queue=256/128 burst=8 inflight=24 host_lanes=6 producer_scan=1024 compute_chain=4 dual_physical=capability-driven resource_sync=1 V20.0+V20.1=preserved");',
            ''
        )
        $block = ($lines -join $nl) + $nl
        $t = $t.Insert($consoleStart, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check = [IO.File]::ReadAllText($CliPath)
    $must = @(
        '[V76.3.20.2][DUAL_QUEUE_DEEP_FEED]',
        'Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "256");',
        'Set("SHARPEMU_PENDING_GUEST_WORK_MB", "128");',
        'Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "8");',
        'Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "24");',
        'Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
        'Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
        'Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "1024");',
        'Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
        'Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");'
    )
    foreach ($m in $must) {
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
