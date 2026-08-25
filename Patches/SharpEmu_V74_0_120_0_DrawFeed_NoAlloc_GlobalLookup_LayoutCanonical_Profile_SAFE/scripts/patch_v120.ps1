param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Output
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Write-Utf8NoBomV120([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Normalize-NewlinesV120([string]$Text){
    if($null-eq$Text){return ''}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function Replace-OnceV120(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Name)
{
    $usesCrlf=$Text.Contains("`r`n")
    $normalizedText=Normalize-NewlinesV120 $Text
    $normalizedOld=Normalize-NewlinesV120 $Old
    $normalizedNew=Normalize-NewlinesV120 $New
    $count=([regex]::Matches(
        $normalizedText,
        [regex]::Escape($normalizedOld))).Count
    if($count-ne1){
        $first=($normalizedOld -split "`n"|Select-Object -First 1).Trim()
        $firstHits=if([string]::IsNullOrEmpty($first)){0}else{
            ([regex]::Matches($normalizedText,[regex]::Escape($first))).Count
        }
        throw "[V74.0.120.0-PATCH] anchor $Name count=$count expected=1 first_line_hits=$firstHits"
    }
    $result=$normalizedText.Replace($normalizedOld,$normalizedNew)
    if($usesCrlf){$result=$result.Replace("`n","`r`n")}
    return $result
}

$text=[IO.File]::ReadAllText($Source)
if($text.Contains('SHARPEMU_V74_0_120_0_DRAW_FEED_HOTPATH')){
    Write-Utf8NoBomV120 $Output $text
    Write-Host '[V74.0.120.0-PATCH] already_applied=1'
    exit 0
}
if($text.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
    throw '[V74.0.120.0-PATCH] V117.15 texture alias is forbidden'
}
if(-not$text.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){
    throw '[V74.0.120.0-PATCH] V118 resident shader baseline missing'
}
if(-not$text.Contains('SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE')){
    throw '[V74.0.120.0-PATCH] V117.16 descriptor cache baseline missing'
}

# ------------------------------------------------------------------
# Fields: exact structural caches + telemetry only, no Vulkan ownership.
# ------------------------------------------------------------------
$text=Replace-OnceV120 $text @'
        private readonly Dictionary<byte[], string> _shaderDigests =
            new(ReferenceEqualityComparer.Instance);
'@ @'
        // SHARPEMU_V74_0_120_0_DRAW_FEED_HOTPATH
        // The V118/V119 run proved pipeline identity is hot but Draw still owns
        // 30-61% of renderer self-time. These caches canonicalize CPU-only
        // structural keys and remove transient collections. They never cache
        // guest bytes, VkImage state or command buffers.
        private readonly Dictionary<ResourceLayoutShapeV120, string>
            _resourceLayoutKeyCacheV120 = [];
        private readonly Dictionary<TargetFormatLayoutShapeV120, string>
            _targetFormatLayoutKeyCacheV120 = [];
        private readonly Dictionary<BlendLayoutShapeV120, string>
            _blendLayoutKeyCacheV120 = [];
        private static long _v120DrawHotpathCount;
        private static long _v120ReadonlyPrepareFastReturns;
        private static long _v120SingleWritablePrepareFastPaths;
        private static long _v120GlobalAllocationLookups;
        private static long _v120GlobalAllocationBinarySteps;
        private static long _v120GlobalAllocationLinearCandidatesAvoided;
        private static long _v120ZeroVertexNoAlloc;
        private static long _v120SingleVertexNoAlloc;
        private static long _v120FeedbackLinearProbes;
        private static long _v120ResourceLayoutCacheHits;
        private static long _v120ResourceLayoutCacheMisses;
        private static long _v120TargetLayoutCacheHits;
        private static long _v120TargetLayoutCacheMisses;
        private static long _v120BlendLayoutCacheHits;
        private static long _v120BlendLayoutCacheMisses;
        private static long _v120ZeroVertexLayoutHits;

        private readonly Dictionary<byte[], string> _shaderDigests =
            new(ReferenceEqualityComparer.Instance);
'@ 'draw-hotpath-fields'

# Key record structs near descriptor cache types.
$text=Replace-OnceV120 $text @'
        private readonly record struct DirtyGuestBufferRange(
'@ @'
        private readonly record struct ResourceLayoutShapeV120(
            int GlobalCount,
            int TextureCount,
            ulong StorageMask0,
            ulong StorageMask1,
            ulong StorageMask2,
            ulong StorageMask3);

        private readonly record struct TargetFormatLayoutShapeV120(
            int Count,
            Format F0,
            Format F1,
            Format F2,
            Format F3,
            Format F4,
            Format F5,
            Format F6,
            Format F7);

        private readonly record struct BlendLayoutShapeV120(
            int Count,
            GuestBlendState B0,
            GuestBlendState B1,
            GuestBlendState B2,
            GuestBlendState B3,
            GuestBlendState B4,
            GuestBlendState B5,
            GuestBlendState B6,
            GuestBlendState B7);

        private readonly record struct DirtyGuestBufferRange(
'@ 'draw-hotpath-key-types'

# Empty arrays use shared empty arrays.
$text=Replace-OnceV120 $text @'
                Textures = new TextureResource[draw.Textures.Count],
                GlobalMemoryBuffers =
                    new GlobalBufferResource[draw.GlobalMemoryBuffers.Count],
                VertexBuffers = new VertexBufferResource[draw.VertexBuffers.Count],
'@ @'
                Textures = draw.Textures.Count == 0
                    ? []
                    : new TextureResource[draw.Textures.Count],
                GlobalMemoryBuffers = draw.GlobalMemoryBuffers.Count == 0
                    ? []
                    : new GlobalBufferResource[draw.GlobalMemoryBuffers.Count],
                VertexBuffers = draw.VertexBuffers.Count == 0
                    ? []
                    : new VertexBufferResource[draw.VertexBuffers.Count],
'@ 'empty-resource-arrays'

# Feedback target: remove LINQ/delegate from every texture binding.
$text=Replace-OnceV120 $text @'
                    var feedbackTarget = feedbackTargets?.FirstOrDefault(target =>
                        ReferenceEquals(resolved.GuestImage, target));
'@ @'
                    var feedbackTarget =
                        FindFeedbackTargetV120(
                            resolved.GuestImage,
                            feedbackTargets);
'@ 'feedback-target-no-linq'

# Vertex resource creation: no Dictionary for zero/one vertex binding.
$text=Replace-OnceV120 $text @'
                var sharedVertexResources = new Dictionary<
                    byte[], VertexBufferResource>(
                    System.Collections.Generic.ReferenceEqualityComparer.Instance);
                for (var index = 0; index < draw.VertexBuffers.Count; index++)
                {
                    var guestVertex = draw.VertexBuffers[index];
                    if (sharedVertexResources.TryGetValue(
                            guestVertex.Data,
                            out var sharedVertex))
                    {
                        resources.VertexBuffers[index] =
                            CreateVertexBufferAlias(sharedVertex, guestVertex);
                    }
                    else
                    {
                        var vertexResource =
                            CreateVertexBufferResource(guestVertex);
                        resources.VertexBuffers[index] = vertexResource;
                        sharedVertexResources.Add(guestVertex.Data, vertexResource);
                    }
                }
'@ @'
                if (draw.VertexBuffers.Count == 0)
                {
                    Interlocked.Increment(ref _v120ZeroVertexNoAlloc);
                }
                else if (draw.VertexBuffers.Count == 1)
                {
                    resources.VertexBuffers[0] =
                        CreateVertexBufferResource(draw.VertexBuffers[0]);
                    Interlocked.Increment(ref _v120SingleVertexNoAlloc);
                }
                else
                {
                    var sharedVertexResources = new Dictionary<
                        byte[], VertexBufferResource>(
                        System.Collections.Generic.ReferenceEqualityComparer.Instance);
                    for (var index = 0; index < draw.VertexBuffers.Count; index++)
                    {
                        var guestVertex = draw.VertexBuffers[index];
                        if (sharedVertexResources.TryGetValue(
                                guestVertex.Data,
                                out var sharedVertex))
                        {
                            resources.VertexBuffers[index] =
                                CreateVertexBufferAlias(sharedVertex, guestVertex);
                        }
                        else
                        {
                            var vertexResource =
                                CreateVertexBufferResource(guestVertex);
                            resources.VertexBuffers[index] = vertexResource;
                            sharedVertexResources.Add(
                                guestVertex.Data,
                                vertexResource);
                        }
                    }
                }
'@ 'vertex-zero-one-noalloc'

# Finally: no HashSet for zero/one vertex binding.
$text=Replace-OnceV120 $text @'
                var returnedVertexData = new HashSet<byte[]>(
                    System.Collections.Generic.ReferenceEqualityComparer.Instance);
                foreach (var vertex in draw.VertexBuffers)
                {
                    if (vertex.Pooled && returnedVertexData.Add(vertex.Data))
                    {
                        GuestDataPool.Shared.Return(vertex.Data);
                    }
                }
'@ @'
                if (draw.VertexBuffers.Count == 1)
                {
                    var vertexV120 = draw.VertexBuffers[0];
                    if (vertexV120.Pooled)
                    {
                        GuestDataPool.Shared.Return(vertexV120.Data);
                    }
                }
                else if (draw.VertexBuffers.Count > 1)
                {
                    var returnedVertexData = new HashSet<byte[]>(
                        System.Collections.Generic.ReferenceEqualityComparer.Instance);
                    foreach (var vertex in draw.VertexBuffers)
                    {
                        if (vertex.Pooled &&
                            returnedVertexData.Add(vertex.Data))
                        {
                            GuestDataPool.Shared.Return(vertex.Data);
                        }
                    }
                }

                TraceDrawHotpathV120();
'@ 'vertex-return-zero-one-noalloc'

# Prepare writable allocations: no List/Sort/Merge for read-only or single writable range.
$text=Replace-OnceV120 $text @'
            var ranges = new List<(ulong Start, ulong End)>(buffers.Count);
            foreach (var buffer in buffers)
            {
                // Persistent mapped guest allocations are only necessary when a
                // shader can write the resource and the guest CPU may observe it.
                // Immutable inputs use per-submission DEVICE_LOCAL buffers.
                if (buffer.BaseAddress == 0 || !buffer.Writable)
                {
                    continue;
                }

                var size = (ulong)Math.Max(buffer.Length, sizeof(uint));
                if (buffer.BaseAddress > ulong.MaxValue - size - 3)
                {
                    continue;
                }

                var alignedStart = buffer.BaseAddress &
                    ~(GuestStorageBufferOffsetAlignment - 1);
                var paddedEnd = (buffer.BaseAddress + size + 3) & ~3UL;
                ranges.Add((
                    alignedStart,
                    paddedEnd));
            }

            if (ranges.Count == 0)
            {
                return;
            }

            ranges.Sort(static (left, right) => left.Start.CompareTo(right.Start));
'@ @'
            var writableRangeCountV120 = 0;
            var firstWritableStartV120 = 0UL;
            var firstWritableEndV120 = 0UL;
            foreach (var buffer in buffers)
            {
                if (buffer.BaseAddress == 0 || !buffer.Writable)
                {
                    continue;
                }

                var sizeV120 =
                    (ulong)Math.Max(buffer.Length, sizeof(uint));
                if (buffer.BaseAddress >
                    ulong.MaxValue - sizeV120 - 3)
                {
                    continue;
                }

                var alignedStartV120 = buffer.BaseAddress &
                    ~(GuestStorageBufferOffsetAlignment - 1);
                var paddedEndV120 =
                    (buffer.BaseAddress + sizeV120 + 3) & ~3UL;
                writableRangeCountV120++;
                if (writableRangeCountV120 == 1)
                {
                    firstWritableStartV120 = alignedStartV120;
                    firstWritableEndV120 = paddedEndV120;
                }
            }

            if (writableRangeCountV120 == 0)
            {
                Interlocked.Increment(
                    ref _v120ReadonlyPrepareFastReturns);
                return;
            }

            if (writableRangeCountV120 == 1)
            {
                Interlocked.Increment(
                    ref _v120SingleWritablePrepareFastPaths);
                EnsureGuestBufferAllocation(
                    firstWritableStartV120,
                    firstWritableEndV120);
                return;
            }

            var ranges =
                new List<(ulong Start, ulong End)>(
                    writableRangeCountV120);
            foreach (var buffer in buffers)
            {
                if (buffer.BaseAddress == 0 || !buffer.Writable)
                {
                    continue;
                }

                var size =
                    (ulong)Math.Max(buffer.Length, sizeof(uint));
                if (buffer.BaseAddress >
                    ulong.MaxValue - size - 3)
                {
                    continue;
                }

                var alignedStart = buffer.BaseAddress &
                    ~(GuestStorageBufferOffsetAlignment - 1);
                var paddedEnd =
                    (buffer.BaseAddress + size + 3) & ~3UL;
                ranges.Add((alignedStart, paddedEnd));
            }

            ranges.Sort(static (left, right) => left.Start.CompareTo(right.Start));
'@ 'prepare-global-noalloc'

# Linear allocation scan -> binary search helper.
$text=Replace-OnceV120 $text @'
            GuestBufferAllocation? allocation = null;
            foreach (var candidate in _guestBufferAllocations)
            {
                if (candidate.BaseAddress > guestBuffer.BaseAddress ||
                    candidate.BaseAddress + candidate.Size < endAddress)
                {
                    continue;
                }

                allocation = candidate;
                break;
            }
'@ @'
            var allocation =
                FindGuestBufferAllocationV120(
                    guestBuffer.BaseAddress,
                    endAddress);
'@ 'global-allocation-binary-call'

# Layout-key methods -> exact canonical caches and helper functions.
$text=Replace-OnceV120 $text @'
        private static string GetResourceLayoutKey(TranslatedDrawResources resources) =>
            resources.ResourceLayoutKey ??= BuildResourceLayoutKey(resources);

        private static string GetVertexLayoutKey(TranslatedDrawResources resources) =>
            resources.VertexLayoutKey ??= BuildVertexLayoutKey(resources);

        private static string BuildResourceLayoutKey(TranslatedDrawResources resources)
'@ @'
        private string GetResourceLayoutKey(
            TranslatedDrawResources resources) =>
            resources.ResourceLayoutKey ??=
                GetCanonicalResourceLayoutKeyV120(resources);

        private static string GetVertexLayoutKey(
            TranslatedDrawResources resources)
        {
            if (resources.VertexLayoutKey is { } cachedV120)
            {
                return cachedV120;
            }

            if (resources.VertexBuffers.Length == 0)
            {
                Interlocked.Increment(ref _v120ZeroVertexLayoutHits);
                return resources.VertexLayoutKey = string.Empty;
            }

            return resources.VertexLayoutKey =
                BuildVertexLayoutKey(resources);
        }

        private string GetCanonicalResourceLayoutKeyV120(
            TranslatedDrawResources resources)
        {
            ulong mask0V120 = 0;
            ulong mask1V120 = 0;
            ulong mask2V120 = 0;
            ulong mask3V120 = 0;
            for (var indexV120 = 0;
                 indexV120 < resources.Textures.Length;
                 indexV120++)
            {
                if (!resources.Textures[indexV120].IsStorage)
                {
                    continue;
                }

                var bitV120 = 1UL << (indexV120 & 63);
                switch (indexV120 >> 6)
                {
                    case 0:
                        mask0V120 |= bitV120;
                        break;
                    case 1:
                        mask1V120 |= bitV120;
                        break;
                    case 2:
                        mask2V120 |= bitV120;
                        break;
                    case 3:
                        mask3V120 |= bitV120;
                        break;
                    default:
                        return BuildResourceLayoutKey(resources);
                }
            }

            var shapeV120 = new ResourceLayoutShapeV120(
                resources.GlobalMemoryBuffers.Length,
                resources.Textures.Length,
                mask0V120,
                mask1V120,
                mask2V120,
                mask3V120);
            if (_resourceLayoutKeyCacheV120.TryGetValue(
                    shapeV120,
                    out var cachedV120))
            {
                Interlocked.Increment(
                    ref _v120ResourceLayoutCacheHits);
                return cachedV120;
            }

            var createdV120 =
                BuildResourceLayoutKey(resources);
            Interlocked.Increment(
                ref _v120ResourceLayoutCacheMisses);
            if (_resourceLayoutKeyCacheV120.Count < 1024)
            {
                _resourceLayoutKeyCacheV120[
                    shapeV120] = createdV120;
            }
            return createdV120;
        }

        private static string BuildResourceLayoutKey(TranslatedDrawResources resources)
'@ 'resource-layout-canonical'

# Replace graphics string.Join allocations with exact canonical value-key caches.
$text=Replace-OnceV120 $text @'
            var renderTargetLayoutV1180 =
                string.Join(',', renderTargetFormats.Select(format => (uint)format));
            var blendLayoutV1180 =
                string.Join(';', resources.Blends.Select(blend =>
                    $"{(blend.Enable ? 1 : 0)}:{blend.ColorSrcFactor}:{blend.ColorDstFactor}:" +
                    $"{blend.ColorFunc}:{blend.AlphaSrcFactor}:{blend.AlphaDstFactor}:" +
                    $"{blend.AlphaFunc}:{(blend.SeparateAlphaBlend ? 1 : 0)}:{blend.WriteMask}"));
            var vertexLayoutV1180 = GetVertexLayoutKey(resources);
'@ @'
            var renderTargetLayoutV1180 =
                GetCanonicalRenderTargetLayoutKeyV120(
                    renderTargetFormats);
            var blendLayoutV1180 =
                GetCanonicalBlendLayoutKeyV120(
                    resources.Blends);
            var vertexLayoutV1180 =
                GetVertexLayoutKey(resources);
'@ 'graphics-layout-canonical-calls'

# Insert all CPU-only helpers before GetShaderDigest.
$text=Replace-OnceV120 $text @'
        private string GetShaderDigest(byte[] spirv)
'@ @'
        private static GuestImageResource? FindFeedbackTargetV120(
            GuestImageResource? image,
            IReadOnlyList<GuestImageResource>? targets)
        {
            if (image is null || targets is null)
            {
                return null;
            }

            for (var indexV120 = 0;
                 indexV120 < targets.Count;
                 indexV120++)
            {
                Interlocked.Increment(
                    ref _v120FeedbackLinearProbes);
                if (ReferenceEquals(image, targets[indexV120]))
                {
                    return targets[indexV120];
                }
            }

            return null;
        }

        private GuestBufferAllocation? FindGuestBufferAllocationV120(
            ulong baseAddress,
            ulong endAddress)
        {
            var queryV120 = Interlocked.Increment(
                ref _v120GlobalAllocationLookups);
            var countV120 = _guestBufferAllocations.Count;
            var lowV120 = 0;
            var highV120 = countV120 - 1;
            var bestV120 = -1;
            var stepsV120 = 0;

            while (lowV120 <= highV120)
            {
                stepsV120++;
                var middleV120 =
                    lowV120 + ((highV120 - lowV120) >> 1);
                var candidateV120 =
                    _guestBufferAllocations[middleV120];
                if (candidateV120.BaseAddress <= baseAddress)
                {
                    bestV120 = middleV120;
                    lowV120 = middleV120 + 1;
                }
                else
                {
                    highV120 = middleV120 - 1;
                }
            }

            Interlocked.Add(
                ref _v120GlobalAllocationBinarySteps,
                stepsV120);
            Interlocked.Add(
                ref _v120GlobalAllocationLinearCandidatesAvoided,
                Math.Max(0, countV120 - stepsV120));

            if (bestV120 < 0)
            {
                TraceDrawHotpathV120(queryV120);
                return null;
            }

            var bestAllocationV120 =
                _guestBufferAllocations[bestV120];
            var coveredV120 =
                bestAllocationV120.BaseAddress <= baseAddress &&
                endAddress >= bestAllocationV120.BaseAddress &&
                endAddress - bestAllocationV120.BaseAddress <=
                    bestAllocationV120.Size;

            TraceDrawHotpathV120(queryV120);
            return coveredV120
                ? bestAllocationV120
                : null;
        }

        private string GetCanonicalRenderTargetLayoutKeyV120(
            IReadOnlyList<Format> formats)
        {
            if (formats.Count > 8)
            {
                return string.Join(
                    ',',
                    formats.Select(format => (uint)format));
            }

            var shapeV120 = new TargetFormatLayoutShapeV120(
                formats.Count,
                formats.Count > 0 ? formats[0] : default,
                formats.Count > 1 ? formats[1] : default,
                formats.Count > 2 ? formats[2] : default,
                formats.Count > 3 ? formats[3] : default,
                formats.Count > 4 ? formats[4] : default,
                formats.Count > 5 ? formats[5] : default,
                formats.Count > 6 ? formats[6] : default,
                formats.Count > 7 ? formats[7] : default);
            if (_targetFormatLayoutKeyCacheV120.TryGetValue(
                    shapeV120,
                    out var cachedV120))
            {
                Interlocked.Increment(
                    ref _v120TargetLayoutCacheHits);
                return cachedV120;
            }

            var createdV120 = string.Join(
                ',',
                formats.Select(format => (uint)format));
            Interlocked.Increment(
                ref _v120TargetLayoutCacheMisses);
            if (_targetFormatLayoutKeyCacheV120.Count < 256)
            {
                _targetFormatLayoutKeyCacheV120[
                    shapeV120] = createdV120;
            }
            return createdV120;
        }

        private string GetCanonicalBlendLayoutKeyV120(
            GuestBlendState[] blends)
        {
            if (blends.Length > 8)
            {
                return BuildBlendLayoutKeyV120(blends);
            }

            var shapeV120 = new BlendLayoutShapeV120(
                blends.Length,
                blends.Length > 0 ? blends[0] : default,
                blends.Length > 1 ? blends[1] : default,
                blends.Length > 2 ? blends[2] : default,
                blends.Length > 3 ? blends[3] : default,
                blends.Length > 4 ? blends[4] : default,
                blends.Length > 5 ? blends[5] : default,
                blends.Length > 6 ? blends[6] : default,
                blends.Length > 7 ? blends[7] : default);
            if (_blendLayoutKeyCacheV120.TryGetValue(
                    shapeV120,
                    out var cachedV120))
            {
                Interlocked.Increment(
                    ref _v120BlendLayoutCacheHits);
                return cachedV120;
            }

            var createdV120 =
                BuildBlendLayoutKeyV120(blends);
            Interlocked.Increment(
                ref _v120BlendLayoutCacheMisses);
            if (_blendLayoutKeyCacheV120.Count < 256)
            {
                _blendLayoutKeyCacheV120[
                    shapeV120] = createdV120;
            }
            return createdV120;
        }

        private static string BuildBlendLayoutKeyV120(
            IEnumerable<GuestBlendState> blends) =>
            string.Join(
                ';',
                blends.Select(blend =>
                    $"{(blend.Enable ? 1 : 0)}:" +
                    $"{blend.ColorSrcFactor}:{blend.ColorDstFactor}:" +
                    $"{blend.ColorFunc}:{blend.AlphaSrcFactor}:" +
                    $"{blend.AlphaDstFactor}:{blend.AlphaFunc}:" +
                    $"{(blend.SeparateAlphaBlend ? 1 : 0)}:" +
                    $"{blend.WriteMask}"));

        private static void TraceDrawHotpathV120(
            long ordinalV120 = 0)
        {
            var drawV120 = ordinalV120 != 0
                ? ordinalV120
                : Interlocked.Increment(
                    ref _v120DrawHotpathCount);
            if (drawV120 > 32 &&
                (drawV120 & (drawV120 - 1)) != 0)
            {
                return;
            }

            Console.Error.WriteLine(
                "[V74.0.120.0][DRAW_HOTPATH] " +
                $"ticks={drawV120} " +
                $"readonly_prepare={Volatile.Read(ref _v120ReadonlyPrepareFastReturns)} " +
                $"single_writable_prepare={Volatile.Read(ref _v120SingleWritablePrepareFastPaths)} " +
                $"global_lookups={Volatile.Read(ref _v120GlobalAllocationLookups)} " +
                $"global_binary_steps={Volatile.Read(ref _v120GlobalAllocationBinarySteps)} " +
                $"linear_candidates_avoided={Volatile.Read(ref _v120GlobalAllocationLinearCandidatesAvoided)} " +
                $"zero_vertex_noalloc={Volatile.Read(ref _v120ZeroVertexNoAlloc)} " +
                $"single_vertex_noalloc={Volatile.Read(ref _v120SingleVertexNoAlloc)} " +
                $"feedback_probes={Volatile.Read(ref _v120FeedbackLinearProbes)} " +
                $"resource_layout_hits={Volatile.Read(ref _v120ResourceLayoutCacheHits)} " +
                $"resource_layout_misses={Volatile.Read(ref _v120ResourceLayoutCacheMisses)} " +
                $"target_layout_hits={Volatile.Read(ref _v120TargetLayoutCacheHits)} " +
                $"target_layout_misses={Volatile.Read(ref _v120TargetLayoutCacheMisses)} " +
                $"blend_layout_hits={Volatile.Read(ref _v120BlendLayoutCacheHits)} " +
                $"blend_layout_misses={Volatile.Read(ref _v120BlendLayoutCacheMisses)} " +
                $"zero_vertex_layout={Volatile.Read(ref _v120ZeroVertexLayoutHits)}");
        }

        private string GetShaderDigest(byte[] spirv)
'@ 'draw-hotpath-helpers'

Write-Utf8NoBomV120 $Output $text
Write-Host '[V74.0.120.0-PATCH] patch_ready=1 cpu_only=1 global_lookup=binary prepare_readonly_noalloc=1 vertex_zero_one_noalloc=1 feedback_linq=0 structural_layout_cache=1 image_change=0 buffer_content_change=0 queue_change=0 submit_change=0 barrier_change=0'
