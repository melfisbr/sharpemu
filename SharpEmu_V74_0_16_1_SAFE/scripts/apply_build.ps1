param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74015 $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root
$agc=Get-AgcPathV74015 $root
$agcText=[System.IO.File]::ReadAllText($agc)
$alreadyApplied=$agcText.Contains("SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY")
$backupRoot=$null
$backupAgc=$null

if(-not $alreadyApplied){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine($root,".sharpemu-hotfix-backup","DccResidentAliasHistory_V74_0_16_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    $backupAgc=[System.IO.Path]::Combine($backupRoot,"AgcExports.cs")
    Copy-Item -LiteralPath $agc -Destination $backupAgc -Force

    try{
        $dccFieldAnchor="private static int _dccAliasTraceCount;"
        if(([regex]::Matches($agcText,[regex]::Escape($dccFieldAnchor))).Count -ne 1){
            throw "[V74.0.16.1] DCC field anchor mismatch."
        }
        $dccFields=@'
private static int _dccAliasTraceCount;

    // SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY
    // Seed history only after the ordinary resolver proves metadata/shape/format
    // and a live GPU guest image. History can then bridge a short provenance gap
    // between command buffers without ever CPU-decoding compressed DCC bytes.
    private readonly record struct V74016DccAliasHistoryKey(
        ulong MetadataAddress,
        uint Width,
        uint Height,
        uint Format,
        uint NumberType);

    private readonly record struct V74016DccAliasHistoryEntry(
        RenderTargetDescriptor Alias,
        ulong WriterSequence,
        long Tick);

    private static readonly ConcurrentDictionary<
        V74016DccAliasHistoryKey,
        V74016DccAliasHistoryEntry> _v74016DccAliasHistory = new();

    private static readonly long _v74016DccAliasHistoryTtlMs =
        long.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_DCC_ALIAS_HISTORY_MS"),
            out var v74016DccAliasHistoryMs) && v74016DccAliasHistoryMs > 0
            ? Math.Min(v74016DccAliasHistoryMs, 10000L)
            : 0L;

    private static int _v74016DccAliasHistorySeedTraceCount;
    private static int _v74016DccAliasHistoryHitTraceCount;
'@
        $agcText=$agcText.Replace($dccFieldAnchor,$dccFields)

        $snapshotField="private static int _v7405LargeTextureSnapshotReuseTraceCount;"
        if(([regex]::Matches($agcText,[regex]::Escape($snapshotField))).Count -ne 1){
            throw "[V74.0.16.1] V74.0.5 snapshot field anchor mismatch."
        }
        $snapshotFields=@'
private static int _v7405LargeTextureSnapshotReuseTraceCount;

    // V74.0.16.1: the V74.0.5 key includes guest write generation. Keep the
    // cross-title default at 2s; this runner opts into 10s for the measured A/B.
    private static readonly long _v74016LargeSnapshotReuseTtlMs =
        long.TryParse(
            Environment.GetEnvironmentVariable("SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS"),
            out var v74016SnapshotReuseMs) && v74016SnapshotReuseMs > 0
            ? Math.Min(v74016SnapshotReuseMs, 30000L)
            : 2000L;
'@
        $agcText=$agcText.Replace($snapshotField,$snapshotFields)

        $resolverSignature="private static bool TryResolveDccMetadataAlias("
        $resolverIndex=$agcText.IndexOf($resolverSignature,[System.StringComparison]::Ordinal)
        if($resolverIndex -lt 0 -or $agcText.IndexOf($resolverSignature,$resolverIndex+1,[System.StringComparison]::Ordinal) -ge 0){
            throw "[V74.0.16.1] DCC resolver signature mismatch."
        }

        $helpers=@'
private static V74016DccAliasHistoryKey GetV74016DccAliasHistoryKey(
        TextureDescriptor descriptor) =>
        new(
            descriptor.MetadataAddress,
            descriptor.Width,
            descriptor.Height,
            descriptor.Format,
            descriptor.NumberType);

    private static void RememberV74016DccAlias(
        TextureDescriptor descriptor,
        RenderTargetDescriptor alias,
        ulong writerSequence)
    {
        if (_v74016DccAliasHistoryTtlMs <= 0 || descriptor.MetadataAddress == 0)
        {
            return;
        }

        var now = Environment.TickCount64;
        var key = GetV74016DccAliasHistoryKey(descriptor);
        if (_v74016DccAliasHistory.Count >= 64)
        {
            foreach (var entry in _v74016DccAliasHistory)
            {
                var age = unchecked(now - entry.Value.Tick);
                if (age < 0 || age > _v74016DccAliasHistoryTtlMs)
                {
                    _v74016DccAliasHistory.TryRemove(entry.Key, out _);
                }
            }
        }

        if (_v74016DccAliasHistory.Count < 64 || _v74016DccAliasHistory.ContainsKey(key))
        {
            _v74016DccAliasHistory[key] =
                new V74016DccAliasHistoryEntry(alias, writerSequence, now);
        }

        var count = Interlocked.Increment(ref _v74016DccAliasHistorySeedTraceCount);
        if (count <= 64)
        {
            Console.Error.WriteLine(
                $"[V74.0.16.1][DCC_HISTORY] seed count={count} " +
                $"sample=0x{descriptor.Address:X16} alias=0x{alias.Address:X16} " +
                $"meta=0x{descriptor.MetadataAddress:X16} size={descriptor.Width}x{descriptor.Height} " +
                $"fmt={descriptor.Format}/{descriptor.NumberType} writer_seq={writerSequence}");
        }
    }

    private static bool TryUseV74016DccAlias(
        TextureDescriptor descriptor,
        out RenderTargetDescriptor alias,
        out ulong writerSequence)
    {
        alias = default;
        writerSequence = 0;
        var key = GetV74016DccAliasHistoryKey(descriptor);
        if (_v74016DccAliasHistoryTtlMs <= 0 ||
            descriptor.MetadataAddress == 0 ||
            !_v74016DccAliasHistory.TryGetValue(key, out var entry))
        {
            return false;
        }

        var now = Environment.TickCount64;
        var age = unchecked(now - entry.Tick);
        if (age < 0 ||
            age > _v74016DccAliasHistoryTtlMs ||
            !GuestGpu.Current.IsGpuGuestImageAvailable(
                entry.Alias.Address,
                entry.Alias.Format,
                entry.Alias.NumberType))
        {
            _v74016DccAliasHistory.TryRemove(key, out _);
            return false;
        }

        alias = entry.Alias;
        writerSequence = entry.WriterSequence;
        var count = Interlocked.Increment(ref _v74016DccAliasHistoryHitTraceCount);
        if (count <= 128 || count % 256 == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.16.1][DCC_HISTORY] hit count={count} " +
                $"sample=0x{descriptor.Address:X16} alias=0x{alias.Address:X16} " +
                $"meta=0x{descriptor.MetadataAddress:X16} age_ms={age} " +
                $"size={descriptor.Width}x{descriptor.Height} " +
                $"fmt={descriptor.Format}/{descriptor.NumberType}");
        }
        return true;
    }

'@
        $agcText=$agcText.Insert($resolverIndex,$helpers)

        $resolverIndex=$agcText.IndexOf($resolverSignature,[System.StringComparison]::Ordinal)
        $openBrace=$agcText.IndexOf('{',$resolverIndex)
        if($openBrace -lt 0){ throw "[V74.0.16.1] DCC resolver open brace missing." }
        $depth=0
        $resolverEnd=-1
        for($index=$openBrace;$index -lt $agcText.Length;$index++){
            $character=$agcText[$index]
            if($character -eq '{'){$depth++}
            elseif($character -eq '}'){
                $depth--
                if($depth -eq 0){$resolverEnd=$index+1;break}
            }
        }
        if($resolverEnd -lt 0){ throw "[V74.0.16.1] DCC resolver brace scan failed." }
        $resolver=$agcText.Substring($resolverIndex,$resolverEnd-$resolverIndex)

        $startPattern='(?ms)(?<indent>^[ \t]*)alias\s*=\s*default\s*;\s*writerSequence\s*=\s*0\s*;\s*if\s*\(\s*drawState\s+is\s+null\s*\)\s*\{\s*reason\s*=\s*"no-draw-state"\s*;\s*return\s+false\s*;\s*\}\s*if\s*\(\s*!descriptor\.HasExtendedDescriptor\s*\|\|\s*descriptor\.MetadataAddress\s*==\s*0\s*\)\s*\{\s*reason\s*=\s*"no-metadata"\s*;\s*return\s+false\s*;\s*\}'
        $startMatches=@([regex]::Matches($resolver,$startPattern))
        if($startMatches.Count -ne 1){
            throw "[V74.0.16.1] DCC resolver start structural count=$($startMatches.Count); expected 1."
        }
        $startMatch=$startMatches[0]
        $startIndent=$startMatch.Groups['indent'].Value
        $newStart=@(
            $startIndent+'alias = default;',
            $startIndent+'writerSequence = 0;',
            $startIndent+'if (!descriptor.HasExtendedDescriptor || descriptor.MetadataAddress == 0)',
            $startIndent+'{',
            $startIndent+'    reason = "no-metadata";',
            $startIndent+'    return false;',
            $startIndent+'}',
            $startIndent+'if (drawState is null)',
            $startIndent+'{',
            $startIndent+'    if (TryUseV74016DccAlias(descriptor, out alias, out writerSequence))',
            $startIndent+'    {',
            $startIndent+'        reason = "history-no-draw-state";',
            $startIndent+'        return true;',
            $startIndent+'    }',
            $startIndent+'    reason = "no-draw-state";',
            $startIndent+'    return false;',
            $startIndent+'}'
        ) -join "`r`n"
        $resolver=$resolver.Substring(0,$startMatch.Index)+$newStart+$resolver.Substring($startMatch.Index+$startMatch.Length)

        # V74.0.16.1: do not bind to one literal C# spelling of the final
        # resolver reason/return. The accumulated checkout can wrap/extend the
        # diagnostic string while preserving the same semantics. Locate the
        # unique result reason by its three runtime fields and insert history
        # handling before it, leaving the original reason and return untouched.
        $resultAnchor=Get-V740161DccResultReasonAnchor -ResolverText $resolver
        $endIndent=$resultAnchor.Indent
        $historyResultBlock=@(
            $endIndent+'if (found)',
            $endIndent+'{',
            $endIndent+'    RememberV74016DccAlias(descriptor, alias, writerSequence);',
            $endIndent+'}',
            $endIndent+'else if (TryUseV74016DccAlias(descriptor, out alias, out writerSequence))',
            $endIndent+'{',
            $endIndent+'    reason = "history_hit=1";',
            $endIndent+'    return true;',
            $endIndent+'}'
        ) -join "`r`n"
        $historyResultBlock += "`r`n"
        $resolver=$resolver.Substring(0,$resultAnchor.Start)+
            $historyResultBlock+
            $resolver.Substring($resultAnchor.Start)
        $agcText=$agcText.Substring(0,$resolverIndex)+$resolver+$agcText.Substring($resolverEnd)

        $ttlHitPattern='unchecked\s*\(\s*v7405Now\s*-\s*v7405Cached\.Tick\s*\)\s*<=\s*2000\s*\)'
        $ttlEvictPattern='unchecked\s*\(\s*v7405Now\s*-\s*entry\.Value\.Tick\s*\)\s*>\s*2000\s*\)'
        $ttlHitMatches=@([regex]::Matches($agcText,$ttlHitPattern))
        $ttlEvictMatches=@([regex]::Matches($agcText,$ttlEvictPattern))
        if($ttlHitMatches.Count -ne 1 -or $ttlEvictMatches.Count -ne 1){
            throw "[V74.0.16.1] V74.0.5 TTL structural anchors are not unique."
        }
        $ttlHitMatch=$ttlHitMatches[0]
        $agcText=$agcText.Substring(0,$ttlHitMatch.Index)+
            'unchecked(v7405Now - v7405Cached.Tick) <= _v74016LargeSnapshotReuseTtlMs)'+
            $agcText.Substring($ttlHitMatch.Index+$ttlHitMatch.Length)
        $ttlEvictMatches=@([regex]::Matches($agcText,$ttlEvictPattern))
        if($ttlEvictMatches.Count -ne 1){ throw "[V74.0.16.1] V74.0.5 eviction TTL anchor changed during patch." }
        $ttlEvictMatch=$ttlEvictMatches[0]
        $agcText=$agcText.Substring(0,$ttlEvictMatch.Index)+
            'unchecked(v7405Now - entry.Value.Tick) > _v74016LargeSnapshotReuseTtlMs)'+
            $agcText.Substring($ttlEvictMatch.Index+$ttlEvictMatch.Length)

        foreach($guard in @(
            "SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY",
            "TryUseV74016DccAlias",
            "RememberV74016DccAlias",
            "history_hit=1",
            "_v74016LargeSnapshotReuseTtlMs"
        )){
            if(-not $agcText.Contains($guard)){
                throw "[V74.0.16.1] Post-patch structural guard missing: $guard"
            }
        }

        [System.IO.File]::WriteAllText($agc,$agcText,[System.Text.UTF8Encoding]::new($false))
        Write-Host "[V74.0.16.1] Installed verified GPU-resident DCC alias history (semantic result anchor)."
        Write-Host "[V74.0.16.1] DCC history default remains disabled; test runner enables 2000ms."
        Write-Host "[V74.0.16.1] Non-DCC snapshot TTL default remains 2000ms; test runner uses 10000ms."
        Write-Host "[V74.0.16.1] V74.0.15 exact large-array single-flight preserved."
        Write-Host "[V74.0.16.1] Backup: $backupRoot"
    }
    catch{
        if($null -ne $backupAgc -and [System.IO.File]::Exists($backupAgc)){
            Copy-Item -LiteralPath $backupAgc -Destination $agc -Force
        }
        Write-Host "[V74.0.16.1] Apply failed; AGC source restored."
        throw
    }
}
else{
    Write-Host "[V74.0.16.1] Source correction already installed; building only."
}

try{
    Write-Host "[V74.0.16.1] Building Release win-x64..."
    Invoke-DotNetCheckedV74015 $root @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74015 -Root $root
}
catch{
    if($null -ne $backupAgc -and [System.IO.File]::Exists($backupAgc)){
        Copy-Item -LiteralPath $backupAgc -Destination $agc -Force
        Write-Host "[V74.0.16.1] Build failed; AGC source restored."
    }
    throw
}

$finalText=[System.IO.File]::ReadAllText($agc)
foreach($guard in @(
    "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
    "SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY",
    "TryUseV74016DccAlias",
    "RememberV74016DccAlias",
    "_v74016LargeSnapshotReuseTtlMs",
    "unchecked(v7405Now - v7405Cached.Tick) <= _v74016LargeSnapshotReuseTtlMs)",
    "unchecked(v7405Now - entry.Value.Tick) > _v74016LargeSnapshotReuseTtlMs)"
)){
    if(-not $finalText.Contains($guard)){ throw "[V74.0.16.1] FINAL guard missing: $guard" }
}
Write-Host "[V74.0.16.1] SUCCESS - source correction applied and Release build passed."
Write-Host "[V74.0.16.1] Next: RUN_4_DEMONS_DCC_HISTORY_FASTBOOT.cmd"
