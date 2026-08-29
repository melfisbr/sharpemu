param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_3_1_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_3_1_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_3_1_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_3_1_DEV_BUILD_$stamp.log")

foreach ($pair in @(@($PresenterPath,$PresenterRel))) {
    $dst = Join-Path $backupRoot $pair[1]
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $pair[0] -Destination $dst -Force
}
Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force

function Restore-Source {
    $src = Join-Path $backupRoot $PresenterRel
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $PresenterPath -Force }
}

try {
    $c = Read-Utf8Preserve $PresenterPath
    $t = $c.Text
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

    $begin = '    // V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_BEGIN'
    $end = '    // V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_END'

    # Idempotent: remove an older copy of this exact revision before rebuilding it.
    $bp = $t.IndexOf($begin,[StringComparison]::Ordinal)
    if ($bp -ge 0) {
        $ep = $t.IndexOf($end,$bp,[StringComparison]::Ordinal)
        if ($ep -lt 0) { Fail 'V21.3.1 end marker ausente' }
        $ep += $end.Length
        while ($ep -lt $t.Length -and ($t[$ep] -eq "`r" -or $t[$ep] -eq "`n")) { $ep++ }
        $t = $t.Remove($bp,$ep-$bp)
    }

    $fieldStartNeedle = '    private static readonly int _producerDependencyClosureSyncScanCapV76383 ='
    $fieldNextNeedle = '    private static int _producerDependencyClosureSyncRemainingV76383;'
    $fs = $t.IndexOf($fieldStartNeedle,[StringComparison]::Ordinal)
    if ($fs -lt 0) { Fail 'closure sync consumer start ausente' }
    $fe = $t.IndexOf($fieldNextNeedle,$fs,[StringComparison]::Ordinal)
    if ($fe -lt 0) { Fail 'closure sync consumer end ausente' }

    $block = @(
        '    // V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_BEGIN',
        '    // V21.3 set the correct environment value, but runtime evidence still',
        '    // showed sync_budget=4096. Make the consumer itself authoritative for',
        '    // PPSA01341 so ModuleInitializer ordering cannot reopen the V21.1 scan.',
        '    private static readonly bool _authoritativeGuestProgressV7632131 =',
        '        InitializeAuthoritativeGuestProgressV7632131();',
        '',
        '    private static bool InitializeAuthoritativeGuestProgressV7632131()',
        '    {',
        '        var disabled = string.Equals(',
        '            Environment.GetEnvironmentVariable("SHARPEMU_V7632131_DISABLE"),',
        '            "1",',
        '            StringComparison.Ordinal);',
        '        var active = false;',
        '        if (!disabled)',
        '        {',
        '            foreach (var arg in Environment.GetCommandLineArgs())',
        '            {',
        '                if (arg.Contains("PPSA01341", StringComparison.OrdinalIgnoreCase))',
        '                {',
        '                    active = true;',
        '                    break;',
        '                }',
        '            }',
        '            if (!active)',
        '            {',
        '                active = string.Equals(',
        '                    Environment.GetEnvironmentVariable("SHARPEMU_TITLE_ID"),',
        '                    "PPSA01341",',
        '                    StringComparison.OrdinalIgnoreCase);',
        '            }',
        '        }',
        '',
        '        Console.Error.WriteLine(',
        '            "[V76.3.21.3.1][AUTHORITATIVE_GUEST_PROGRESS] " +',
        '            $"active={(active ? 1 : 0)} closure_sync_budget={(active ? 512 : -1)} " +',
        '            $"consumer=VulkanVideoPresenter disabled={(disabled ? 1 : 0)}");',
        '        return active;',
        '    }',
        '',
        '    private static readonly int _producerDependencyClosureSyncScanCapV76383 =',
        '        _authoritativeGuestProgressV7632131',
        '            ? 512',
        '            : Math.Clamp(',
        '                int.TryParse(',
        '                    Environment.GetEnvironmentVariable("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN"),',
        '                    out var closureSyncScanV76383) && closureSyncScanV76383 > 0',
        '                    ? closureSyncScanV76383',
        '                    : 512,',
        '                64,',
        '                4096);',
        '    // V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_END',
        ''
    ) -join $nl

    $t = $t.Remove($fs,$fe-$fs).Insert($fs,$block)
    Write-Utf8Preserve $PresenterPath $t $c.HasBom

    $post = [IO.File]::ReadAllText($PresenterPath)
    foreach ($m in @(
        'V76.3.21.3.1_AUTHORITATIVE_CLOSURE_SYNC_BEGIN',
        '[V76.3.21.3.1][AUTHORITATIVE_GUEST_PROGRESS]',
        '_authoritativeGuestProgressV7632131',
        '? 512',
        'SHARPEMU_V7632131_DISABLE'
    )) {
        if (-not $post.Contains($m)) { Fail "post-apply marker ausente: $m" }
    }

    $dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
    if (-not $dotnet) { $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source }
    if (-not $dotnet) { Fail 'dotnet nao encontrado' }

    & $dotnet restore $Project 2>&1 | Tee-Object -FilePath $restoreLog
    if ($LASTEXITCODE -ne 0) { throw "restore exit=$LASTEXITCODE" }

    & $dotnet build $Project -c Debug -r win-x64 --no-restore 2>&1 | Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "build exit=$LASTEXITCODE" }

    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug rid=win-x64"
    Write-Host "[$Tag] backup=$backupZip"
    Write-Host "[$Tag] presenter_sha256=$(Get-HashLower $PresenterPath)"
}
catch {
    $message = $_.Exception.Message
    try { Restore-Source; Write-Host "[$Tag] source restored automatically" -ForegroundColor Yellow } catch {}
    throw "[$Tag] APPLY/BUILD FAILED: $message"
}
