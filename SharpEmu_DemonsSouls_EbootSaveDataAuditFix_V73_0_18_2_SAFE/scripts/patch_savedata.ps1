param(
    [Parameter(Mandatory=$true)][string]$SourcePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if(-not [IO.File]::Exists($SourcePath)){
    throw "SaveData source ausente: $SourcePath"
}

$text=[IO.File]::ReadAllText($SourcePath)
$changed=$false

# ---------------------------------------------------------------------------
# 1) PS5 SaveData block domain used by PPSA01341: 64 KiB.
# ---------------------------------------------------------------------------
if(-not $text.Contains('SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18')){
    $blockPattern='private\s+const\s+uint\s+DefaultBlockSize\s*=\s*\d+\s*;'
    $rx=[Text.RegularExpressions.Regex]::new($blockPattern)
    $m=$rx.Matches($text)
    if($m.Count -ne 1){
        throw "DefaultBlockSize: esperado 1 match, encontrado $($m.Count)."
    }

    $replacement=@'
    // SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18
    // PPSA01341 rounds save bytes with (size + 0xFFFF) >> 16.
    private const uint DefaultBlockSize = 65536;
'@.TrimEnd()

    $text=$rx.Replace($text,$replacement,1)
    $changed=$true

    # Keep the existing logical block quota, but update any old 32 KiB-only
    # comment so it does not document the wrong unit.
    $text=$text.Replace(
        'private const ulong DefaultTotalBlocks = 0x8000; // 1 GiB of 32 KiB blocks',
        'private const ulong DefaultTotalBlocks = 0x8000; // logical PS5 save-data block quota'
    )
}

# Normalize the search-info used-block calculation if the accumulated source
# still has a literal 32 KiB formula.
if($text -match '\(size\s*\+\s*32767\)\s*/\s*32768'){
    $text=[Text.RegularExpressions.Regex]::Replace(
        $text,
        '\(size\s*\+\s*32767\)\s*/\s*32768',
        '(size + (long)DefaultBlockSize - 1L) / DefaultBlockSize'
    )
    $changed=$true
}

# ---------------------------------------------------------------------------
# 2) sceSaveDataBackup exact NID imported by PPSA01341.
# ---------------------------------------------------------------------------
if(-not $text.Contains('Nid = "z1JA8-iJt3k"')){
    $backup=@'

    // SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BACKUP_V73_0_18
    // PPSA01341 callsite passes RDI=&backupParam:
    // +0x00 int32 userId, +0x08 titleId pointer, +0x10 dirName pointer.
    [SysAbiExport(
        Nid = "z1JA8-iJt3k",
        ExportName = "sceSaveDataBackup",
        Target = Generation.Gen5,
        LibraryName = "libSceSaveData")]
    public static int SaveDataBackup(CpuContext ctx)
    {
        var backupAddress = ctx[CpuRegister.Rdi];
        if (backupAddress == 0 ||
            !TryReadInt32(ctx, backupAddress + 0x00, out var userId) ||
            !ctx.TryReadUInt64(backupAddress + 0x08, out var titleIdAddress) ||
            !ctx.TryReadUInt64(backupAddress + 0x10, out var dirNameAddress))
        {
            return SetReturn(
                ctx,
                (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        if (userId < 0 || dirNameAddress == 0 ||
            !TryReadFixedAscii(
                ctx,
                dirNameAddress,
                SaveDataDirNameSize,
                out var dirName) ||
            string.IsNullOrWhiteSpace(dirName))
        {
            return SetReturn(ctx, OrbisSaveDataErrorParameter);
        }

        var titleId = ResolveConfiguredTitleId();
        if (titleIdAddress != 0)
        {
            if (!TryReadFixedAscii(
                    ctx,
                    titleIdAddress,
                    SaveDataTitleIdSize,
                    out var explicitTitleId))
            {
                return SetReturn(
                    ctx,
                    (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }

            if (!string.IsNullOrWhiteSpace(explicitTitleId))
            {
                titleId = SanitizePathSegment(explicitTitleId.Trim());
            }
        }

        try
        {
            var slotDir = SaveDataStorage.SlotDir(
                ResolveTitleSaveRoot(userId, titleId),
                dirName);

            if (!Directory.Exists(slotDir))
            {
                TraceSaveData(
                    $"backup user={userId} title={titleId} " +
                    $"dir='{dirName}' result=not_found path='{slotDir}'");
                return SetReturn(ctx, OrbisSaveDataErrorNotFound);
            }

            // SharpEmu writes mounted save files directly to persistent host
            // storage. Backup is therefore a synchronous persistence barrier;
            // queue the platform completion event only after the slot exists.
            EnqueueEvent(EventTypeBackupEnd, userId, dirName);
            TraceSaveData(
                $"backup user={userId} title={titleId} " +
                $"dir='{dirName}' synchronous=1 path='{slotDir}'");
            return SetReturn(ctx, 0);
        }
        catch (Exception exception)
            when (exception is IOException or UnauthorizedAccessException)
        {
            TraceSaveData(
                $"backup user={userId} title={titleId} " +
                $"dir='{dirName}' error='{exception.Message}'");
            return SetReturn(ctx, OrbisSaveDataErrorInternal);
        }
    }

'@

    $anchor='    // ---- params (metadata shown in the save UI) ----'
    $idx=$text.IndexOf($anchor,[StringComparison]::Ordinal)
    if($idx -lt 0){
        throw 'sceSaveDataBackup: anchor de insercao nao encontrado.'
    }
    $text=$text.Insert($idx,$backup)
    $changed=$true
}

# ---------------------------------------------------------------------------
# 3) sceSaveDataPrepare ABI from PPSA01341.
# ---------------------------------------------------------------------------
if(-not $text.Contains('SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18')){
    $prepareMethod=@'
public static int SaveDataPrepare(CpuContext ctx)
    {
        var mountPointAddress = ctx[CpuRegister.Rdi];
        var prepareAddress = ctx[CpuRegister.Rsi];

        // SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18
        // PPSA01341 passes RSI=&prepareParam. The first dword contains the
        // transaction resource. RDX is caller-saved at the audited callsite.
        int resource;
        if (prepareAddress != 0)
        {
            if (!TryReadUInt32(
                    ctx,
                    prepareAddress + 0x00,
                    out var resourceValue))
            {
                return ctx.SetReturn(
                    (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
            }

            resource = unchecked((int)resourceValue);
        }
        else
        {
            // Compatibility fallback for older SharpEmu synthetic callers.
            resource = unchecked((int)ctx[CpuRegister.Rdx]);
        }

        if (mountPointAddress == 0)
        {
            return ctx.SetReturn(OrbisSaveDataErrorParameter);
        }

        if (!TryReadFixedAscii(
                ctx,
                mountPointAddress,
                16,
                out var mountPoint))
        {
            return ctx.SetReturn(
                (int)OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT);
        }

        if (string.IsNullOrWhiteSpace(mountPoint))
        {
            return ctx.SetReturn(OrbisSaveDataErrorParameter);
        }

        lock (_stateGate)
        {
            if (resource != 0)
            {
                _preparedTransactionResources.Add(resource);
            }
        }

        TraceSaveData(
            $"prepare mount_point={mountPoint} " +
            $"param=0x{prepareAddress:X16} resource={resource} " +
            $"abi={(prepareAddress != 0 ? "param-rsi" : "legacy-rdx")}");
        return ctx.SetReturn(0);
    }
'@

    # Replace only the method body between the known export and the next export.
    $pattern='public\s+static\s+int\s+SaveDataPrepare\s*\(\s*CpuContext\s+ctx\s*\)\s*\{.*?\n\s{4}\}\s*\n\s*\n\s*\[SysAbiExport\('
    $rx=[Text.RegularExpressions.Regex]::new(
        $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches=$rx.Matches($text)
    if($matches.Count -ne 1){
        throw "sceSaveDataPrepare: esperado 1 metodo, encontrado $($matches.Count)."
    }

    $replacement=$prepareMethod + "`r`n`r`n    [SysAbiExport("
    $text=$rx.Replace($text,[Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },1)
    $changed=$true
}

# ---------------------------------------------------------------------------
# Final structural validation before writing.
# ---------------------------------------------------------------------------
$required=@(
    'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18',
    'private const uint DefaultBlockSize = 65536;',
    'Nid = "z1JA8-iJt3k"',
    'ExportName = "sceSaveDataBackup"',
    'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18',
    'var prepareAddress = ctx[CpuRegister.Rsi];'
)
foreach($marker in $required){
    if(-not $text.Contains($marker)){
        throw "Post-patch marker ausente: $marker"
    }
}

# Ensure no duplicate backup export.
$backupCount=[Text.RegularExpressions.Regex]::Matches(
    $text,
    'Nid\s*=\s*"z1JA8-iJt3k"'
).Count
if($backupCount -ne 1){
    throw "sceSaveDataBackup NID duplicado/ausente: count=$backupCount"
}

# Ensure old literal block size is gone.
if($text.Contains('private const uint DefaultBlockSize = 32768;')){
    throw 'DefaultBlockSize 32768 ainda presente apos patch.'
}

if($changed){
    [IO.File]::WriteAllText(
        $SourcePath,
        $text,
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host '[V73.0.18.2] STRUCTURAL PATCH APPLIED.' -ForegroundColor Green
}
else{
    Write-Host '[V73.0.18.2] STRUCTURAL PATCH ALREADY PRESENT.' -ForegroundColor Yellow
}
