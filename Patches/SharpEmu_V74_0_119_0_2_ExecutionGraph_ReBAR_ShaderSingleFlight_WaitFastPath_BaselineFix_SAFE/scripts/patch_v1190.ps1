param(
    [Parameter(Mandatory=$true)][string]$AgcSource,
    [Parameter(Mandatory=$true)][string]$PresenterSource,
    [Parameter(Mandatory=$true)][string]$HostPoolSource,
    [Parameter(Mandatory=$true)][string]$EnvelopeSource,
    [Parameter(Mandatory=$true)][string]$OutputAgc,
    [Parameter(Mandatory=$true)][string]$OutputPresenter,
    [Parameter(Mandatory=$true)][string]$OutputHostPool,
    [Parameter(Mandatory=$true)][string]$OutputEnvelope
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Write-Utf8NoBomV1190([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Normalize-NewlinesV1190([string]$Text){
    if($null-eq$Text){return ''}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function Replace-OnceV1190(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Name)
{
    $usesCrlf=$Text.Contains("`r`n")
    $t=Normalize-NewlinesV1190 $Text
    $o=Normalize-NewlinesV1190 $Old
    $n=Normalize-NewlinesV1190 $New
    $count=([regex]::Matches($t,[regex]::Escape($o))).Count
    if($count-ne1){
        $first=($o -split "`n"|Select-Object -First 1).Trim()
        $firstHits=if($first){([regex]::Matches($t,[regex]::Escape($first))).Count}else{0}
        throw "[V119.0-PATCH] anchor $Name count=$count expected=1 first_line_hits=$firstHits"
    }
    $result=$t.Replace($o,$n)
    if($usesCrlf){$result=$result.Replace("`n","`r`n")}
    return $result
}

$agc=[IO.File]::ReadAllText($AgcSource)
$presenter=[IO.File]::ReadAllText($PresenterSource)
$hostPool=[IO.File]::ReadAllText($HostPoolSource)
$envelope=[IO.File]::ReadAllText($EnvelopeSource)

$markers=@(
    $agc.Contains('SHARPEMU_V74_0_119_0_SHADER_SINGLEFLIGHT'),
    $presenter.Contains('SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT'),
    $hostPool.Contains('MemoryClassV1190'),
    $envelope.Contains('SHARPEMU_V74_0_119_0_EXECUTION_GRAPH_ENVELOPE')
)
$installed=(@($markers|Where-Object{$_})).Count
if($installed-ne0-and$installed-ne4){
    throw "[V119.0-PATCH] partial installation detected installed=$installed/4"
}
if($installed-eq4){
    Write-Utf8NoBomV1190 $OutputAgc $agc
    Write-Utf8NoBomV1190 $OutputPresenter $presenter
    Write-Utf8NoBomV1190 $OutputHostPool $hostPool
    Write-Utf8NoBomV1190 $OutputEnvelope $envelope
    Write-Host '[V119.0-PATCH] already_applied=1'
    exit 0
}

if(-not$presenter.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){
    throw '[V119.0-PATCH] V118.0.1 GPU-resident baseline required'
}
if($presenter.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
    throw '[V119.0-PATCH] forbidden V117.15 texture alias detected'
}

# =====================================================================
# 1) AGC shader single-flight + event-driven waiter fast path
# =====================================================================
$agc=Replace-OnceV1190 $agc @'
    private static readonly ConcurrentDictionary<
        (ulong Es, ulong State, ulong AliasAlignment),
        IGuestCompiledShader> _depthOnlyVertexShaderCache = new();

    // RootFix V18: compiled shader objects carry SPIR-V/MSL payloads and can
'@ @'
    private static readonly ConcurrentDictionary<
        (ulong Es, ulong State, ulong AliasAlignment),
        IGuestCompiledShader> _depthOnlyVertexShaderCache = new();

    // SHARPEMU_V74_0_119_0_SHADER_SINGLEFLIGHT
    // Canonical shader caches remain authoritative. The keyed monitors only
    // serialize identical cache misses so concurrent parser workers cannot
    // repeat the same Gen5 -> SPIR-V translation.
    private static readonly ConcurrentDictionary<
        (ulong Es, ulong EsState, ulong Ps, ulong PsState, ulong OutputLayout,
         uint OutputCount, uint Attributes, uint PsInputEna, uint PsInputAddr,
         ulong PsInputCntl, ulong AliasAlignment),
        object> _graphicsShaderCompileGatesV1190 = new();
    private static readonly ConcurrentDictionary<
        (ulong Cs, ulong State, uint LocalX, uint LocalY, uint LocalZ,
         uint WaveLanes, ulong AliasAlignment),
        object> _computeShaderCompileGatesV1190 = new();
    private static readonly object _graphicsShaderCompileOverflowGateV1190 = new();
    private static readonly object _computeShaderCompileOverflowGateV1190 = new();
    private static readonly bool _shaderSingleFlightV1190 =
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_SHADER_SINGLEFLIGHT_V1190"),
            "0",
            StringComparison.Ordinal);
    private static long _v1190ShaderSingleFlightWaits;
    private static long _v1190ShaderSingleFlightDedupHits;
    private static long _v1190WaitMonitorFastPolls;
    private static long _v1190WaitMonitorFullPolls;

    private static object GetGraphicsShaderCompileGateV1190(
        (ulong Es, ulong EsState, ulong Ps, ulong PsState, ulong OutputLayout,
         uint OutputCount, uint Attributes, uint PsInputEna, uint PsInputAddr,
         ulong PsInputCntl, ulong AliasAlignment) key)
    {
        if (_graphicsShaderCompileGatesV1190.TryGetValue(
                key,
                out var existing))
        {
            return existing;
        }

        if (_graphicsShaderCompileGatesV1190.Count >=
            _maxGraphicsShaderCacheEntries)
        {
            return _graphicsShaderCompileOverflowGateV1190;
        }

        return _graphicsShaderCompileGatesV1190.GetOrAdd(
            key,
            static _ => new object());
    }

    private static object GetComputeShaderCompileGateV1190(
        (ulong Cs, ulong State, uint LocalX, uint LocalY, uint LocalZ,
         uint WaveLanes, ulong AliasAlignment) key)
    {
        if (_computeShaderCompileGatesV1190.TryGetValue(
                key,
                out var existing))
        {
            return existing;
        }

        if (_computeShaderCompileGatesV1190.Count >=
            _maxComputeShaderCacheEntries)
        {
            return _computeShaderCompileOverflowGateV1190;
        }

        return _computeShaderCompileGatesV1190.GetOrAdd(
            key,
            static _ => new object());
    }

    // RootFix V18: compiled shader objects carry SPIR-V/MSL payloads and can
'@ 'agc-singleflight-fields'

$agc=Replace-OnceV1190 $agc @'
            int resumed;
            int remaining;
            lock (gpuState.Gate)
            {
                resumed = DrainResumableDcbs(ctx, gpuState, tracePackets: _traceAgc);
                remaining = GpuWaitRegistry.CountForMemory(CanonicalMemory(ctx.Memory));
'@ @'
            int resumed;
            int remaining;
            lock (gpuState.Gate)
            {
                // SHARPEMU_V74_0_119_0_WAITER_EVENT_FASTPATH
                // A producer already records exact satisfied addresses. Consume
                // the O(latched) index first; retain the full scan only when
                // no producer latch exists, preserving direct CPU-write and
                // retry/deadlock semantics.
                var canonicalWaitMemoryV1190 =
                    CanonicalMemory(ctx.Memory);
                var producerLatchedV1190 =
                    GpuWaitRegistry.HasLatchedSatisfiedV74100(
                        canonicalWaitMemoryV1190);
                resumed = DrainResumableDcbs(
                    ctx,
                    gpuState,
                    tracePackets: _traceAgc,
                    preferLatchedFastPathV740942:
                        producerLatchedV1190);
                if (producerLatchedV1190)
                {
                    Interlocked.Increment(
                        ref _v1190WaitMonitorFastPolls);
                }
                else
                {
                    Interlocked.Increment(
                        ref _v1190WaitMonitorFullPolls);
                }

                remaining = GpuWaitRegistry.CountForMemory(
                    canonicalWaitMemoryV1190);
'@ 'agc-wait-monitor-fastpath'

$agc=Replace-OnceV1190 $agc @'
                GpuWaitProfile.RecordMonitorPoll(resumed != 0);
                GpuWaitProfile.ReportIfDue(remaining);
                if (remaining == 0)
'@ @'
                GpuWaitProfile.RecordMonitorPoll(resumed != 0);
                GpuWaitProfile.ReportIfDue(remaining);

                var executionGraphPollsV1190 =
                    Volatile.Read(ref _v1190WaitMonitorFastPolls) +
                    Volatile.Read(ref _v1190WaitMonitorFullPolls);
                if (executionGraphPollsV1190 is 32 or 128 or 512 or 2048 ||
                    (executionGraphPollsV1190 > 2048 &&
                     (executionGraphPollsV1190 &
                      (executionGraphPollsV1190 - 1)) == 0))
                {
                    Console.Error.WriteLine(
                        $"[V74.0.119.0][EXECUTION_GRAPH] " +
                        $"wait_fast={Volatile.Read(ref _v1190WaitMonitorFastPolls)} " +
                        $"wait_full={Volatile.Read(ref _v1190WaitMonitorFullPolls)} " +
                        $"shader_waits={Volatile.Read(ref _v1190ShaderSingleFlightWaits)} " +
                        $"shader_dedup={Volatile.Read(ref _v1190ShaderSingleFlightDedupHits)}");
                }

                if (remaining == 0)
'@ 'agc-execution-graph-telemetry'

# Wrap the graphics cache-miss region in one keyed monitor.
$graphicsStart='        if (compiled.Vertex is null || compiled.Pixel is null)'
$graphicsEnd='        var useFixedFullscreenClear = usedFixedFullscreenClear;'
$normalizedAgc=Normalize-NewlinesV1190 $agc
$startIndex=$normalizedAgc.IndexOf($graphicsStart,$normalizedAgc.IndexOf('_graphicsShaderCache.TryGetValue(shaderKey, out var compiled);'))
$endIndex=$normalizedAgc.IndexOf($graphicsEnd,$startIndex)
if($startIndex-lt0-or$endIndex-lt0){throw '[V119.0-PATCH] graphics singleflight region not found'}
$oldGraphics=$normalizedAgc.Substring($startIndex,$endIndex-$startIndex)
$indentedGraphics=($oldGraphics -split "`n" | ForEach-Object{
    if($_.Length-eq0){''}else{'    '+$_}
}) -join "`n"
$newGraphics=@'
        object? graphicsCompileGateV1190 = null;
        if (_shaderSingleFlightV1190 &&
            (compiled.Vertex is null || compiled.Pixel is null))
        {
            graphicsCompileGateV1190 =
                GetGraphicsShaderCompileGateV1190(shaderKey);
            if (!Monitor.TryEnter(graphicsCompileGateV1190))
            {
                Interlocked.Increment(
                    ref _v1190ShaderSingleFlightWaits);
                Monitor.Enter(graphicsCompileGateV1190);
            }

            _graphicsShaderCache.TryGetValue(
                shaderKey,
                out compiled);
            if (compiled.Vertex is not null &&
                compiled.Pixel is not null)
            {
                Interlocked.Increment(
                    ref _v1190ShaderSingleFlightDedupHits);
            }
        }

        try
        {
__OLD_GRAPHICS__
        }
        finally
        {
            if (graphicsCompileGateV1190 is not null)
            {
                Monitor.Exit(graphicsCompileGateV1190);
            }
        }

'@
$newGraphics=$newGraphics.Replace('__OLD_GRAPHICS__',$indentedGraphics)
$normalizedAgc=$normalizedAgc.Substring(0,$startIndex)+$newGraphics+$normalizedAgc.Substring($endIndex)
$agc=if($agc.Contains("`r`n")){$normalizedAgc.Replace("`n","`r`n")}else{$normalizedAgc}

# Compute cache miss: keyed monitor + recheck.
$computeOld=@'
            _computeShaderCache.TryGetValue(shaderKey, out var computeShader);

            if (computeShader is null &&
                GuestGpu.Current.TryCompileComputeShader(
                    shaderState,
                    evaluation,
                    localSizeX,
                    localSizeY,
                    localSizeZ,
                    out computeShader,
                    out computeError,
                    totalGlobalBufferCount,
                    initialScalarBufferIndex: _bakeScalars
                        ? -1
                        : guestGlobalBufferCount,
                    waveLaneCount: dispatch.WaveLaneCount,
                    storageBufferOffsetAlignment:
                        _storageBufferOffsetAlignment))
            {
                DumpCompiledShader(
                    "cs",
                    shaderAddress,
                    shaderKey.Item2,
                    computeShader!,
                    shaderState.Program);
            }

'@
$computeNew=@'
            _computeShaderCache.TryGetValue(shaderKey, out var computeShader);

            if (computeShader is null)
            {
                object? computeCompileGateV1190 = null;
                if (_shaderSingleFlightV1190)
                {
                    computeCompileGateV1190 =
                        GetComputeShaderCompileGateV1190(shaderKey);
                    if (!Monitor.TryEnter(computeCompileGateV1190))
                    {
                        Interlocked.Increment(
                            ref _v1190ShaderSingleFlightWaits);
                        Monitor.Enter(computeCompileGateV1190);
                    }
                }

                try
                {
                    _computeShaderCache.TryGetValue(
                        shaderKey,
                        out computeShader);
                    if (computeShader is not null)
                    {
                        Interlocked.Increment(
                            ref _v1190ShaderSingleFlightDedupHits);
                    }
                    else if (GuestGpu.Current.TryCompileComputeShader(
                                 shaderState,
                                 evaluation,
                                 localSizeX,
                                 localSizeY,
                                 localSizeZ,
                                 out computeShader,
                                 out computeError,
                                 totalGlobalBufferCount,
                                 initialScalarBufferIndex: _bakeScalars
                                     ? -1
                                     : guestGlobalBufferCount,
                                 waveLaneCount: dispatch.WaveLaneCount,
                                 storageBufferOffsetAlignment:
                                     _storageBufferOffsetAlignment))
                    {
                        DumpCompiledShader(
                            "cs",
                            shaderAddress,
                            shaderKey.Item2,
                            computeShader!,
                            shaderState.Program);
                        if (_computeShaderCache.Count <
                            _maxComputeShaderCacheEntries)
                        {
                            _computeShaderCache.TryAdd(
                                shaderKey,
                                computeShader!);
                        }
                    }
                }
                finally
                {
                    if (computeCompileGateV1190 is not null)
                    {
                        Monitor.Exit(computeCompileGateV1190);
                    }
                }
            }

'@
$agc=Replace-OnceV1190 $agc $computeOld $computeNew 'agc-compute-singleflight'

# =====================================================================
# 2) V118 resident shader hot reference path
# =====================================================================
$presenter=Replace-OnceV1190 $presenter @'
            public required string Digest;
            public required byte[] SpirvSnapshot;
            public required ShaderModule Module;
'@ @'
            public required string Digest;
            public required byte[] SpirvSnapshot;

            // SHARPEMU_V74_0_119_0_RESIDENT_SHADER_REFERENCE_FASTPATH
            // AGC compiled shader cache commonly returns the same immutable
            // SPIR-V byte[] reference. Keep that exact reference so the hot
            // path is O(1); retain byte-for-byte SequenceEqual whenever a new
            // array appears at the same guest address.
            public required byte[] SourceReferenceV1190;
            public required ShaderModule Module;
'@ 'presenter-resident-reference-field'

$presenter=Replace-OnceV1190 $presenter @'
        private static long _v1180AddressExactHits;
        private static long _v1180ContentChanges;
'@ @'
        private static long _v1180AddressExactHits;
        private static long _v1190ResidentReferenceHits;
        private static long _v1190ResidentByteCompareHits;
        private static long _v1190ResidentCompareBytesAvoided;
        private static long _v1180ContentChanges;
'@ 'presenter-resident-reference-counters'

$presenter=Replace-OnceV1190 $presenter @'
            if (guestAddress != 0 &&
                _residentShadersByAddressV1180.TryGetValue(
                    (stage, guestAddress), out var byAddressV1180))
            {
                if (byAddressV1180.SpirvSnapshot.Length == spirv.Length &&
                    byAddressV1180.SpirvSnapshot.AsSpan().SequenceEqual(spirv))
                {
                    program = byAddressV1180;
                    Interlocked.Increment(ref _v1180AddressExactHits);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                Interlocked.Increment(ref _v1180ContentChanges);
            }
'@ @'
            if (guestAddress != 0 &&
                _residentShadersByAddressV1180.TryGetValue(
                    (stage, guestAddress), out var byAddressV1180))
            {
                if (ReferenceEquals(
                        byAddressV1180.SourceReferenceV1190,
                        spirv))
                {
                    program = byAddressV1180;
                    Interlocked.Increment(
                        ref _v1180AddressExactHits);
                    Interlocked.Increment(
                        ref _v1190ResidentReferenceHits);
                    Interlocked.Add(
                        ref _v1190ResidentCompareBytesAvoided,
                        spirv.Length);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                if (byAddressV1180.SpirvSnapshot.Length == spirv.Length &&
                    byAddressV1180.SpirvSnapshot.AsSpan().SequenceEqual(spirv))
                {
                    byAddressV1180.SourceReferenceV1190 = spirv;
                    program = byAddressV1180;
                    Interlocked.Increment(
                        ref _v1180AddressExactHits);
                    Interlocked.Increment(
                        ref _v1190ResidentByteCompareHits);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                Interlocked.Increment(ref _v1180ContentChanges);
            }
'@ 'presenter-resident-address-reference-fastpath'

$presenter=Replace-OnceV1190 $presenter @'
                SpirvSnapshot = spirv.ToArray(),
                Module = module,
'@ @'
                SpirvSnapshot = spirv.ToArray(),
                SourceReferenceV1190 = spirv,
                Module = module,
'@ 'presenter-resident-registration-reference'

$presenter=Replace-OnceV1190 $presenter @'
                        _residentShadersByAddressV1180[(stage, guestAddress)] = program;
                    }
                    Interlocked.Increment(ref _v1180DigestHits);
'@ @'
                        _residentShadersByAddressV1180[(stage, guestAddress)] = program;
                    }
                    byDigestV1180.SourceReferenceV1190 = spirv;
                    Interlocked.Increment(ref _v1180DigestHits);
'@ 'presenter-resident-digest-reference-refresh'

$presenter=Replace-OnceV1190 $presenter @'
                $"address_hits={Volatile.Read(ref _v1180AddressExactHits)} " +
                $"content_changes={Volatile.Read(ref _v1180ContentChanges)} " +
'@ @'
                $"address_hits={Volatile.Read(ref _v1180AddressExactHits)} " +
                $"reference_hits={Volatile.Read(ref _v1190ResidentReferenceHits)} " +
                $"byte_compare_hits={Volatile.Read(ref _v1190ResidentByteCompareHits)} " +
                $"compare_avoided_mb={Volatile.Read(ref _v1190ResidentCompareBytesAvoided) / (1024.0 * 1024.0):F2} " +
                $"content_changes={Volatile.Read(ref _v1180ContentChanges)} " +
'@ 'presenter-resident-telemetry'

# =====================================================================
# 3) ReBAR-aware direct read-only global buffer
# =====================================================================
$presenter=Replace-OnceV1190 $presenter @'
        private static readonly bool DeviceLocalReadOnlyGlobalsEnabled =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS"),
                "0",
                StringComparison.Ordinal);
'@ @'
        private static readonly bool DeviceLocalReadOnlyGlobalsEnabled =
            !string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS"),
                "0",
                StringComparison.Ordinal);

        // SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT
        // If Vulkan exposes a memory type which is simultaneously
        // DEVICE_LOCAL|HOST_VISIBLE|HOST_COHERENT, immutable shader globals can
        // be written directly into GPU-local mapped memory. This removes the
        // transient upload buffer + CmdCopyBuffer + transfer barrier. Unsupported
        // devices take the exact V117.12 path.
        private static readonly bool _rebarGlobalDirectV1190 =
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_REBAR_GLOBAL_DIRECT_V1190"),
                "0",
                StringComparison.Ordinal);
        private static long _v1190RebarGlobalDirectCount;
        private static long _v1190RebarGlobalDirectBytes;
        private static long _v1190RebarGlobalFallbackCount;
        private static long _v1190RebarSupportProbeCount;

        // 0 = unknown, 1 = a compatible BAR memory type was observed,
        // -1 = this device does not expose one for shader storage buffers.
        private int _rebarGlobalSupportStateV11901;
'@ 'presenter-rebar-fields'

$presenter=Replace-OnceV1190 $presenter @'
        private VkBuffer CreateHostBufferUninitializedV11712(
'@ @'
        private bool TryCreateRebarHostBufferUninitializedV1190(
            ulong requestedSize,
            BufferUsageFlags usage,
            out VkBuffer buffer,
            out DeviceMemory memory,
            out nint mapped)
        {
            buffer = default;
            memory = default;
            mapped = 0;

            // V119.0.1: do not create/destroy a probe VkBuffer on every global
            // binding when the driver exposes no BAR-visible device-local type.
            if (Volatile.Read(
                    ref _rebarGlobalSupportStateV11901) < 0)
            {
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            var size = Math.Max(
                requestedSize,
                (ulong)sizeof(uint));
            var capacity = BitOperations.RoundUpToPowerOf2(size);
            var key = new VulkanHostBufferPoolKey(
                usage,
                capacity,
                MemoryPropertyFlags.DeviceLocalBit);

            if (_hostBufferPool.TryRent(key, out var pooled))
            {
                buffer = pooled.Buffer;
                memory = pooled.Memory;
                mapped = pooled.Mapped;
                return true;
            }

            Interlocked.Increment(
                ref _v1190RebarSupportProbeCount);

            var bufferInfo = new BufferCreateInfo
            {
                SType = StructureType.BufferCreateInfo,
                Size = capacity,
                Usage = usage,
                SharingMode = SharingMode.Exclusive,
            };

            var createResultV11901 = _vk.CreateBuffer(
                _device,
                &bufferInfo,
                null,
                out var createdBuffer);
            if (createResultV11901 != Result.Success)
            {
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            _vk.GetBufferMemoryRequirements(
                _device,
                createdBuffer,
                out var requirements);
            if (!TryFindMemoryTypeV1190(
                    requirements.MemoryTypeBits,
                    MemoryPropertyFlags.HostVisibleBit |
                    MemoryPropertyFlags.HostCoherentBit |
                    MemoryPropertyFlags.DeviceLocalBit,
                    out var memoryTypeIndex))
            {
                _vk.DestroyBuffer(
                    _device,
                    createdBuffer,
                    null);
                Volatile.Write(
                    ref _rebarGlobalSupportStateV11901,
                    -1);
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            Volatile.Write(
                ref _rebarGlobalSupportStateV11901,
                1);

            var allocatedMemory = default(DeviceMemory);
            var memoryInfo = new MemoryAllocateInfo
            {
                SType = StructureType.MemoryAllocateInfo,
                AllocationSize = requirements.Size,
                MemoryTypeIndex = memoryTypeIndex,
            };
            var allocateResultV11901 = _vk.AllocateMemory(
                _device,
                &memoryInfo,
                null,
                out allocatedMemory);
            if (allocateResultV11901 != Result.Success)
            {
                // BAR heap pressure must never turn an optional optimization
                // into a fatal renderer error. Use the exact V117.12 path.
                _vk.DestroyBuffer(
                    _device,
                    createdBuffer,
                    null);
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            var bindResultV11901 = _vk.BindBufferMemory(
                _device,
                createdBuffer,
                allocatedMemory,
                0);
            if (bindResultV11901 != Result.Success)
            {
                _vk.DestroyBuffer(
                    _device,
                    createdBuffer,
                    null);
                _vk.FreeMemory(
                    _device,
                    allocatedMemory,
                    null);
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            void* persistentMapping = null;
            var mapResultV11901 = _vk.MapMemory(
                _device,
                allocatedMemory,
                0,
                capacity,
                0,
                &persistentMapping);
            if (mapResultV11901 != Result.Success ||
                persistentMapping is null)
            {
                _vk.DestroyBuffer(
                    _device,
                    createdBuffer,
                    null);
                _vk.FreeMemory(
                    _device,
                    allocatedMemory,
                    null);
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }

            try
            {
                var allocation = new VulkanHostBufferAllocation(
                    createdBuffer,
                    allocatedMemory,
                    key,
                    (nint)persistentMapping);
                _hostBufferPool.Register(allocation);

                buffer = createdBuffer;
                memory = allocatedMemory;
                mapped = (nint)persistentMapping;
                return true;
            }
            catch
            {
                // Registration happens after a successful persistent map. Clean
                // up in Vulkan lifetime order before falling back.
                _vk.UnmapMemory(
                    _device,
                    allocatedMemory);
                _vk.DestroyBuffer(
                    _device,
                    createdBuffer,
                    null);
                _vk.FreeMemory(
                    _device,
                    allocatedMemory,
                    null);
                Interlocked.Increment(
                    ref _v1190RebarGlobalFallbackCount);
                return false;
            }
        }

        private VkBuffer CreateHostBufferUninitializedV11712(
'@ 'presenter-rebar-host-helper'

$presenter=Replace-OnceV1190 $presenter @'
        private uint FindMemoryType(
            uint typeBits,
'@ @'
        private bool TryFindMemoryTypeV1190(
            uint typeBits,
            MemoryPropertyFlags requiredFlags,
            out uint memoryTypeIndex)
        {
            _vk.GetPhysicalDeviceMemoryProperties(
                _physicalDevice,
                out var properties);
            var memoryTypes = &properties.MemoryTypes.Element0;

            for (uint index = 0;
                 index < properties.MemoryTypeCount;
                 index++)
            {
                if ((typeBits & (1u << (int)index)) != 0 &&
                    (memoryTypes[index].PropertyFlags & requiredFlags) ==
                        requiredFlags)
                {
                    memoryTypeIndex = index;
                    return true;
                }
            }

            memoryTypeIndex = 0;
            return false;
        }

        private uint FindMemoryType(
            uint typeBits,
'@ 'presenter-rebar-memory-type-probe'

$presenter=Replace-OnceV1190 $presenter @'
            var byteBiasInt = checked((int)byteBias);
            var usage = DeviceLocalReadOnlyGlobalsEnabled
                ? BufferUsageFlags.TransferSrcBit
                : BufferUsageFlags.StorageBufferBit;
            var hostBuffer = CreateHostBufferUninitializedV11712(
                descriptorSize,
                usage,
                out var hostMemory,
                out var hostMapped);

            var successV11712 = false;
'@ @'
            var byteBiasInt = checked((int)byteBias);

            var rebarBufferV1190 = default(VkBuffer);
            var rebarMemoryV1190 = default(DeviceMemory);
            nint rebarMappedV1190 = 0;
            var rebarDirectV1190 = false;
            if (_rebarGlobalDirectV1190)
            {
                rebarDirectV1190 =
                    TryCreateRebarHostBufferUninitializedV1190(
                        descriptorSize,
                        BufferUsageFlags.StorageBufferBit,
                        out rebarBufferV1190,
                        out rebarMemoryV1190,
                        out rebarMappedV1190);
            }

            var usage = DeviceLocalReadOnlyGlobalsEnabled
                ? BufferUsageFlags.TransferSrcBit
                : BufferUsageFlags.StorageBufferBit;

            VkBuffer hostBuffer;
            DeviceMemory hostMemory;
            nint hostMapped;
            if (rebarDirectV1190)
            {
                hostBuffer = rebarBufferV1190;
                hostMemory = rebarMemoryV1190;
                hostMapped = rebarMappedV1190;
            }
            else
            {
                hostBuffer = CreateHostBufferUninitializedV11712(
                    descriptorSize,
                    usage,
                    out hostMemory,
                    out hostMapped);
            }

            var successV11712 = false;
'@ 'presenter-rebar-deferred-host-select'

$presenter=Replace-OnceV1190 $presenter @'
                TraceShaderGlobalDirectUploadV11712(countV11712);

                if (!DeviceLocalReadOnlyGlobalsEnabled)
                {
'@ @'
                TraceShaderGlobalDirectUploadV11712(countV11712);

                if (rebarDirectV1190)
                {
                    var directCountV1190 =
                        Interlocked.Increment(
                            ref _v1190RebarGlobalDirectCount);
                    var directBytesV1190 =
                        Interlocked.Add(
                            ref _v1190RebarGlobalDirectBytes,
                            guestBuffer.Length);
                    if (directCountV1190 <= 16 ||
                        (directCountV1190 &
                         (directCountV1190 - 1)) == 0)
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.119.0][REBAR_GLOBAL_DIRECT] " +
                            $"count={directCountV1190} " +
                            $"bytes={directBytesV1190} " +
                            $"mb={directBytesV1190 / (1024.0 * 1024.0):F2} " +
                            $"support={Volatile.Read(ref _rebarGlobalSupportStateV11901)} " +
                            $"probes={Volatile.Read(ref _v1190RebarSupportProbeCount)} " +
                            $"fallbacks={Volatile.Read(ref _v1190RebarGlobalFallbackCount)}");
                    }
                }

                if (rebarDirectV1190 ||
                    !DeviceLocalReadOnlyGlobalsEnabled)
                {
'@ 'presenter-rebar-direct-return'

# Host pool key separates ordinary host staging from DEVICE_LOCAL mapped ReBAR.
$hostPool=Replace-OnceV1190 $hostPool @'
internal readonly record struct VulkanHostBufferPoolKey(
    BufferUsageFlags Usage,
    ulong Capacity);
'@ @'
internal readonly record struct VulkanHostBufferPoolKey(
    BufferUsageFlags Usage,
    ulong Capacity,
    // SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT
    // Prevent a normal system-memory staging allocation from being rented by
    // the DEVICE_LOCAL mapped path (or vice versa).
    MemoryPropertyFlags MemoryClassV1190 = 0);
'@ 'hostpool-memory-class-key'

# =====================================================================
# 4) Demon's Souls execution envelope
# =====================================================================
$envelope=Replace-OnceV1190 $envelope @'
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");
'@ @'
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");

        // SHARPEMU_V74_0_119_0_EXECUTION_GRAPH_ENVELOPE
        // V118 proved pipeline identity is hot (>50k fast hits) but FPS did
        // not move. Keep its resident pipeline architecture, reduce its maximum
        // RAM ceiling, remove the ineffective V117.13 global-residency tracker,
        // and optimize the actual feed path without changing GPU ordering.
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "0");
        Set("SHARPEMU_SHADER_SINGLEFLIGHT_V1190", "1");
        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");
        Set("SHARPEMU_PROFILE_RENDER", "1");
        Set("SHARPEMU_PROFILE_RENDER_REPORT_S", "5");
        Set("SHARPEMU_TRACE_SHADER_PIPELINE_TIMING", "1");
'@ 'envelope-execution-graph'

Write-Utf8NoBomV1190 $OutputAgc $agc
Write-Utf8NoBomV1190 $OutputPresenter $presenter
Write-Utf8NoBomV1190 $OutputHostPool $hostPool
Write-Utf8NoBomV1190 $OutputEnvelope $envelope

Write-Host '[V119.0.1-PATCH] patch_ready=1 shader_singleflight=1 waiter_latched_fastpath=1 resident_reference_fastpath=1 rebar_direct_auto=1 shader_resident_max=1024 old_global_residency=0 queue_order_change=0 vkqueue_change=0 submit_change=0 barrier_change=0 image_lifetime_change=0'
