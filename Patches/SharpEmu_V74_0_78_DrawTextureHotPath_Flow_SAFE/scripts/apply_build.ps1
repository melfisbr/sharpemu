param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$state=Assert-StructuralContracts
$presenter=$state.Presenter
$agc=$state.Agc

$presenterChanged=$false
$agcChanged=$false

if(-not $presenter.Contains('SHARPEMU_V74_0_78_PRE_SNAPSHOT_SAMPLER_ALIAS_INDEX')){
$helper=@'
    // SHARPEMU_V74_0_78_PRE_SNAPSHOT_SAMPLER_ALIAS_INDEX
    // The backend cache key includes sampler state, but texel content does not.
    // Keep a second O(1) index over every content-defining field except Sampler
    // so AGC can skip guest-memory snapshot/detile BEFORE V74.0.73 creates the
    // lightweight sampler alias on the presenter thread.
    private readonly record struct V74078TextureContentKey(
        ulong Address,
        uint Width,
        uint Height,
        uint Format,
        uint NumberType,
        uint DstSelect,
        uint TileMode,
        uint Pitch,
        bool Arrayed,
        uint ArrayLayers,
        uint Type,
        uint Depth,
        ulong MetadataAddress,
        uint DescriptorFlags,
        uint BcSwizzle,
        bool HasExtendedDescriptor);

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<
        V74078TextureContentKey, TextureContentIdentity>
        _v74078TextureByContent = new();

    private static long _v74078PreSnapshotSamplerAliasHitCount;

    private static V74078TextureContentKey GetTextureContentKeyV74078(
        in TextureContentIdentity identity) =>
        new(
            identity.Address,
            identity.Width,
            identity.Height,
            identity.Format,
            identity.NumberType,
            identity.DstSelect,
            identity.TileMode,
            identity.Pitch,
            identity.Arrayed,
            identity.ArrayLayers,
            identity.Type,
            identity.Depth,
            identity.MetadataAddress,
            identity.DescriptorFlags,
            identity.BcSwizzle,
            identity.HasExtendedDescriptor);

    private static void RemoveTextureContentAliasIndexV74078(
        in TextureContentIdentity identity)
    {
        var contentKey = GetTextureContentKeyV74078(identity);
        if (_v74078TextureByContent.TryGetValue(contentKey, out var mapped) &&
            mapped.Equals(identity))
        {
            _v74078TextureByContent.TryRemove(contentKey, out _);
        }
    }

    private static bool TryResolveCachedTextureIdentityV74078(
        in TextureContentIdentity requested,
        out TextureContentIdentity canonical,
        out bool samplerAlias)
    {
        if (_cachedTextureIdentities.ContainsKey(requested))
        {
            canonical = requested;
            samplerAlias = false;
            return true;
        }

        var contentKey = GetTextureContentKeyV74078(requested);
        if (_v74078TextureByContent.TryGetValue(contentKey, out canonical) &&
            _cachedTextureIdentities.ContainsKey(canonical))
        {
            samplerAlias = !canonical.Sampler.Equals(requested.Sampler);
            return true;
        }

        _v74078TextureByContent.TryRemove(contentKey, out _);
        canonical = default;
        samplerAlias = false;
        return false;
    }

    private static void TracePreSnapshotSamplerAliasV74078(
        in TextureContentIdentity requested,
        in TextureContentIdentity canonical,
        bool samplerAlias)
    {
        if (!samplerAlias)
        {
            return;
        }

        var count = Interlocked.Increment(
            ref _v74078PreSnapshotSamplerAliasHitCount);
        if (count <= 256 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.78][PRE_SNAPSHOT_SAMPLER_ALIAS] " +
                $"count={count} addr=0x{requested.Address:X16} " +
                $"size={requested.Width}x{requested.Height} " +
                $"fmt={requested.Format}/{requested.NumberType} " +
                $"tile={requested.TileMode} source_copy=skipped");
        }
    }

'@
    $sig='    internal static bool IsTextureContentCached(in TextureContentIdentity identity)'
    $idx=$presenter.IndexOf($sig,[System.StringComparison]::Ordinal)
    if($idx -lt 0){throw "$script:Tag presenter cache signature not found for insertion."}
    $presenter=$presenter.Insert($idx,$helper)
    $presenterChanged=$true
}

# Replace only the cache-query method body. Helpers/legacy alias code elsewhere are preserved.
$startSig='    internal static bool IsTextureContentCached(in TextureContentIdentity identity)'
$endSig='    private static void MarkTextureContentCached('
$start=$presenter.IndexOf($startSig,[System.StringComparison]::Ordinal)
$end=$presenter.IndexOf($endSig,$start,[System.StringComparison]::Ordinal)
if($start -lt 0 -or $end -lt 0 -or $end -le $start){throw "$script:Tag unable to bound IsTextureContentCached."}
$oldMethod=$presenter.Substring($start,$end-$start)
if(-not $oldMethod.Contains('TryResolveCachedTextureIdentityV74078')){
$newMethod=@'
    internal static bool IsTextureContentCached(in TextureContentIdentity identity)
    {
        if (!TryResolveCachedTextureIdentityV74078(
                identity,
                out var canonical,
                out var samplerAlias))
        {
            return false;
        }

        if (!ShouldProbeUntrackedTextureCache() || canonical.Address == 0)
        {
            TracePreSnapshotSamplerAliasV74078(identity, canonical, samplerAlias);
            return true;
        }

        if (!_untrackedTextureCacheProbes.TryGetValue(canonical, out var previous))
        {
            _cachedTextureIdentities.TryRemove(canonical, out _);
            RemoveTextureContentAliasIndexV74078(canonical);
            _staleTextureIdentities.TryAdd(canonical, 0);
            TraceUntrackedTextureCacheStale(
                canonical,
                0,
                0,
                "missing-baseline");
            return false;
        }

        var memory = _guestMemory;
        if (memory is null || previous.ByteCount == 0)
        {
            TracePreSnapshotSamplerAliasV74078(identity, canonical, samplerAlias);
            return true;
        }

        var current = ComputeSparseGuestContentProbe(
            memory,
            canonical.Address,
            previous.ByteCount);
        if (current == previous.Hash)
        {
            TracePreSnapshotSamplerAliasV74078(identity, canonical, samplerAlias);
            return true;
        }

        _cachedTextureIdentities.TryRemove(canonical, out _);
        _untrackedTextureCacheProbes.TryRemove(canonical, out _);
        RemoveTextureContentAliasIndexV74078(canonical);
        _staleTextureIdentities.TryAdd(canonical, 0);
        TraceUntrackedTextureCacheStale(
            canonical,
            previous.Hash,
            current,
            "guest-bytes-changed");
        return false;
    }

'@
    $presenter=$presenter.Substring(0,$start)+$newMethod+$presenter.Substring($end)
    $presenterChanged=$true
}

# Keep the content-only index in lock-step with the exact identity mirror.
if(-not ($presenter -match '_v74078TextureByContent\[GetTextureContentKeyV74078\(identity\)\]\s*=\s*identity;')){
    $needle='        _cachedTextureIdentities.TryAdd(identity, 0);'
    $pos=$presenter.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag MarkTextureContentCached insertion anchor missing."}
    $insert=$needle+"`r`n        _v74078TextureByContent[GetTextureContentKeyV74078(identity)] = identity;"
    $presenter=$presenter.Remove($pos,$needle.Length).Insert($pos,$insert)
    $presenterChanged=$true
}
if(-not ($presenter -match 'RemoveTextureContentAliasIndexV74078\(identity\);')){
    $unmarkStart=$presenter.IndexOf('    private static void UnmarkTextureContentCached(',[System.StringComparison]::Ordinal)
    $unmarkEnd=$presenter.IndexOf('    private static void ClearCachedTextureIdentities(', $unmarkStart,[System.StringComparison]::Ordinal)
    if($unmarkStart -lt 0 -or $unmarkEnd -lt 0){throw "$script:Tag Unmark method bounds missing."}
    $segment=$presenter.Substring($unmarkStart,$unmarkEnd-$unmarkStart)
    $needle='        _cachedTextureIdentities.TryRemove(identity, out _);'
    $local=$segment.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($local -lt 0){throw "$script:Tag Unmark exact-cache anchor missing."}
    $global=$unmarkStart+$local
    $insert=$needle+"`r`n        RemoveTextureContentAliasIndexV74078(identity);"
    $presenter=$presenter.Remove($global,$needle.Length).Insert($global,$insert)
    $presenterChanged=$true
}
if(-not ($presenter -match '_v74078TextureByContent\.Clear\(\);')){
    $clearStart=$presenter.IndexOf('    private static void ClearCachedTextureIdentities(',[System.StringComparison]::Ordinal)
    if($clearStart -lt 0){throw "$script:Tag ClearCachedTextureIdentities missing."}
    $needle='        _cachedTextureIdentities.Clear();'
    $pos=$presenter.IndexOf($needle,$clearStart,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag Clear exact-cache anchor missing."}
    $insert=$needle+"`r`n        _v74078TextureByContent.Clear();"
    $presenter=$presenter.Remove($pos,$needle.Length).Insert($pos,$insert)
    $presenterChanged=$true
}

# Large texture buffer is overwritten by TryReadTextureGuestMemory; avoid zeroing 8–32 MiB first.
$agcBefore=$agc
$agc=[regex]::Replace(
    $agc,
    'source\s*=\s*new\s+byte\s*\[\s*\(int\)physicalSourceByteCount\s*\]\s*;',
    'source = GC.AllocateUninitializedArray<byte>(checked((int)physicalSourceByteCount));')
if($agc -ne $agcBefore){$agcChanged=$true}

# Publish a persistent drain context as soon as the monitor exists.
if(-not $agc.Contains('SHARPEMU_V74_0_78_WAIT_MONITOR_DRAIN_CONTEXT')){
    $needle=@'
        var monitorContext = new CpuContext(
            submitContext.Memory,
            submitContext.TargetGeneration);
'@
    $pos=$agc.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag EnsureGpuWaitMonitor context anchor missing."}
    $insert=$needle+@'
        // SHARPEMU_V74_0_78_WAIT_MONITOR_DRAIN_CONTEXT
        // Producer callbacks can now request the already-existing drain path
        // immediately instead of waiting for the monitor's next 1..16 ms poll.
        Volatile.Write(ref gpuState.PendingDrainContext, monitorContext);
'@
    $agc=$agc.Remove($pos,$needle.Length).Insert($pos,$insert)
    $agcChanged=$true
}

# Clear stale context when the last real waiter disappears.
if(-not $agc.Contains('SHARPEMU_V74_0_78_CLEAR_WAIT_MONITOR_DRAIN_CONTEXT')){
    $needle=@'
                if (remaining == 0)
                {
                    gpuState.WaitMonitorRunning = false;
                    return;
                }
'@
    $pos=$agc.IndexOf($needle,[System.StringComparison]::Ordinal)
    if($pos -lt 0){throw "$script:Tag MonitorGpuWaits remaining==0 anchor missing."}
    $replacement=@'
                if (remaining == 0)
                {
                    // SHARPEMU_V74_0_78_CLEAR_WAIT_MONITOR_DRAIN_CONTEXT
                    Volatile.Write(ref gpuState.PendingDrainContext, null);
                    gpuState.WaitMonitorRunning = false;
                    return;
                }
'@
    $agc=$agc.Remove($pos,$needle.Length).Insert($pos,$replacement)
    $agcChanged=$true
}

# Promote an actual producer/writeback signal into the existing coalesced drain path.
$signalStart=$agc.IndexOf('    private static void SignalGpuWaitMonitor(object memory)',[System.StringComparison]::Ordinal)
$signalEnd=$agc.IndexOf('    private static void ApplySubmittedDmaData(', $signalStart,[System.StringComparison]::Ordinal)
if($signalStart -lt 0 -or $signalEnd -lt 0){throw "$script:Tag SignalGpuWaitMonitor bounds missing."}
$signalSegment=$agc.Substring($signalStart,$signalEnd-$signalStart)
if(-not $signalSegment.Contains('SHARPEMU_V74_0_78_PRODUCER_WAKE_DRAIN')){
$newSignal=@'
    private static void SignalGpuWaitMonitor(object memory)
    {
        memory = CanonicalMemory(memory);
        if (!_submittedGpuStates.TryGetValue(memory, out var gpuState))
        {
            return;
        }

        lock (gpuState.WaitMonitorSignalGate)
        {
            gpuState.WaitMonitorSignalVersion++;
            Monitor.Pulse(gpuState.WaitMonitorSignalGate);
        }

        // SHARPEMU_V74_0_78_PRODUCER_WAKE_DRAIN
        // A real GPU writeback/visibility signal already changed observable
        // state. If real waiters exist, request the same authoritative
        // DrainResumableDcbs path immediately. No label/fence/value is forged.
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
    }

'@
    $agc=$agc.Substring(0,$signalStart)+$newSignal+$agc.Substring($signalEnd)
    $agcChanged=$true
}

if(-not $presenterChanged -and -not $agcChanged){
    Write-Host "$script:Tag State=AlreadyApplied"
}else{
    $backup=New-Backup
    try{
        if($presenterChanged){Write-Utf8NoBom $script:PresenterPath $presenter}
        if($agcChanged){Write-Utf8NoBom $script:AgcPath $agc}

        # Structural post-check before build.
        $p2=Read-Utf8 $script:PresenterPath
        $a2=Read-Utf8 $script:AgcPath
        if(-not $p2.Contains('SHARPEMU_V74_0_78_PRE_SNAPSHOT_SAMPLER_ALIAS_INDEX')){throw "$script:Tag presenter marker missing after patch."}
        if(-not $p2.Contains('TryResolveCachedTextureIdentityV74078')){throw "$script:Tag presenter resolver missing after patch."}
        if(-not $p2.Contains('_v74078TextureByContent[GetTextureContentKeyV74078(identity)] = identity;')){throw "$script:Tag presenter index update missing."}
        if(-not $a2.Contains('SHARPEMU_V74_0_78_PRODUCER_WAKE_DRAIN')){throw "$script:Tag producer wake marker missing."}
        if(-not ($a2 -match 'AllocateUninitializedArray<byte>\s*\(\s*checked\(\(int\)physicalSourceByteCount\)\s*\)')){throw "$script:Tag uninitialized snapshot replacement missing."}

        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY."
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
        Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
    }catch{
        Restore-Backup $backup
        throw
    }
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_78_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+".log")
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
if(-not(Test-Path -LiteralPath $project -PathType Leaf)){
    $project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
}
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
