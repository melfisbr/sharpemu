param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $Patches ("V76_3_21_4_1_PRE_SOURCE_$stamp")
$backupZip = Join-Path $Patches ("V76_3_21_4_1_PRE_SOURCE_$stamp.zip")
$restoreLog = Join-Path $Patches ("V76_3_21_4_1_DEV_RESTORE_$stamp.log")
$buildLog = Join-Path $Patches ("V76_3_21_4_1_DEV_BUILD_$stamp.log")

$backupAgc = Join-Path $backupRoot $AgcRel
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupAgc) | Out-Null

$sourceHashBefore = Get-HashLower $AgcPath
Copy-Item -LiteralPath $AgcPath -Destination $backupAgc -Force
if (-not (Test-Path -LiteralPath $backupAgc -PathType Leaf)) {
    Fail "backup AGC nao criado: $backupAgc"
}
$backupHash = Get-HashLower $backupAgc
if ($backupHash -ne $sourceHashBefore) {
    Fail "backup SHA256 divergente source=$sourceHashBefore backup=$backupHash"
}

Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force
Write-Host "[$Tag] BACKUP PASSED source=$AgcPath sha256=$sourceHashBefore zip=$backupZip"

function Restore-Source {
    if (Test-Path -LiteralPath $backupAgc) {
        Copy-Item -LiteralPath $backupAgc -Destination $AgcPath -Force
    }
}

try {
    $c = Read-Utf8Preserve $AgcPath
    $t = $c.Text
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }

    $begin = '    // V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN'
    $end = '    // V76.3.21.4_AGC_PUBLISH_FAIRNESS_END'

    $removedBlock = 0
    $start = $t.IndexOf($begin,[StringComparison]::Ordinal)
    if ($start -ge 0) {
        $endPos = $t.IndexOf($end,$start,[StringComparison]::Ordinal)
        if ($endPos -lt 0) {
            Fail 'V21.4 fairness begin encontrado sem end marker'
        }

        $after = $endPos + $end.Length
        if ($after + 1 -lt $t.Length -and $t.Substring($after,2) -eq "`r`n") {
            $after += 2
        }
        elseif ($after -lt $t.Length -and ($t[$after] -eq "`n" -or $t[$after] -eq "`r")) {
            $after += 1
        }

        $t = $t.Remove($start,$after-$start)
        $removedBlock = 1
    }

    $hookLines = @(
        '        NoteAgcBuilderV763214("release_mem");',
        '        NoteAgcBuilderV763214("write_data");',
        '        NoteAgcDriverSubmitV763214("dcb");',
        '        NoteAgcDriverSubmitV763214("acb");',
        '        NoteAgcDriverSubmitV763214("multi_dcb");'
    )

    $removedHooks = 0
    foreach ($hook in $hookLines) {
        foreach ($suffix in @("`r`n","`n","")) {
            $needle = $hook + $suffix
            while ($t.Contains($needle)) {
                $t = $t.Replace($needle,'')
                $removedHooks++
                if ($suffix -eq '') { break }
            }
        }
    }

    foreach ($forbidden in @(
        'V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN',
        'V76.3.21.4_AGC_PUBLISH_FAIRNESS_END',
        'NoteAgcBuilderV763214',
        'NoteAgcDriverSubmitV763214',
        '_v763214BuilderOps',
        '_v763214BuilderSinceSubmit',
        '_v763214DriverSubmits',
        '_v763214FairnessYields'
    )) {
        if ($t.Contains($forbidden)) {
            Fail "residuo V21.4 permaneceu apos rollback: $forbidden"
        }
    }

    # The V21.4 package was the only revision that intentionally inserted
    # Thread.Yield() in AgcExports. Do not silently remove unrelated future uses:
    # only reject it if the V21.4 block/hooks were present in the pre-source.
    $preHadV214 = $c.Text.Contains('V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN') -or
                  $c.Text.Contains('NoteAgcBuilderV763214') -or
                  $c.Text.Contains('NoteAgcDriverSubmitV763214')
    if ($preHadV214 -and $t.Contains('System.Threading.Thread.Yield()')) {
        Fail 'Thread.Yield ainda presente no AgcExports apos remover V21.4'
    }

    Write-Utf8Preserve $AgcPath $t $c.HasBom

    $post = [IO.File]::ReadAllText($AgcPath)
    foreach ($required in @(
        'public static int DcbWriteData(CpuContext ctx)',
        'public static int CbReleaseMem(CpuContext ctx)',
        'public static int DriverSubmitDcb(CpuContext ctx)',
        'public static int DriverSubmitAcb(CpuContext ctx)',
        'private static void EnqueueSubmittedDcb('
    )) {
        if (-not $post.Contains($required)) {
            Fail "post-rollback AGC anchor perdido: $required"
        }
    }

    $dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
    if (-not $dotnet) { $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source }
    if (-not $dotnet) { Fail 'dotnet nao encontrado' }

    & $dotnet restore $Project -r win-x64 2>&1 | Tee-Object -FilePath $restoreLog
    if ($LASTEXITCODE -ne 0) { throw "restore exit=$LASTEXITCODE" }

    & $dotnet build $Project -t:Rebuild -c Debug -r win-x64 --no-restore `
        -p:Optimize=true -p:DebugSymbols=true -p:DebugType=portable -p:TieredPGO=true `
        2>&1 | Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "build exit=$LASTEXITCODE" }

    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug rid=win-x64"
    Write-Host "[$Tag] rollback_v214_block=$removedBlock removed_hook_lines=$removedHooks"
    Write-Host "[$Tag] backup=$backupZip"
    Write-Host "[$Tag] agc_sha256=$(Get-HashLower $AgcPath)"
}
catch {
    $message = $_.Exception.Message
    try {
        Restore-Source
        Write-Host "[$Tag] source restored automatically" -ForegroundColor Yellow
    }
    catch {}
    throw "[$Tag] APPLY/BUILD FAILED: $message"
}
