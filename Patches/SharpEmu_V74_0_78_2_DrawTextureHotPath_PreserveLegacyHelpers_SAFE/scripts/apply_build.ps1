param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$state=Assert-StructuralContracts
$presenter=$state.Presenter
$agc=$state.Agc

$presenterChanged=$false
$agcChanged=$false
$presenterNl=if($presenter.Contains("`r`n")){"`r`n"}else{"`n"}

# Capture accumulated helper contracts before touching the presenter. V74.0.78.1
# accidentally replaced the entire region between IsTextureContentCached and
# MarkTextureContentCached; that deleted these helpers in accumulated checkouts.
$legacyNormalizeDefsBefore=([regex]::Matches($presenter,'(?m)^[ \t]*(?:private|internal)\s+static\s+[^\r\n]*\bNormalizeSamplerIdentityV74075\s*\(')).Count
$legacyIgnoringDefsBefore=([regex]::Matches($presenter,'(?m)^[ \t]*(?:private|internal)\s+static\s+bool\s+IsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count
$legacyNormalizeRefsBefore=([regex]::Matches($presenter,'\bNormalizeSamplerIdentityV74075\s*\(')).Count
$legacyIgnoringRefsAgcBefore=([regex]::Matches($agc,'\bIsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count

# ---------------------------------------------------------------------------
# Presenter hot path: wrap the EXISTING cache method instead of replacing its
# body/neighboring helpers. The old implementation stays byte-for-byte intact
# (apart from its signature name), so V74.0.75/V74.0.74 helpers survive.
# ---------------------------------------------------------------------------
if(-not $presenter.Contains('SHARPEMU_V74_0_78_2_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER')){
    $pattern='(?m)^(?<indent>[ \t]*)internal\s+static\s+bool\s+IsTextureContentCached\s*\(\s*in\s+TextureContentIdentity\s+identity\s*\)'
    $matches=[regex]::Matches($presenter,$pattern)
    if($matches.Count -ne 1){throw "$script:Tag presenter IsTextureContentCached anchor count=$($matches.Count), expected=1."}
    $m=$matches[0]
    $i=$m.Groups['indent'].Value
    $nl=$presenterNl

    $block=@(
        "$i// SHARPEMU_V74_0_78_2_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER",
        "$i// O(1) content lookup that ignores sampler only. The accumulated cache",
        "$i// method below remains authoritative for stale-content/coherency checks.",
        "${i}private readonly record struct V740782TextureContentKey(",
        "$i    ulong Address,",
        "$i    uint Width,",
        "$i    uint Height,",
        "$i    uint Format,",
        "$i    uint NumberType,",
        "$i    uint DstSelect,",
        "$i    uint TileMode,",
        "$i    uint Pitch,",
        "$i    bool Arrayed,",
        "$i    uint ArrayLayers,",
        "$i    uint Type,",
        "$i    uint Depth,",
        "$i    ulong MetadataAddress,",
        "$i    uint DescriptorFlags,",
        "$i    uint BcSwizzle,",
        "$i    bool HasExtendedDescriptor);",
        '',
        "${i}private static readonly System.Collections.Concurrent.ConcurrentDictionary<",
        "$i    V740782TextureContentKey, TextureContentIdentity>",
        "$i    _v740782TextureByContent = new();",
        "${i}private static long _v740782PreSnapshotAliasHitCount;",
        '',
        "${i}private static V740782TextureContentKey GetTextureContentKeyV740782(",
        "$i    in TextureContentIdentity identity) =>",
        "$i    new(",
        "$i        identity.Address,",
        "$i        identity.Width,",
        "$i        identity.Height,",
        "$i        identity.Format,",
        "$i        identity.NumberType,",
        "$i        identity.DstSelect,",
        "$i        identity.TileMode,",
        "$i        identity.Pitch,",
        "$i        identity.Arrayed,",
        "$i        identity.ArrayLayers,",
        "$i        identity.Type,",
        "$i        identity.Depth,",
        "$i        identity.MetadataAddress,",
        "$i        identity.DescriptorFlags,",
        "$i        identity.BcSwizzle,",
        "$i        identity.HasExtendedDescriptor);",
        '',
        "${i}private static void RemoveTextureContentIndexV740782(",
        "$i    in TextureContentIdentity identity)",
        "$i{",
        "$i    var key = GetTextureContentKeyV740782(identity);",
        "$i    if (_v740782TextureByContent.TryGetValue(key, out var mapped) &&",
        "$i        mapped.Equals(identity))",
        "$i    {",
        "$i        _v740782TextureByContent.TryRemove(key, out _);",
        "$i    }",
        "$i}",
        '',
        "${i}private static void TracePreSnapshotAliasV740782(",
        "$i    in TextureContentIdentity requested)",
        "$i{",
        "$i    var hit = Interlocked.Increment(ref _v740782PreSnapshotAliasHitCount);",
        "$i    if (hit <= 256 || (hit & (hit - 1)) == 0)",
        "$i    {",
        "$i        Console.Error.WriteLine(",
        ($i + '            $"[V74.0.78.2][PRE_SNAPSHOT_SAMPLER_ALIAS] " +'),
        ($i + '            $"count={hit} addr=0x{requested.Address:X16} " +'),
        ($i + '            $"size={requested.Width}x{requested.Height} " +'),
        ($i + '            $"fmt={requested.Format}/{requested.NumberType} " +'),
        ($i + '            $"tile={requested.TileMode} source_copy=skipped");'),
        "$i    }",
        "$i}",
        '',
        "${i}internal static bool IsTextureContentCached(in TextureContentIdentity identity)",
        "$i{",
        "$i    // Exact sampler-inclusive identity: keep the accumulated implementation",
        "$i    // as the single authority for sparse probes and stale invalidation.",
        "$i    if (_cachedTextureIdentities.ContainsKey(identity))",
        "$i    {",
        "$i        return IsTextureContentCachedBaselineV740782(identity);",
        "$i    }",
        '',
        "$i    var key = GetTextureContentKeyV740782(identity);",
        "$i    if (_v740782TextureByContent.TryGetValue(key, out var canonical))",
        "$i    {",
        "$i        if (!canonical.Sampler.Equals(identity.Sampler) &&",
        "$i            IsTextureContentCachedBaselineV740782(canonical))",
        "$i        {",
        "$i            TracePreSnapshotAliasV740782(identity);",
        "$i            return true;",
        "$i        }",
        '',
        "$i        if (!_cachedTextureIdentities.ContainsKey(canonical))",
        "$i        {",
        "$i            _v740782TextureByContent.TryRemove(key, out _);",
        "$i        }",
        "$i    }",
        '',
        "$i    // Preserve any accumulated fallback/legacy alias behavior.",
        "$i    return IsTextureContentCachedBaselineV740782(identity);",
        "$i}",
        ''
    ) -join $nl

    $renamed="${i}private static bool IsTextureContentCachedBaselineV740782(in TextureContentIdentity identity)"
    $presenter=$presenter.Substring(0,$m.Index)+$block+$nl+$renamed+$presenter.Substring($m.Index+$m.Length)
    $presenterChanged=$true
}

# Maintain the content-only index in the existing exact-cache lifecycle without
# replacing any accumulated helper methods around it.
if(-not $presenter.Contains('_v740782TextureByContent[GetTextureContentKeyV740782(identity)] = identity;')){
    $markStart=$presenter.IndexOf('    private static void MarkTextureContentCached(',[System.StringComparison]::Ordinal)
    $markEnd=$presenter.IndexOf('    private static void UnmarkTextureContentCached(', $markStart,[System.StringComparison]::Ordinal)
    if($markStart -lt 0 -or $markEnd -lt 0){throw "$script:Tag MarkTextureContentCached bounds missing."}
    $segment=$presenter.Substring($markStart,$markEnd-$markStart)
    $needle='_cachedTextureIdentities.TryAdd(identity, 0);'
    $local=$segment.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($local -lt 0){throw "$script:Tag exact-cache add anchor missing inside MarkTextureContentCached."}
    $global=$markStart+$local
    $replacement=$needle+$presenterNl+"        _v740782TextureByContent[GetTextureContentKeyV740782(identity)] = identity;"
    $presenter=$presenter.Remove($global,$needle.Length).Insert($global,$replacement)
    $presenterChanged=$true
}

if(-not $presenter.Contains('RemoveTextureContentIndexV740782(identity);')){
    $unmarkStart=$presenter.IndexOf('    private static void UnmarkTextureContentCached(',[System.StringComparison]::Ordinal)
    $unmarkEnd=$presenter.IndexOf('    private static void ClearCachedTextureIdentities(', $unmarkStart,[System.StringComparison]::Ordinal)
    if($unmarkStart -lt 0 -or $unmarkEnd -lt 0){throw "$script:Tag UnmarkTextureContentCached bounds missing."}
    $segment=$presenter.Substring($unmarkStart,$unmarkEnd-$unmarkStart)
    $needle='_cachedTextureIdentities.TryRemove(identity, out _);'
    $local=$segment.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($local -lt 0){throw "$script:Tag exact-cache remove anchor missing inside UnmarkTextureContentCached."}
    $global=$unmarkStart+$local
    $replacement=$needle+$presenterNl+"        RemoveTextureContentIndexV740782(identity);"
    $presenter=$presenter.Remove($global,$needle.Length).Insert($global,$replacement)
    $presenterChanged=$true
}

if(-not $presenter.Contains('_v740782TextureByContent.Clear();')){
    $clearStart=$presenter.IndexOf('    private static void ClearCachedTextureIdentities(',[System.StringComparison]::Ordinal)
    if($clearStart -lt 0){throw "$script:Tag ClearCachedTextureIdentities missing."}
    $needle='_cachedTextureIdentities.Clear();'
    $pos=$presenter.IndexOf($needle,$clearStart,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag exact-cache clear anchor missing."}
    $replacement=$needle+$presenterNl+"        _v740782TextureByContent.Clear();"
    $presenter=$presenter.Remove($pos,$needle.Length).Insert($pos,$replacement)
    $presenterChanged=$true
}

# ---------------------------------------------------------------------------
# AGC: eliminate CLR zero-fill only for physicalSourceByteCount buffers that
# are immediately overwritten by TryReadTextureGuestMemory.
# ---------------------------------------------------------------------------
$agcBefore=$agc
$agc=[regex]::Replace(
    $agc,
    'new\s+byte\s*\[\s*\(int\)physicalSourceByteCount\s*\]',
    'GC.AllocateUninitializedArray<byte>(checked((int)physicalSourceByteCount))')
if($agc -ne $agcBefore){$agcChanged=$true}

# Publish the existing drain context once. Preserve an accumulated V74.0.75
# implementation if it already does this.
if(-not $agc.Contains('Volatile.Write(ref gpuState.PendingDrainContext, monitorContext);')){
    $needle=@'
        var monitorContext = new CpuContext(
            submitContext.Memory,
            submitContext.TargetGeneration);
'@
    $pos=$agc.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag EnsureGpuWaitMonitor context anchor missing."}
    $insert=$needle+@'
        // SHARPEMU_V74_0_78_2_WAIT_MONITOR_DRAIN_CONTEXT
        Volatile.Write(ref gpuState.PendingDrainContext, monitorContext);
'@
    $agc=$agc.Remove($pos,$needle.Length).Insert($pos,$insert)
    $agcChanged=$true
}

# Producer/writeback signal: append to the existing SignalGpuWaitMonitor body
# instead of replacing it, so accumulated synchronization logic is preserved.
$signalStart=$agc.IndexOf('    private static void SignalGpuWaitMonitor(object memory)',[System.StringComparison]::Ordinal)
$signalEnd=$agc.IndexOf('    private static void ApplySubmittedDmaData(', $signalStart,[System.StringComparison]::Ordinal)
if($signalStart -lt 0 -or $signalEnd -lt 0){throw "$script:Tag SignalGpuWaitMonitor bounds missing."}
$signalSegment=$agc.Substring($signalStart,$signalEnd-$signalStart)
$alreadyHasWake=$signalSegment.Contains('GpuWaitRegistry.CountForMemory(memory)') -and $signalSegment.Contains('DrainPending')
if(-not $alreadyHasWake -and -not $signalSegment.Contains('SHARPEMU_V74_0_78_2_PRODUCER_WAKE_DRAIN')){
    $close=$signalSegment.LastIndexOf("    }",[System.StringComparison]::Ordinal)
    if($close -lt 0){throw "$script:Tag SignalGpuWaitMonitor closing brace missing."}
    $wake=@'

        // SHARPEMU_V74_0_78_2_PRODUCER_WAKE_DRAIN
        // Real producer/writeback evidence only requests the existing authoritative
        // drain path. No guest value, fence or completion is synthesized here.
        if (GpuWaitRegistry.CountForMemory(memory) != 0 &&
            Volatile.Read(ref gpuState.PendingDrainContext) is not null)
        {
            Interlocked.Exchange(ref gpuState.DrainPending, 1);
            if (_dedicatedWaitDrainV74071 &&
                EnsureDedicatedResumableDcbDrainWorkerV74071(gpuState))
            {
                gpuState.DedicatedDrainSignal.Set();
            }
            else
            {
                QueueLegacyResumableDcbDrainWorkerV74071(gpuState);
            }
        }
'@
    $global=$signalStart+$close
    $agc=$agc.Insert($global,$wake)
    $agcChanged=$true
}

if(-not $presenterChanged -and -not $agcChanged){
    Write-Host "$script:Tag State=AlreadyApplied"
}else{
    $backup=New-Backup
    try{
        if($presenterChanged){Write-Utf8NoBom $script:PresenterPath $presenter}
        if($agcChanged){Write-Utf8NoBom $script:AgcPath $agc}

        $p2=Read-Utf8 $script:PresenterPath
        $a2=Read-Utf8 $script:AgcPath
        if(-not $p2.Contains('SHARPEMU_V74_0_78_2_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER')){throw "$script:Tag presenter wrapper marker missing after patch."}
        if(-not $p2.Contains('IsTextureContentCachedBaselineV740782')){throw "$script:Tag preserved baseline cache method missing after patch."}
        if(-not $p2.Contains('_v740782TextureByContent[GetTextureContentKeyV740782(identity)] = identity;')){throw "$script:Tag content index lifecycle add missing."}
        if(-not ($a2 -match 'AllocateUninitializedArray<byte>\s*\(\s*checked\(\(int\)physicalSourceByteCount\)\s*\)')){throw "$script:Tag uninitialized physical snapshot replacement missing."}

        $legacyNormalizeDefsAfter=([regex]::Matches($p2,'(?m)^[ \t]*(?:private|internal)\s+static\s+[^\r\n]*\bNormalizeSamplerIdentityV74075\s*\(')).Count
        $legacyIgnoringDefsAfter=([regex]::Matches($p2,'(?m)^[ \t]*(?:private|internal)\s+static\s+bool\s+IsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count
        $legacyNormalizeRefsAfter=([regex]::Matches($p2,'\bNormalizeSamplerIdentityV74075\s*\(')).Count
        $legacyIgnoringRefsAgcAfter=([regex]::Matches($a2,'\bIsTextureContentCachedIgnoringSamplerV74074\s*\(')).Count
        if($legacyNormalizeDefsAfter -ne $legacyNormalizeDefsBefore -or $legacyNormalizeRefsAfter -ne $legacyNormalizeRefsBefore){throw "$script:Tag accumulated NormalizeSamplerIdentityV74075 contract changed unexpectedly."}
        if($legacyIgnoringDefsAfter -ne $legacyIgnoringDefsBefore -or $legacyIgnoringRefsAgcAfter -ne $legacyIgnoringRefsAgcBefore){throw "$script:Tag accumulated IsTextureContentCachedIgnoringSamplerV74074 contract changed unexpectedly."}

        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY; legacy helpers preserved."
        Write-Host "$script:Tag LegacyNormalizeDefs=$legacyNormalizeDefsAfter LegacyNormalizeRefs=$legacyNormalizeRefsAfter"
        Write-Host "$script:Tag LegacyIgnoringSamplerDefs=$legacyIgnoringDefsAfter LegacyIgnoringSamplerAgcRefs=$legacyIgnoringRefsAgcAfter"
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
        Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
    }catch{
        Restore-Backup $backup
        throw
    }
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_78_2_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+".log")
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{
    & dotnet build $project -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
    $code=$LASTEXITCODE
}catch{
    $code=1
    $_ | Out-String | Add-Content -LiteralPath $buildLog
}
if($code -ne 0){
    if(Test-Path -LiteralPath $script:StateFile){
        $backup=(Read-Utf8 $script:StateFile).Trim()
        if($backup -and (Test-Path -LiteralPath $backup)){
            Restore-Backup $backup
            Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow
        }
    }
    throw "$script:Tag BUILD FAILED. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
