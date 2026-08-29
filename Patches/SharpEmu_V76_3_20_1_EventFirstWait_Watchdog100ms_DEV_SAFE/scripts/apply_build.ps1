param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_20_1_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_20_1_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_20_1_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_20_1_DEV_BUILD_$stamp.log")

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
    $already = $t.Contains('[V76.3.20.1][EVENT_FIRST_WAIT')

    if (-not $already) {
        $markerNeedle = '"[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY]'
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
            '        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "100");',
            '        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "16");',
            '        Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
            '        Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
            '        Set("SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN", "0");',
            '        Set("SHARPEMU_AGC_DEDICATED_NONBLOCKING_GATE", "1");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.20.1][EVENT_FIRST_WAIT] producer_latch=immediate dedicated_fast=1 submit_evidence=1 owner_drain=0 nonblocking_gate=1 producerless_fullscan_watchdog_ms=100 guest_wait_values=unchanged");',
            ''
        )
        $block = ($lines -join $nl) + $nl
        $t = $t.Insert($consoleStart, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check = [IO.File]::ReadAllText($CliPath)
    $must = @(
        '[V76.3.20.1][EVENT_FIRST_WAIT]',
        'Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "100");',
        'Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "16");',
        'Set("SHARPEMU_DEDICATED_WAIT_DRAIN", "1");',
        'Set("SHARPEMU_AGC_DEDICATED_FAST_ONLY", "1");',
        'Set("SHARPEMU_AGC_SUBMIT_EVIDENCE_WAIT_DRAIN", "1");',
        'Set("SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN", "0");',
        'Set("SHARPEMU_AGC_DEDICATED_NONBLOCKING_GATE", "1");'
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
