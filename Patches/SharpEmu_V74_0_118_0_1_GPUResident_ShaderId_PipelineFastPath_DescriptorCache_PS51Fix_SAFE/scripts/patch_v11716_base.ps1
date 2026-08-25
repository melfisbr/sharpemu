param(
    [Parameter(Mandatory=$true)][string]$PresenterSource,
    [Parameter(Mandatory=$true)][string]$EnvelopeSource,
    [Parameter(Mandatory=$true)][string]$OutputPresenter,
    [Parameter(Mandatory=$true)][string]$OutputEnvelope
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Write-Utf8NoBom([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function N([string]$Text){
    if($null-eq$Text){return ''}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function R1([string]$Text,[string]$Old,[string]$New,[string]$Name){
    $usesCrlf=$Text.Contains("`r`n")
    $t=N $Text;$o=N $Old;$n=N $New
    $count=([regex]::Matches($t,[regex]::Escape($o))).Count
    if($count-ne1){
        $first=($o -split "`n"|Select-Object -First 1).Trim()
        $hits=if([string]::IsNullOrEmpty($first)){0}else{
            ([regex]::Matches($t,[regex]::Escape($first))).Count
        }
        throw "[V74.0.117.16-PATCH] anchor $Name count=$count expected=1 first_line_hits=$hits normalized_eol=1"
    }
    $r=$t.Replace($o,$n)
    if($usesCrlf){$r=$r.Replace("`n","`r`n")}
    return $r
}

$presenter=[IO.File]::ReadAllText($PresenterSource)
$envelope=[IO.File]::ReadAllText($EnvelopeSource)

$mp='SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE'
$mq='SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_CACHE_ENVELOPE'
$flags=@($presenter.Contains($mp),$envelope.Contains($mq))
$installed=(@($flags|Where-Object{$_})).Count
if($installed-ne0-and$installed-ne2){
    throw "[V74.0.117.16-PATCH] partial installation detected installed=$installed/2"
}
if($installed-eq2){
    Write-Utf8NoBom $OutputPresenter $presenter
    Write-Utf8NoBom $OutputEnvelope $envelope
    Write-Host '[V74.0.117.16-PATCH] patch_ready=1 already_applied=1 block_sets=8 max_cached_sets=512 fence_release=1 descriptor_rewrite_after_fence_only=1 image_change=0 buffer_content_change=0 queue_change=0 submit_change=0 barrier_change=0'
    exit 0
}

if($presenter.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
    throw '[V74.0.117.16-PATCH] V117.15 still present; rollback first'
}
if(-not$presenter.Contains('SHARPEMU_V74_0_117_14_PRODUCER_ITEM_HEADROOM')){
    throw '[V74.0.117.16-PATCH] V117.14 presenter baseline missing'
}
if(-not$envelope.Contains('SHARPEMU_V74_0_117_14_PRODUCER_CRITICAL_PATH_ENVELOPE')){
    throw '[V74.0.117.16-PATCH] V117.14 envelope baseline missing'
}

# ------------------------------------------------------------------
# Cache fields. Dedicated pools are never mixed with legacy one-set pools.
# ------------------------------------------------------------------
$presenter=R1 $presenter @'
        private readonly Stack<DescriptorPool> _recycledDescriptorPools = new();
        private VulkanGuestQueueIdentity _activeGuestQueue =
'@ @'
        private readonly Stack<DescriptorPool> _recycledDescriptorPools = new();

        // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
        // Layout/pipeline objects are already cached, but the old hot path still
        // reset a one-set DescriptorPool and called vkAllocateDescriptorSets for
        // every draw/dispatch. Cache descriptor SETS themselves by immutable
        // DescriptorSetLayout. A lease returns only after the existing
        // submission fence retires TranslatedDrawResources, so UpdateDescriptorSets
        // never rewrites a set which can still be referenced by the GPU.
        private static readonly bool _descriptorSetCacheV11716 =
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DESCRIPTOR_SET_CACHE_V11716"),
                "0",
                StringComparison.Ordinal);
        private const int V11716DescriptorBlockSize = 8;
        private static readonly int _descriptorSetCacheMaxSetsV11716 =
            Math.Clamp(
                int.TryParse(
                    Environment.GetEnvironmentVariable(
                        "SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716"),
                    out var descriptorCacheMaxV11716)
                    ? descriptorCacheMaxV11716
                    : 512,
                V11716DescriptorBlockSize,
                4096);
        private readonly Dictionary<ulong, DescriptorSetCacheV11716>
            _descriptorSetCachesV11716 = [];
        private int _descriptorSetCachedAllocatedV11716;
        private int _descriptorSetCachedInUseV11716;
        private int _descriptorSetCachedPeakInUseV11716;
        private static long _v11716DescriptorAcquireCount;
        private static long _v11716DescriptorReuseHitCount;
        private static long _v11716DescriptorBlockAllocCalls;
        private static long _v11716DescriptorFallbackCount;

        private VulkanGuestQueueIdentity _activeGuestQueue =
'@ 'descriptor-cache-fields'

$presenter=R1 $presenter @'
        private sealed record DescriptorLayoutBundle(
            DescriptorSetLayout DescriptorSetLayout,
            PipelineLayout PipelineLayout);

        private readonly record struct DirtyGuestBufferRange(
'@ @'
        private sealed record DescriptorLayoutBundle(
            DescriptorSetLayout DescriptorSetLayout,
            PipelineLayout PipelineLayout);

        private sealed class DescriptorSetCacheV11716
        {
            public required DescriptorSetLayout Layout;
            public required int SampledImageCount;
            public required int StorageImageCount;
            public required int GlobalBufferCount;
            public Stack<DescriptorSetLeaseV11716> Free { get; } = new();
            public List<DescriptorPool> Pools { get; } = [];
        }

        private sealed class DescriptorSetLeaseV11716
        {
            public required DescriptorSetCacheV11716 Owner;
            public required DescriptorPool Pool;
            public required DescriptorSet Set;
            public bool InUse;
        }

        private readonly record struct DirtyGuestBufferRange(
'@ 'descriptor-cache-types'

$presenter=R1 $presenter @'
            public DescriptorPool DescriptorPool;
            public DescriptorSet DescriptorSet;
            public TextureResource[] Textures = [];
'@ @'
            public DescriptorPool DescriptorPool;
            public DescriptorSet DescriptorSet;
            public DescriptorSetLeaseV11716? DescriptorLeaseV11716;
            public TextureResource[] Textures = [];
'@ 'descriptor-lease-resource-field'

# ------------------------------------------------------------------
# Cache helpers inserted before descriptor hot path.
# ------------------------------------------------------------------
$presenter=R1 $presenter @'
        // SHARPEMU_V74_0_90_DESCRIPTOR_STACK_SCRATCH
        private static long _v74090DescriptorStackScratchTraceCount;

        [MethodImpl(MethodImplOptions.NoInlining)]
        private void CreateTranslatedDescriptorResources(
'@ @'
        // SHARPEMU_V74_0_90_DESCRIPTOR_STACK_SCRATCH
        private static long _v74090DescriptorStackScratchTraceCount;

        // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
        private bool AcquireDescriptorSetV11716(
            DescriptorSetLayout setLayout,
            int sampledImageCount,
            int storageImageCount,
            int globalBufferCount,
            TranslatedDrawResources resources)
        {
            if (!_descriptorSetCacheV11716 ||
                setLayout.Handle == 0)
            {
                Interlocked.Increment(
                    ref _v11716DescriptorFallbackCount);
                return false;
            }

            if (!_descriptorSetCachesV11716.TryGetValue(
                    setLayout.Handle,
                    out var cacheV11716))
            {
                cacheV11716 = new DescriptorSetCacheV11716
                {
                    Layout = setLayout,
                    SampledImageCount = sampledImageCount,
                    StorageImageCount = storageImageCount,
                    GlobalBufferCount = globalBufferCount,
                };
                _descriptorSetCachesV11716.Add(
                    setLayout.Handle,
                    cacheV11716);
            }
            else if (cacheV11716.SampledImageCount != sampledImageCount ||
                     cacheV11716.StorageImageCount != storageImageCount ||
                     cacheV11716.GlobalBufferCount != globalBufferCount)
            {
                // A layout handle should imply an identical resource shape.
                // Keep the old one-set path instead of guessing if that
                // invariant is ever violated.
                Interlocked.Increment(
                    ref _v11716DescriptorFallbackCount);
                return false;
            }

            DescriptorSetLeaseV11716 leaseV11716;
            if (cacheV11716.Free.TryPop(out var reusableV11716))
            {
                leaseV11716 = reusableV11716;
                Interlocked.Increment(
                    ref _v11716DescriptorReuseHitCount);
            }
            else
            {
                if (_descriptorSetCachedAllocatedV11716 +
                        V11716DescriptorBlockSize >
                    _descriptorSetCacheMaxSetsV11716)
                {
                    Interlocked.Increment(
                        ref _v11716DescriptorFallbackCount);
                    return false;
                }

                var poolSizesV11716 =
                    stackalloc DescriptorPoolSize[3];
                var poolSizeCountV11716 = 0;
                if (sampledImageCount != 0)
                {
                    poolSizesV11716[poolSizeCountV11716++] =
                        new DescriptorPoolSize
                        {
                            Type =
                                DescriptorType.CombinedImageSampler,
                            DescriptorCount = checked(
                                (uint)(
                                    sampledImageCount *
                                    V11716DescriptorBlockSize)),
                        };
                }
                if (storageImageCount != 0)
                {
                    poolSizesV11716[poolSizeCountV11716++] =
                        new DescriptorPoolSize
                        {
                            Type = DescriptorType.StorageImage,
                            DescriptorCount = checked(
                                (uint)(
                                    storageImageCount *
                                    V11716DescriptorBlockSize)),
                        };
                }
                if (globalBufferCount != 0)
                {
                    poolSizesV11716[poolSizeCountV11716++] =
                        new DescriptorPoolSize
                        {
                            Type = DescriptorType.StorageBuffer,
                            DescriptorCount = checked(
                                (uint)(
                                    globalBufferCount *
                                    V11716DescriptorBlockSize)),
                        };
                }

                var poolInfoV11716 = new DescriptorPoolCreateInfo
                {
                    SType = StructureType.DescriptorPoolCreateInfo,
                    MaxSets = V11716DescriptorBlockSize,
                    PoolSizeCount = (uint)poolSizeCountV11716,
                    PPoolSizes = poolSizesV11716,
                };
                DescriptorPool poolV11716;
                Check(
                    _vk.CreateDescriptorPool(
                        _device,
                        &poolInfoV11716,
                        null,
                        out poolV11716),
                    "vkCreateDescriptorPool(v117.16 block)");

                var layoutsV11716 =
                    stackalloc DescriptorSetLayout[
                        V11716DescriptorBlockSize];
                var setsV11716 =
                    stackalloc DescriptorSet[
                        V11716DescriptorBlockSize];
                for (var indexV11716 = 0;
                     indexV11716 < V11716DescriptorBlockSize;
                     indexV11716++)
                {
                    layoutsV11716[indexV11716] = setLayout;
                }

                var allocateInfoV11716 =
                    new DescriptorSetAllocateInfo
                    {
                        SType =
                            StructureType.DescriptorSetAllocateInfo,
                        DescriptorPool = poolV11716,
                        DescriptorSetCount =
                            V11716DescriptorBlockSize,
                        PSetLayouts = layoutsV11716,
                    };

                try
                {
                    Check(
                        _vk.AllocateDescriptorSets(
                            _device,
                            &allocateInfoV11716,
                            setsV11716),
                        "vkAllocateDescriptorSets(v117.16 block)");
                }
                catch
                {
                    _vk.DestroyDescriptorPool(
                        _device,
                        poolV11716,
                        null);
                    throw;
                }

                cacheV11716.Pools.Add(poolV11716);
                _descriptorSetCachedAllocatedV11716 +=
                    V11716DescriptorBlockSize;
                Interlocked.Increment(
                    ref _v11716DescriptorBlockAllocCalls);

                leaseV11716 = new DescriptorSetLeaseV11716
                {
                    Owner = cacheV11716,
                    Pool = poolV11716,
                    Set = setsV11716[0],
                    InUse = false,
                };

                for (var indexV11716 = 1;
                     indexV11716 < V11716DescriptorBlockSize;
                     indexV11716++)
                {
                    cacheV11716.Free.Push(
                        new DescriptorSetLeaseV11716
                        {
                            Owner = cacheV11716,
                            Pool = poolV11716,
                            Set = setsV11716[indexV11716],
                            InUse = false,
                        });
                }
            }

            if (leaseV11716.InUse)
            {
                throw new InvalidOperationException(
                    "V117.16 descriptor lease reused while in-flight");
            }

            leaseV11716.InUse = true;
            resources.DescriptorLeaseV11716 = leaseV11716;
            resources.DescriptorPool = leaseV11716.Pool;
            resources.DescriptorSet = leaseV11716.Set;

            _descriptorSetCachedInUseV11716++;
            if (_descriptorSetCachedInUseV11716 >
                _descriptorSetCachedPeakInUseV11716)
            {
                _descriptorSetCachedPeakInUseV11716 =
                    _descriptorSetCachedInUseV11716;
            }

            var acquireV11716 = Interlocked.Increment(
                ref _v11716DescriptorAcquireCount);
            if (acquireV11716 <= 32 ||
                (acquireV11716 & (acquireV11716 - 1)) == 0)
            {
                var blockCallsV11716 = Volatile.Read(
                    ref _v11716DescriptorBlockAllocCalls);
                var fallbackV11716 = Volatile.Read(
                    ref _v11716DescriptorFallbackCount);
                Console.Error.WriteLine(
                    $"[V74.0.117.16][DESCRIPTOR_SET_CACHE] " +
                    $"acquires={acquireV11716} " +
                    $"hits={Volatile.Read(ref _v11716DescriptorReuseHitCount)} " +
                    $"block_alloc_calls={blockCallsV11716} " +
                    $"cached_sets={_descriptorSetCachedAllocatedV11716} " +
                    $"fallbacks={fallbackV11716} " +
                    $"in_use={_descriptorSetCachedInUseV11716} " +
                    $"peak={_descriptorSetCachedPeakInUseV11716} " +
                    $"alloc_calls_saved={Math.Max(0L, acquireV11716 - blockCallsV11716)} " +
                    $"reset_calls_saved={acquireV11716}");
            }

            return true;
        }

        private void ReleaseDescriptorSetV11716(
            DescriptorSetLeaseV11716 lease)
        {
            if (!lease.InUse)
            {
                return;
            }

            lease.InUse = false;
            _descriptorSetCachedInUseV11716 =
                Math.Max(
                    0,
                    _descriptorSetCachedInUseV11716 - 1);
            lease.Owner.Free.Push(lease);
        }

        private void DestroyDescriptorSetCacheV11716()
        {
            foreach (var cacheV11716 in
                     _descriptorSetCachesV11716.Values)
            {
                foreach (var poolV11716 in
                         cacheV11716.Pools)
                {
                    if (poolV11716.Handle != 0)
                    {
                        _vk.DestroyDescriptorPool(
                            _device,
                            poolV11716,
                            null);
                    }
                }
            }

            _descriptorSetCachesV11716.Clear();
            _descriptorSetCachedAllocatedV11716 = 0;
            _descriptorSetCachedInUseV11716 = 0;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private void CreateTranslatedDescriptorResources(
'@ 'descriptor-cache-helpers'

# ------------------------------------------------------------------
# Replace one-set pool setup with cache-first + exact fallback.
# ------------------------------------------------------------------
$presenter=R1 $presenter @'
            var setLayout = layout.DescriptorSetLayout;
            if (_recycledDescriptorPools.TryPop(out var recycledPool))
            {
                Check(
                    _vk.ResetDescriptorPool(_device, recycledPool, 0),
                    "vkResetDescriptorPool");
                resources.DescriptorPool = recycledPool;
            }
            else
            {
                var genericPoolSizes = stackalloc DescriptorPoolSize[3];
                genericPoolSizes[0] = new DescriptorPoolSize
                {
                    Type = DescriptorType.CombinedImageSampler,
                    DescriptorCount = 256,
                };
                genericPoolSizes[1] = new DescriptorPoolSize
                {
                    Type = DescriptorType.StorageImage,
                    DescriptorCount = 64,
                };
                genericPoolSizes[2] = new DescriptorPoolSize
                {
                    Type = DescriptorType.StorageBuffer,
                    DescriptorCount = 64,
                };
                var poolInfo = new DescriptorPoolCreateInfo
                {
                    SType = StructureType.DescriptorPoolCreateInfo,
                    MaxSets = 1,
                    PoolSizeCount = 3,
                    PPoolSizes = genericPoolSizes,
                };
                DescriptorPool descriptorPool;
                Check(
                    _vk.CreateDescriptorPool(
                        _device,
                        &poolInfo,
                        null,
                        out descriptorPool),
                    "vkCreateDescriptorPool");
                resources.DescriptorPool = descriptorPool;
            }

            var allocateInfo = new DescriptorSetAllocateInfo
            {
                SType = StructureType.DescriptorSetAllocateInfo,
                DescriptorPool = resources.DescriptorPool,
                DescriptorSetCount = 1,
                PSetLayouts = &setLayout,
            };
            DescriptorSet descriptorSet;
            Check(
                _vk.AllocateDescriptorSets(_device, &allocateInfo, out descriptorSet),
                "vkAllocateDescriptorSets");
            resources.DescriptorSet = descriptorSet;

            // Existing generic descriptor-pool budgets cap these practical
            // counts. Keep scratch on the renderer stack instead of allocating
            // three managed arrays per draw/dispatch.
            if (sampledImageCount > 256 ||
                storageImageCount > 64 ||
                globalBufferCount > 64 ||
                bindingCount > 321)
            {
                throw new InvalidOperationException(
                    $"Descriptor binding set exceeds existing pool limits: " +
                    $"sampled={sampledImageCount} storage={storageImageCount} " +
                    $"globals={globalBufferCount} bindings={bindingCount}.");
            }
'@ @'
            var setLayout = layout.DescriptorSetLayout;

            // Existing generic descriptor-pool budgets cap these practical
            // counts. Keep the same limits as V117.14.
            if (sampledImageCount > 256 ||
                storageImageCount > 64 ||
                globalBufferCount > 64 ||
                bindingCount > 321)
            {
                throw new InvalidOperationException(
                    $"Descriptor binding set exceeds existing pool limits: " +
                    $"sampled={sampledImageCount} storage={storageImageCount} " +
                    $"globals={globalBufferCount} bindings={bindingCount}.");
            }

            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
            if (!AcquireDescriptorSetV11716(
                    setLayout,
                    sampledImageCount,
                    storageImageCount,
                    globalBufferCount,
                    resources))
            {
                // Exact V117.14 fallback. Cached-block budget exhaustion or an
                // unexpected layout-shape mismatch never changes semantics.
                if (_recycledDescriptorPools.TryPop(
                        out var recycledPool))
                {
                    Check(
                        _vk.ResetDescriptorPool(
                            _device,
                            recycledPool,
                            0),
                        "vkResetDescriptorPool");
                    resources.DescriptorPool = recycledPool;
                }
                else
                {
                    var genericPoolSizes =
                        stackalloc DescriptorPoolSize[3];
                    genericPoolSizes[0] =
                        new DescriptorPoolSize
                        {
                            Type =
                                DescriptorType.CombinedImageSampler,
                            DescriptorCount = 256,
                        };
                    genericPoolSizes[1] =
                        new DescriptorPoolSize
                        {
                            Type = DescriptorType.StorageImage,
                            DescriptorCount = 64,
                        };
                    genericPoolSizes[2] =
                        new DescriptorPoolSize
                        {
                            Type = DescriptorType.StorageBuffer,
                            DescriptorCount = 64,
                        };
                    var poolInfo = new DescriptorPoolCreateInfo
                    {
                        SType =
                            StructureType.DescriptorPoolCreateInfo,
                        MaxSets = 1,
                        PoolSizeCount = 3,
                        PPoolSizes = genericPoolSizes,
                    };
                    DescriptorPool descriptorPool;
                    Check(
                        _vk.CreateDescriptorPool(
                            _device,
                            &poolInfo,
                            null,
                            out descriptorPool),
                        "vkCreateDescriptorPool");
                    resources.DescriptorPool =
                        descriptorPool;
                }

                var allocateInfo =
                    new DescriptorSetAllocateInfo
                    {
                        SType =
                            StructureType.DescriptorSetAllocateInfo,
                        DescriptorPool =
                            resources.DescriptorPool,
                        DescriptorSetCount = 1,
                        PSetLayouts = &setLayout,
                    };
                DescriptorSet descriptorSet;
                Check(
                    _vk.AllocateDescriptorSets(
                        _device,
                        &allocateInfo,
                        out descriptorSet),
                    "vkAllocateDescriptorSets");
                resources.DescriptorSet = descriptorSet;
            }
'@ 'descriptor-cache-hotpath'

# ------------------------------------------------------------------
# Fence retirement releases cached descriptor set; fallback keeps old pool path.
# ------------------------------------------------------------------
$presenter=R1 $presenter @'
            if (resources.DescriptorPool.Handle != 0)
            {
                if (_recycledDescriptorPools.Count < 32)
                {
                    _recycledDescriptorPools.Push(resources.DescriptorPool);
                }
                else
                {
                    _vk.DestroyDescriptorPool(_device, resources.DescriptorPool, null);
                }
            }
'@ @'
            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
            if (resources.DescriptorLeaseV11716 is { } descriptorLeaseV11716)
            {
                resources.DescriptorLeaseV11716 = null;
                ReleaseDescriptorSetV11716(
                    descriptorLeaseV11716);
                resources.DescriptorPool = default;
                resources.DescriptorSet = default;
            }
            else if (resources.DescriptorPool.Handle != 0)
            {
                if (_recycledDescriptorPools.Count < 32)
                {
                    _recycledDescriptorPools.Push(resources.DescriptorPool);
                }
                else
                {
                    _vk.DestroyDescriptorPool(
                        _device,
                        resources.DescriptorPool,
                        null);
                }
            }
'@ 'descriptor-cache-fence-release'

# ------------------------------------------------------------------
# Dispose cached pools only after DeviceWaitIdle/Drain/Collect.
# ------------------------------------------------------------------
$presenter=R1 $presenter @'
            _graphicsPipelines.Clear();
            foreach (var layout in _descriptorLayouts.Values)
'@ @'
            _graphicsPipelines.Clear();

            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
            // DeviceWaitIdle + frame/submission drain above guarantees no
            // descriptor set remains referenced by GPU commands here.
            DestroyDescriptorSetCacheV11716();

            foreach (var layout in _descriptorLayouts.Values)
'@ 'descriptor-cache-dispose'

# ------------------------------------------------------------------
# Envelope enable only. No queue, submit, barrier, texture or buffer policy.
# ------------------------------------------------------------------
$envelope=R1 $envelope @'
        Set("SHARPEMU_PLANNED_PRODUCER_QUEUE_PRIORITY", "1");
'@ @'
        Set("SHARPEMU_PLANNED_PRODUCER_QUEUE_PRIORITY", "1");

        // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_CACHE_ENVELOPE
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "512");
'@ 'descriptor-cache-envelope'

Write-Utf8NoBom $OutputPresenter $presenter
Write-Utf8NoBom $OutputEnvelope $envelope
Write-Host '[V74.0.117.16-PATCH] patch_ready=1 already_applied=0 block_sets=8 max_cached_sets=512 fence_release=1 descriptor_rewrite_after_fence_only=1 image_change=0 buffer_content_change=0 queue_change=0 submit_change=0 barrier_change=0'
