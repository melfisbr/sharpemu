param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_4_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_4_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_4_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_4_DEV_BUILD_$stamp.log")

if (-not (Test-Path -LiteralPath $AgcPath -PathType Leaf)) { Fail "AGC source ausente: $AgcPath" }
$backupAgc = Join-Path $backupRoot $AgcRel
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupAgc) | Out-Null
$sourceHashBefore = Get-HashLower $AgcPath
Copy-Item -LiteralPath $AgcPath -Destination $backupAgc -Force
if (-not (Test-Path -LiteralPath $backupAgc -PathType Leaf)) { Fail "backup AGC nao criado: $backupAgc" }
$backupHash = Get-HashLower $backupAgc
if ($backupHash -ne $sourceHashBefore) { Fail "backup SHA256 divergente source=$sourceHashBefore backup=$backupHash" }
Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
Write-Host "[$Tag] BACKUP PASSED source=$AgcPath sha256=$sourceHashBefore zip=$backupZip"

function Restore-Source {
    if (Test-Path -LiteralPath $backupAgc) { Copy-Item -LiteralPath $backupAgc -Destination $AgcPath -Force }
}

function Get-MethodRange([string]$Text,[string]$Signature) {
    $start = $Text.IndexOf($Signature,[StringComparison]::Ordinal)
    if ($start -lt 0) { Fail "method signature ausente: $Signature" }
    $next = $Text.IndexOf('    [SysAbiExport(', $start + $Signature.Length, [StringComparison]::Ordinal)
    if ($next -lt 0) { $next = $Text.Length }
    [pscustomobject]@{ Start=$start; End=$next }
}

function Insert-BeforeMethodNeedle([string]$Text,[string]$Signature,[string]$Needle,[string]$InsertText) {
    $r = Get-MethodRange $Text $Signature
    $pos = $Text.LastIndexOf($Needle, $r.End - 1, $r.End - $r.Start, [StringComparison]::Ordinal)
    if ($pos -lt $r.Start) { Fail "needle ausente em $Signature : $Needle" }
    $Text.Insert($pos,$InsertText)
}

try {
    $c = Read-Utf8Preserve $AgcPath
    $t = $c.Text
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

    if (-not $t.Contains('V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN')) {
        $anchor = '    [SysAbiExport(' + $nl + '        Nid = "wr23dPKyWc0",'
        $anchorPos = $t.IndexOf($anchor,[StringComparison]::Ordinal)
        if ($anchorPos -lt 0) { Fail 'helper insertion anchor wr23dPKyWc0 ausente' }

        $helper = @(
'    // V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN',
'    // Normal runs can lose forward progress while diagnostic logging changes host',
'    // scheduling enough to escape the same point. Do not fabricate guest GPU work:',
'    // only yield the current host worker when it has built many real PM4 packets',
'    // for several milliseconds without a completed AGC driver submit.',
'    private static readonly bool _v763214AgcPublishFairness =',
'        IsDemonsSoulsV763214() &&',
'        !string.Equals(',
'            Environment.GetEnvironmentVariable("SHARPEMU_V763214_DISABLE"),',
'            "1",',
'            StringComparison.Ordinal);',
'    private static long _v763214BuilderOps;',
'    private static long _v763214BuilderSinceSubmit;',
'    private static long _v763214DriverSubmits;',
'    private static long _v763214FairnessYields;',
'    private static long _v763214LastSubmitTicks = System.Diagnostics.Stopwatch.GetTimestamp();',
'    private static int _v763214ProfileLogged;',
'',
'    private static bool IsDemonsSoulsV763214()',
'    {',
'        foreach (var arg in Environment.GetCommandLineArgs())',
'        {',
'            if (arg.Contains("PPSA01341", StringComparison.OrdinalIgnoreCase))',
'            {',
'                return true;',
'            }',
'        }',
'',
'        return string.Equals(',
'            Environment.GetEnvironmentVariable("SHARPEMU_TITLE_ID"),',
'            "PPSA01341",',
'            StringComparison.OrdinalIgnoreCase);',
'    }',
'',
'    private static bool IsPowerOfTwoV763214(long value) =>',
'        value > 0 && (value & (value - 1)) == 0;',
'',
'    private static void LogAgcPublishFairnessProfileV763214()',
'    {',
'        if (System.Threading.Interlocked.CompareExchange(ref _v763214ProfileLogged, 1, 0) != 0)',
'        {',
'            return;',
'        }',
'',
'        Console.Error.WriteLine(',
'            "[V76.3.21.4][AGC_PUBLISH_FAIRNESS] " +',
'            $"active={(_v763214AgcPublishFairness ? 1 : 0)} builder_threshold=512 gap_ms=4 " +',
'            "yield_stride=128 mode=cooperative-host-yield guest_pm4=unchanged " +',
'            "waits=unchanged ordering=unchanged sync512=preserved");',
'    }',
'',
'    private static void NoteAgcBuilderV763214(string kind)',
'    {',
'        if (!_v763214AgcPublishFairness)',
'        {',
'            return;',
'        }',
'',
'        LogAgcPublishFairnessProfileV763214();',
'        var total = System.Threading.Interlocked.Increment(ref _v763214BuilderOps);',
'        var sinceSubmit = System.Threading.Interlocked.Increment(ref _v763214BuilderSinceSubmit);',
'        var lastSubmit = System.Threading.Volatile.Read(ref _v763214LastSubmitTicks);',
'        var gapMs = System.Diagnostics.Stopwatch.GetElapsedTime(lastSubmit).TotalMilliseconds;',
'        var yielded = false;',
'        long yields = System.Threading.Volatile.Read(ref _v763214FairnessYields);',
'',
'        if (sinceSubmit >= 512 && gapMs >= 4.0 && (sinceSubmit & 127) == 0)',
'        {',
'            System.Threading.Thread.Yield();',
'            yields = System.Threading.Interlocked.Increment(ref _v763214FairnessYields);',
'            yielded = true;',
'        }',
'',
'        if (total <= 16 || IsPowerOfTwoV763214(total) ||',
'            (yielded && (yields <= 16 || IsPowerOfTwoV763214(yields))))',
'        {',
'            Console.Error.WriteLine(',
'                $"[V76.3.21.4][AGC_MEANINGFUL_PROGRESS] phase=builder kind={kind} " +',
'                $"builder_total={total} since_submit={sinceSubmit} gap_ms={gapMs:F3} yields={yields}");',
'        }',
'    }',
'',
'    private static void NoteAgcDriverSubmitV763214(string kind)',
'    {',
'        if (!_v763214AgcPublishFairness)',
'        {',
'            return;',
'        }',
'',
'        LogAgcPublishFairnessProfileV763214();',
'        var beforeReset = System.Threading.Interlocked.Exchange(ref _v763214BuilderSinceSubmit, 0);',
'        var previousTicks = System.Threading.Interlocked.Exchange(',
'            ref _v763214LastSubmitTicks,',
'            System.Diagnostics.Stopwatch.GetTimestamp());',
'        var submit = System.Threading.Interlocked.Increment(ref _v763214DriverSubmits);',
'        var builder = System.Threading.Volatile.Read(ref _v763214BuilderOps);',
'        var gapMs = System.Diagnostics.Stopwatch.GetElapsedTime(previousTicks).TotalMilliseconds;',
'        var yields = System.Threading.Volatile.Read(ref _v763214FairnessYields);',
'',
'        if (submit <= 16 || IsPowerOfTwoV763214(submit) || beforeReset >= 512)',
'        {',
'            Console.Error.WriteLine(',
'                $"[V76.3.21.4][AGC_MEANINGFUL_PROGRESS] phase=submit kind={kind} " +',
'                $"submit_total={submit} builder_total={builder} builders_since_prev_submit={beforeReset} " +',
'                $"submit_gap_ms={gapMs:F3} yields={yields}");',
'        }',
'    }',
'    // V76.3.21.4_AGC_PUBLISH_FAIRNESS_END',
''
        ) -join $nl
        $t = $t.Insert($anchorPos,$helper + $nl)

        # Count only successfully materialized PM4 builder packets.
        $t = Insert-BeforeMethodNeedle $t 'public static int CbReleaseMem(CpuContext ctx)' ('        return ReturnPointer(ctx, commandAddress);' + $nl) ('        NoteAgcBuilderV763214("release_mem");' + $nl)
        $t = Insert-BeforeMethodNeedle $t 'public static int DcbWriteData(CpuContext ctx)' ('        return ReturnPointer(ctx, commandAddress);' + $nl) ('        NoteAgcBuilderV763214("write_data");' + $nl)

        # Count only submit calls that completed their existing publish/drain path.
        $t = Insert-BeforeMethodNeedle $t 'public static int DriverSubmitDcb(CpuContext ctx)' ('        ctx[CpuRegister.Rax] = 0;' + $nl) ('        NoteAgcDriverSubmitV763214("dcb");' + $nl)
        $t = Insert-BeforeMethodNeedle $t 'public static int DriverSubmitAcb(CpuContext ctx)' ('        ctx[CpuRegister.Rax] = 0;' + $nl) ('        NoteAgcDriverSubmitV763214("acb");' + $nl)
        $t = Insert-BeforeMethodNeedle $t 'public static int DriverSubmitMultiDcbs(CpuContext ctx)' ('        ctx[CpuRegister.Rax] = 0;' + $nl) ('        NoteAgcDriverSubmitV763214("multi_dcb");' + $nl)
    }

    Write-Utf8Preserve $AgcPath $t $c.HasBom
    $post = [IO.File]::ReadAllText($AgcPath)
    foreach ($m in @(
        'V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN',
        '[V76.3.21.4][AGC_PUBLISH_FAIRNESS]',
        '[V76.3.21.4][AGC_MEANINGFUL_PROGRESS]',
        'NoteAgcBuilderV763214("release_mem")',
        'NoteAgcBuilderV763214("write_data")',
        'NoteAgcDriverSubmitV763214("dcb")',
        'NoteAgcDriverSubmitV763214("acb")',
        'NoteAgcDriverSubmitV763214("multi_dcb")',
        'System.Threading.Thread.Yield()'
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
    Write-Host "[$Tag] agc_sha256=$(Get-HashLower $AgcPath)"
}
catch {
    $message = $_.Exception.Message
    try { Restore-Source; Write-Host "[$Tag] source restored automatically" -ForegroundColor Yellow } catch {}
    throw "[$Tag] APPLY/BUILD FAILED: $message"
}
