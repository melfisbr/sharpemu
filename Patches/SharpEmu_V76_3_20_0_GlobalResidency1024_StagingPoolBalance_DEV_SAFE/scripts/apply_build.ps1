param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_20_0_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_20_0_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_20_0_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_20_0_DEV_BUILD_$stamp.log")

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
    $already = $t.Contains('[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY')

    if (-not $already) {
        $markerNeedle = '"[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE]'
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
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");',
            '        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");',
            '        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
            '        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "768");',
            '',
            '        Console.Error.WriteLine(',
            '            "[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY] entries=1024 resident_mb=384 host_pool_mb=256 device_pool_mb=768 admission=V19-unchanged dual_queue=preserved waits=unchanged");',
            ''
        )
        $block = ($lines -join $nl) + $nl
        $t = $t.Insert($consoleStart, $block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check = [IO.File]::ReadAllText($CliPath)
    $must = @(
        '[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY]',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1024");',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "384");',
        'Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");',
        'Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "768");'
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
