param(
 [Parameter(Mandatory=$true)][string]$PresenterSource,
 [Parameter(Mandatory=$true)][string]$EnvelopeSource,
 [Parameter(Mandatory=$true)][string]$OutputPresenter,
 [Parameter(Mandatory=$true)][string]$OutputEnvelope
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Write-Utf8NoBomV11811([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Normalize-NewlinesV11811([string]$Text){
    if($null-eq$Text){return ''}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function Replace-OnceV11811(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Name)
{
    $usesCrlf=$Text.Contains("`r`n")
    $t=Normalize-NewlinesV11811 $Text
    $o=Normalize-NewlinesV11811 $Old
    $n=Normalize-NewlinesV11811 $New
    $count=([regex]::Matches($t,[regex]::Escape($o))).Count
    if($count-ne1){
        $first=($o -split "`n"|Select-Object -First 1).Trim()
        $hits=if([string]::IsNullOrEmpty($first)){0}else{
            ([regex]::Matches($t,[regex]::Escape($first))).Count
        }
        throw "[V118.1.1-PATCH] anchor $Name count=$count expected=1 first_line_hits=$hits"
    }
    $result=$t.Replace($o,$n)
    if($usesCrlf){$result=$result.Replace("`n","`r`n")}
    return $result
}

$p=[IO.File]::ReadAllText($PresenterSource)
$q=[IO.File]::ReadAllText($EnvelopeSource)

$requiredV1181=@(
    'SHARPEMU_V74_0_118_1_ALLOCATION_FREE_GRAPHICS_FASTPATH',
    'ResidentGraphicsExecutionKeyV1181',
    'ResidentGraphicsExecutionEntryV1181',
    'TryGetResidentGraphicsPipelineV1181',
    'RememberResidentGraphicsPipelineV1181',
    'SourceReferenceV1181'
)
$presentV1181=@($requiredV1181|Where-Object{$p.Contains($_)}).Count
$envelopeV1181=
    $q.Contains('SHARPEMU_V74_0_118_1_GPU_RESIDENT_FASTPATH_ENVELOPE') -and
    $q.Contains('SHARPEMU_GPU_RESIDENT_GRAPHICS_FASTPATH_V1181')

if($presentV1181-eq$requiredV1181.Count -and $envelopeV1181){
    Write-Utf8NoBomV11811 $OutputPresenter $p
    Write-Utf8NoBomV11811 $OutputEnvelope $q
    Write-Host '[V118.1.1-PATCH] already_applied=1 full_v1181_markers=1'
    exit 0
}

if($presentV1181-ne0 -or $envelopeV1181){
    throw "[V118.1.1-PATCH] partial V118.1 installation detected presenter=$presentV1181/$($requiredV1181.Count) envelope=$envelopeV1181"
}

if(-not$p.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){
    throw '[V118.1.1-PATCH] V118.0.1 GPU-resident baseline missing'
}
if(-not$p.Contains('SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE')){
    throw '[V118.1.1-PATCH] V117.16 descriptor cache baseline missing'
}
if($p.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
    throw '[V118.1.1-PATCH] forbidden V117.15 texture alias still installed'
}

$p=Replace-OnceV11811 $p @'
        private readonly Dictionary<ComputePipelineKey, Pipeline> _computePipelines = new();
        private readonly Dictionary<GraphicsPipelineKey, Pipeline> _graphicsPipelines = new();

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
        // A guest shader address becomes a stable ShaderId only after exact SPIR-V
        // content validation. Shader modules stay immutable/resident until
        // DeviceWaitIdle shutdown. No GPU resource or command ordering changes.
        private static readonly bool _gpuResidentShaderV1180 =
            !string.Equals(Environment.GetEnvironmentVariable(
                "SHARPEMU_GPU_RESIDENT_SHADER_V1180"),"0",StringComparison.Ordinal);
        private static readonly int _gpuResidentShaderMaxV1180 =
            Math.Clamp(int.TryParse(Environment.GetEnvironmentVariable(
                "SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180"),out var maxV1180)
                ? maxV1180 : 4096,64,16384);
        private readonly Dictionary<ResidentShaderDigestKeyV1180,ResidentShaderProgramV1180>
            _residentShadersByDigestV1180 = [];
        private readonly Dictionary<(ShaderStageFlags Stage, ulong Address),ResidentShaderProgramV1180>
            _residentShadersByAddressV1180 = [];
        private readonly Dictionary<ResidentComputeExecutionKeyV1180,Pipeline>
            _residentComputeExecutionV1180 = [];
        private readonly Dictionary<ResidentGraphicsExecutionKeyV1180,Pipeline>
            _residentGraphicsExecutionV1180 = [];
        private int _nextResidentShaderIdV1180 = 1;
        private static long _v1180ShaderLookups;
        private static long _v1180AddressExactHits;
        private static long _v1180ContentChanges;
        private static long _v1180DigestHits;
        private static long _v1180Registrations;
        private static long _v1180Fallbacks;
        private static long _v1180ComputePipelineFastHits;
        private static long _v1180GraphicsPipelineFastHits;
        private static long _v1180ModuleReuseSavings;

        private readonly Dictionary<GuestSampler, Sampler> _samplers = new();
'@ @'
        private readonly Dictionary<ComputePipelineKey, Pipeline> _computePipelines = new();
        private readonly Dictionary<GraphicsPipelineKey, Pipeline> _graphicsPipelines = new();

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
        // A guest shader address becomes a stable ShaderId only after exact SPIR-V
        // content validation. Shader modules stay immutable/resident until
        // DeviceWaitIdle shutdown. No GPU resource or command ordering changes.
        private static readonly bool _gpuResidentShaderV1180 =
            !string.Equals(Environment.GetEnvironmentVariable(
                "SHARPEMU_GPU_RESIDENT_SHADER_V1180"),"0",StringComparison.Ordinal);
        private static readonly int _gpuResidentShaderMaxV1180 =
            Math.Clamp(int.TryParse(Environment.GetEnvironmentVariable(
                "SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180"),out var maxV1180)
                ? maxV1180 : 4096,64,16384);
        private readonly Dictionary<ResidentShaderDigestKeyV1180,ResidentShaderProgramV1180>
            _residentShadersByDigestV1180 = [];
        private readonly Dictionary<(ShaderStageFlags Stage, ulong Address),ResidentShaderProgramV1180>
            _residentShadersByAddressV1180 = [];
        private readonly Dictionary<ResidentComputeExecutionKeyV1180,Pipeline>
            _residentComputeExecutionV1180 = [];

        // SHARPEMU_V74_0_118_1_ALLOCATION_FREE_GRAPHICS_FASTPATH
        // V118.0 still built RenderTarget/Blend/VertexLayout strings before its
        // graphics fast lookup. V118.1 hashes those already-decoded fields with
        // no allocation, then exact-compares the bucket before using a pipeline.
        // Hash collision can therefore never select the wrong pipeline.
        private static readonly bool _gpuResidentGraphicsFastPathV1181 =
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_GPU_RESIDENT_GRAPHICS_FASTPATH_V1181"),
                "0",
                StringComparison.Ordinal);
        private readonly Dictionary<
            ResidentGraphicsExecutionKeyV1181,
            List<ResidentGraphicsExecutionEntryV1181>>
            _residentGraphicsExecutionV1181 = [];

        private int _nextResidentShaderIdV1180 = 1;
        private static long _v1180ShaderLookups;
        private static long _v1180AddressExactHits;
        private static long _v1180ContentChanges;
        private static long _v1180DigestHits;
        private static long _v1180Registrations;
        private static long _v1180Fallbacks;
        private static long _v1180ComputePipelineFastHits;
        private static long _v1180GraphicsPipelineFastHits;
        private static long _v1180ModuleReuseSavings;

        private static long _v1181ShaderReferenceHits;
        private static long _v1181ShaderExactCompareHits;
        private static long _v1181ShaderCompareBytesSaved;
        private static long _v1181GraphicsFastLookups;
        private static long _v1181GraphicsFastHits;
        private static long _v1181GraphicsBucketChecks;
        private static long _v1181GraphicsHashCollisions;
        private static long _v1181GraphicsStringBuildsAvoided;

        private readonly Dictionary<GuestSampler, Sampler> _samplers = new();
'@ 'resident-fields-incremental'

$p=Replace-OnceV11811 $p @'
        private readonly record struct ComputePipelineKey(
            string ShaderDigest,
            string Resources);

        private readonly record struct ResidentShaderDigestKeyV1180(
            ShaderStageFlags Stage,
            string Digest);

        private sealed class ResidentShaderProgramV1180
        {
            public required int ShaderId;
            public required ShaderStageFlags Stage;
            public required string Digest;
            public required byte[] SpirvSnapshot;
            public required ShaderModule Module;
            public ulong GuestAddress;
            public int PipelineVariantUses;
        }

        private readonly record struct ResidentComputeExecutionKeyV1180(
            int ShaderId,
            ulong PipelineLayout);

        private readonly record struct ResidentGraphicsExecutionKeyV1180(
            int VertexShaderId,
            int FragmentShaderId,
            ulong PipelineLayout,
            string RenderTargetLayout,
            bool HasDepthAttachment,
            PrimitiveTopology Topology,
            string BlendLayout,
            string VertexLayout,
            GuestRasterState Raster,
            GuestDepthState Depth);

        private sealed record StorageContractCacheV74099(
            bool Success,
            SpirvStorageImageContract[] Contracts,
            string Error);

        private sealed record DescriptorLayoutBundle(
'@ @'
        private readonly record struct ComputePipelineKey(
            string ShaderDigest,
            string Resources);

        private readonly record struct ResidentShaderDigestKeyV1180(
            ShaderStageFlags Stage,
            string Digest);

        private sealed class ResidentShaderProgramV1180
        {
            public required int ShaderId;
            public required ShaderStageFlags Stage;
            public required string Digest;
            public required byte[] SpirvSnapshot;
            // Same immutable-array contract already used by _shaderDigests.
            // Reference equality is a zero-scan hot path; a different array
            // still receives exact SequenceEqual validation below.
            public required byte[] SourceReferenceV1181;
            public required ShaderModule Module;
            public ulong GuestAddress;
            public int PipelineVariantUses;
        }

        private readonly record struct ResidentComputeExecutionKeyV1180(
            int ShaderId,
            ulong PipelineLayout);

        private readonly record struct ResidentGraphicsExecutionKeyV1181(
            int VertexShaderId,
            int FragmentShaderId,
            ulong PipelineLayout,
            ulong ArraySignature,
            bool HasDepthAttachment,
            PrimitiveTopology Topology,
            GuestRasterState Raster,
            GuestDepthState Depth);

        private readonly record struct ResidentVertexLayoutElementV1181(
            uint Location,
            uint ComponentCount,
            uint DataFormat,
            uint NumberFormat,
            uint EffectiveStride);

        private sealed class ResidentGraphicsExecutionEntryV1181
        {
            public required Pipeline Pipeline;
            public required Format[] RenderTargetFormats;
            public required GuestBlendState[] Blends;
            public required ResidentVertexLayoutElementV1181[] VertexLayout;
        }

        private sealed record StorageContractCacheV74099(
            bool Success,
            SpirvStorageImageContract[] Contracts,
            string Error);

        private sealed record DescriptorLayoutBundle(
'@ 'resident-types-incremental'

$p=Replace-OnceV11811 $p @'
        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
        private bool TryGetResidentShaderProgramV1180(
            byte[] spirv,
            ShaderStageFlags stage,
            ulong guestAddress,
            out ResidentShaderProgramV1180 program)
        {
            program = null!;
            if (!_gpuResidentShaderV1180 || spirv.Length == 0)
            {
                return false;
            }

            var lookup = Interlocked.Increment(ref _v1180ShaderLookups);
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

            // Existing reference cache avoids SHA256 when the translator reused
            // the same immutable byte[]; otherwise SHA is paid once on registration.
            var digest = GetShaderDigest(spirv);
            var digestKey = new ResidentShaderDigestKeyV1180(stage, digest);
            if (_residentShadersByDigestV1180.TryGetValue(
                    digestKey, out var byDigestV1180))
            {
                // SHA256 is not used as a correctness shortcut: exact bytes must
                // still match before associating a different guest address.
                if (byDigestV1180.SpirvSnapshot.Length == spirv.Length &&
                    byDigestV1180.SpirvSnapshot.AsSpan().SequenceEqual(spirv))
                {
                    program = byDigestV1180;
                    if (guestAddress != 0)
                    {
                        _residentShadersByAddressV1180[(stage, guestAddress)] = program;
                    }
                    Interlocked.Increment(ref _v1180DigestHits);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                Interlocked.Increment(ref _v1180Fallbacks);
                return false;
            }

            if (_residentShadersByDigestV1180.Count >= _gpuResidentShaderMaxV1180)
            {
                Interlocked.Increment(ref _v1180Fallbacks);
                return false;
            }

            var module = CreateShaderModule(spirv);
            program = new ResidentShaderProgramV1180
            {
                ShaderId = _nextResidentShaderIdV1180++,
                Stage = stage,
                Digest = digest,
                SpirvSnapshot = spirv.ToArray(),
                Module = module,
                GuestAddress = guestAddress,
            };
            _residentShadersByDigestV1180.Add(digestKey, program);
            if (guestAddress != 0)
            {
                _residentShadersByAddressV1180[(stage, guestAddress)] = program;
            }
            Interlocked.Increment(ref _v1180Registrations);
            TraceResidentShaderV1180(lookup);
            return true;
        }

        private void TraceResidentShaderV1180(long lookup)
        {
            if (lookup > 32 && (lookup & (lookup - 1)) != 0)
            {
                return;
            }

            Console.Error.WriteLine(
                $"[V74.0.118.0][RESIDENT_SHADER] lookups={lookup} " +
                $"address_hits={Volatile.Read(ref _v1180AddressExactHits)} " +
                $"content_changes={Volatile.Read(ref _v1180ContentChanges)} " +
                $"digest_hits={Volatile.Read(ref _v1180DigestHits)} " +
                $"registered={Volatile.Read(ref _v1180Registrations)} " +
                $"resident={_residentShadersByDigestV1180.Count} " +
                $"compute_pipeline_fast_hits={Volatile.Read(ref _v1180ComputePipelineFastHits)} " +
                $"graphics_pipeline_fast_hits={Volatile.Read(ref _v1180GraphicsPipelineFastHits)} " +
                $"module_create_saved={Volatile.Read(ref _v1180ModuleReuseSavings)} " +
                $"fallbacks={Volatile.Read(ref _v1180Fallbacks)}");
        }

        private string GetShaderDigest(byte[] spirv)
        {
'@ @'
        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
        private bool TryGetResidentShaderProgramV1180(
            byte[] spirv,
            ShaderStageFlags stage,
            ulong guestAddress,
            out ResidentShaderProgramV1180 program)
        {
            program = null!;
            if (!_gpuResidentShaderV1180 || spirv.Length == 0)
            {
                return false;
            }

            var lookup = Interlocked.Increment(ref _v1180ShaderLookups);
            if (guestAddress != 0 &&
                _residentShadersByAddressV1180.TryGetValue(
                    (stage, guestAddress), out var byAddressV1180))
            {
                // SHARPEMU_V74_0_118_1_SHADER_REFERENCE_FASTPATH
                // _shaderDigests already treats a byte[] instance as immutable.
                // Reuse that existing contract and avoid rescanning SPIR-V when
                // the exact translated array instance returns.
                if (ReferenceEquals(
                        byAddressV1180.SourceReferenceV1181,
                        spirv))
                {
                    program = byAddressV1180;
                    Interlocked.Increment(ref _v1180AddressExactHits);
                    Interlocked.Increment(ref _v1181ShaderReferenceHits);
                    Interlocked.Add(
                        ref _v1181ShaderCompareBytesSaved,
                        spirv.LongLength);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                if (byAddressV1180.SpirvSnapshot.Length == spirv.Length &&
                    byAddressV1180.SpirvSnapshot.AsSpan().SequenceEqual(spirv))
                {
                    program = byAddressV1180;
                    byAddressV1180.SourceReferenceV1181 = spirv;
                    Interlocked.Increment(ref _v1180AddressExactHits);
                    Interlocked.Increment(ref _v1181ShaderExactCompareHits);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                Interlocked.Increment(ref _v1180ContentChanges);
            }

            // Existing reference cache avoids SHA256 when the translator reused
            // the same immutable byte[]; otherwise SHA is paid once on registration.
            var digest = GetShaderDigest(spirv);
            var digestKey = new ResidentShaderDigestKeyV1180(stage, digest);
            if (_residentShadersByDigestV1180.TryGetValue(
                    digestKey, out var byDigestV1180))
            {
                if (ReferenceEquals(
                        byDigestV1180.SourceReferenceV1181,
                        spirv))
                {
                    program = byDigestV1180;
                    if (guestAddress != 0)
                    {
                        _residentShadersByAddressV1180[(stage, guestAddress)] =
                            program;
                    }
                    Interlocked.Increment(ref _v1180DigestHits);
                    Interlocked.Increment(ref _v1181ShaderReferenceHits);
                    Interlocked.Add(
                        ref _v1181ShaderCompareBytesSaved,
                        spirv.LongLength);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                // Different array/reference: retain V118.0's exact byte guard.
                if (byDigestV1180.SpirvSnapshot.Length == spirv.Length &&
                    byDigestV1180.SpirvSnapshot.AsSpan().SequenceEqual(spirv))
                {
                    program = byDigestV1180;
                    byDigestV1180.SourceReferenceV1181 = spirv;
                    if (guestAddress != 0)
                    {
                        _residentShadersByAddressV1180[(stage, guestAddress)] =
                            program;
                    }
                    Interlocked.Increment(ref _v1180DigestHits);
                    Interlocked.Increment(ref _v1181ShaderExactCompareHits);
                    TraceResidentShaderV1180(lookup);
                    return true;
                }

                Interlocked.Increment(ref _v1180Fallbacks);
                return false;
            }

            if (_residentShadersByDigestV1180.Count >= _gpuResidentShaderMaxV1180)
            {
                Interlocked.Increment(ref _v1180Fallbacks);
                return false;
            }

            var module = CreateShaderModule(spirv);
            program = new ResidentShaderProgramV1180
            {
                ShaderId = _nextResidentShaderIdV1180++,
                Stage = stage,
                Digest = digest,
                SpirvSnapshot = spirv.ToArray(),
                SourceReferenceV1181 = spirv,
                Module = module,
                GuestAddress = guestAddress,
            };
            _residentShadersByDigestV1180.Add(digestKey, program);
            if (guestAddress != 0)
            {
                _residentShadersByAddressV1180[(stage, guestAddress)] = program;
            }
            Interlocked.Increment(ref _v1180Registrations);
            TraceResidentShaderV1180(lookup);
            return true;
        }

        private void TraceResidentShaderV1180(long lookup)
        {
            if (lookup > 32 && (lookup & (lookup - 1)) != 0)
            {
                return;
            }

            Console.Error.WriteLine(
                $"[V74.0.118.0][RESIDENT_SHADER] lookups={lookup} " +
                $"address_hits={Volatile.Read(ref _v1180AddressExactHits)} " +
                $"content_changes={Volatile.Read(ref _v1180ContentChanges)} " +
                $"digest_hits={Volatile.Read(ref _v1180DigestHits)} " +
                $"registered={Volatile.Read(ref _v1180Registrations)} " +
                $"resident={_residentShadersByDigestV1180.Count} " +
                $"compute_pipeline_fast_hits={Volatile.Read(ref _v1180ComputePipelineFastHits)} " +
                $"graphics_pipeline_fast_hits={Volatile.Read(ref _v1180GraphicsPipelineFastHits)} " +
                $"module_create_saved={Volatile.Read(ref _v1180ModuleReuseSavings)} " +
                $"reference_hits={Volatile.Read(ref _v1181ShaderReferenceHits)} " +
                $"exact_compare_hits={Volatile.Read(ref _v1181ShaderExactCompareHits)} " +
                $"compare_mb_saved={Volatile.Read(ref _v1181ShaderCompareBytesSaved) / (1024.0 * 1024.0):F2} " +
                $"graphics_allocfree_hits={Volatile.Read(ref _v1181GraphicsFastHits)} " +
                $"graphics_string_builds_avoided={Volatile.Read(ref _v1181GraphicsStringBuildsAvoided)} " +
                $"fallbacks={Volatile.Read(ref _v1180Fallbacks)}");
        }

        // SHARPEMU_V74_0_118_1_ALLOCATION_FREE_GRAPHICS_FASTPATH
        private static ulong MixResidentGraphicsSignatureV1181(
            ulong hash,
            ulong value)
        {
            unchecked
            {
                return (hash ^ value) * 1099511628211UL;
            }
        }

        private static ulong BuildResidentGraphicsArraySignatureV1181(
            TranslatedDrawResources resources,
            IReadOnlyList<Format> renderTargetFormats)
        {
            var hash = 1469598103934665603UL;

            hash = MixResidentGraphicsSignatureV1181(
                hash,
                (ulong)renderTargetFormats.Count);
            for (var index = 0; index < renderTargetFormats.Count; index++)
            {
                hash = MixResidentGraphicsSignatureV1181(
                    hash,
                    (uint)renderTargetFormats[index]);
            }

            hash = MixResidentGraphicsSignatureV1181(
                hash,
                (ulong)resources.Blends.Length);
            foreach (var blend in resources.Blends)
            {
                hash = MixResidentGraphicsSignatureV1181(hash, blend.Enable ? 1UL : 0UL);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.ColorSrcFactor);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.ColorDstFactor);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.ColorFunc);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.AlphaSrcFactor);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.AlphaDstFactor);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.AlphaFunc);
                hash = MixResidentGraphicsSignatureV1181(
                    hash,
                    blend.SeparateAlphaBlend ? 1UL : 0UL);
                hash = MixResidentGraphicsSignatureV1181(hash, blend.WriteMask);
            }

            hash = MixResidentGraphicsSignatureV1181(
                hash,
                (ulong)resources.VertexBuffers.Length);
            foreach (var buffer in resources.VertexBuffers)
            {
                var effectiveStride =
                    buffer.Stride == 0
                        ? Math.Max(buffer.ComponentCount, 1u) *
                          (uint)sizeof(float)
                        : buffer.Stride;
                hash = MixResidentGraphicsSignatureV1181(hash, buffer.Location);
                hash = MixResidentGraphicsSignatureV1181(hash, buffer.ComponentCount);
                hash = MixResidentGraphicsSignatureV1181(hash, buffer.DataFormat);
                hash = MixResidentGraphicsSignatureV1181(hash, buffer.NumberFormat);
                hash = MixResidentGraphicsSignatureV1181(hash, effectiveStride);
            }

            return hash;
        }

        private static bool ResidentGraphicsStateMatchesV1181(
            ResidentGraphicsExecutionEntryV1181 entry,
            TranslatedDrawResources resources,
            IReadOnlyList<Format> renderTargetFormats)
        {
            if (entry.RenderTargetFormats.Length != renderTargetFormats.Count ||
                entry.Blends.Length != resources.Blends.Length ||
                entry.VertexLayout.Length != resources.VertexBuffers.Length)
            {
                return false;
            }

            for (var index = 0; index < entry.RenderTargetFormats.Length; index++)
            {
                if (entry.RenderTargetFormats[index] != renderTargetFormats[index])
                {
                    return false;
                }
            }

            for (var index = 0; index < entry.Blends.Length; index++)
            {
                if (entry.Blends[index] != resources.Blends[index])
                {
                    return false;
                }
            }

            for (var index = 0; index < entry.VertexLayout.Length; index++)
            {
                var buffer = resources.VertexBuffers[index];
                var effectiveStride =
                    buffer.Stride == 0
                        ? Math.Max(buffer.ComponentCount, 1u) *
                          (uint)sizeof(float)
                        : buffer.Stride;
                var current = new ResidentVertexLayoutElementV1181(
                    buffer.Location,
                    buffer.ComponentCount,
                    buffer.DataFormat,
                    buffer.NumberFormat,
                    effectiveStride);
                if (entry.VertexLayout[index] != current)
                {
                    return false;
                }
            }

            return true;
        }

        private bool TryGetResidentGraphicsPipelineV1181(
            ResidentGraphicsExecutionKeyV1181 key,
            TranslatedDrawResources resources,
            IReadOnlyList<Format> renderTargetFormats,
            out Pipeline pipeline)
        {
            pipeline = default;
            if (!_gpuResidentGraphicsFastPathV1181)
            {
                return false;
            }

            Interlocked.Increment(ref _v1181GraphicsFastLookups);
            if (!_residentGraphicsExecutionV1181.TryGetValue(key, out var bucket))
            {
                return false;
            }

            foreach (var entry in bucket)
            {
                Interlocked.Increment(ref _v1181GraphicsBucketChecks);
                if (!ResidentGraphicsStateMatchesV1181(
                        entry,
                        resources,
                        renderTargetFormats))
                {
                    Interlocked.Increment(ref _v1181GraphicsHashCollisions);
                    continue;
                }

                pipeline = entry.Pipeline;
                Interlocked.Increment(ref _v1180GraphicsPipelineFastHits);
                Interlocked.Increment(ref _v1181GraphicsFastHits);
                Interlocked.Add(ref _v1181GraphicsStringBuildsAvoided, 3);
                return true;
            }

            return false;
        }

        private void RememberResidentGraphicsPipelineV1181(
            ResidentGraphicsExecutionKeyV1181 key,
            TranslatedDrawResources resources,
            IReadOnlyList<Format> renderTargetFormats,
            Pipeline pipeline)
        {
            if (!_gpuResidentGraphicsFastPathV1181 || pipeline.Handle == 0)
            {
                return;
            }

            if (!_residentGraphicsExecutionV1181.TryGetValue(key, out var bucket))
            {
                bucket = [];
                _residentGraphicsExecutionV1181.Add(key, bucket);
            }
            else
            {
                foreach (var existing in bucket)
                {
                    if (ResidentGraphicsStateMatchesV1181(
                            existing,
                            resources,
                            renderTargetFormats))
                    {
                        return;
                    }
                }
            }

            var vertexLayout = new ResidentVertexLayoutElementV1181[
                resources.VertexBuffers.Length];
            for (var index = 0; index < vertexLayout.Length; index++)
            {
                var buffer = resources.VertexBuffers[index];
                var effectiveStride =
                    buffer.Stride == 0
                        ? Math.Max(buffer.ComponentCount, 1u) *
                          (uint)sizeof(float)
                        : buffer.Stride;
                vertexLayout[index] = new ResidentVertexLayoutElementV1181(
                    buffer.Location,
                    buffer.ComponentCount,
                    buffer.DataFormat,
                    buffer.NumberFormat,
                    effectiveStride);
            }

            bucket.Add(
                new ResidentGraphicsExecutionEntryV1181
                {
                    Pipeline = pipeline,
                    RenderTargetFormats = renderTargetFormats.ToArray(),
                    Blends = resources.Blends.ToArray(),
                    VertexLayout = vertexLayout,
                });
        }

        private string GetShaderDigest(byte[] spirv)
        {
'@ 'resident-helper-incremental'

$p=Replace-OnceV11811 $p @'
            IReadOnlyList<Format> renderTargetFormats,
            Extent2D extent,
            ulong shaderAddress)
        {
            var hasResidentVertexV1180 = TryGetResidentShaderProgramV1180(
                vertexSpirv, ShaderStageFlags.VertexBit, 0, out var residentVertexV1180);
            var hasResidentFragmentV1180 = TryGetResidentShaderProgramV1180(
                fragmentSpirv, ShaderStageFlags.FragmentBit, shaderAddress, out var residentFragmentV1180);

            var renderTargetLayoutV1180 =
                string.Join(',', renderTargetFormats.Select(format => (uint)format));
            var blendLayoutV1180 =
                string.Join(';', resources.Blends.Select(blend =>
                    $"{(blend.Enable ? 1 : 0)}:{blend.ColorSrcFactor}:{blend.ColorDstFactor}:" +
                    $"{blend.ColorFunc}:{blend.AlphaSrcFactor}:{blend.AlphaDstFactor}:" +
                    $"{blend.AlphaFunc}:{(blend.SeparateAlphaBlend ? 1 : 0)}:{blend.WriteMask}"));
            var vertexLayoutV1180 = GetVertexLayoutKey(resources);

            ResidentGraphicsExecutionKeyV1180? fastKeyV1180 = null;
            if (hasResidentVertexV1180 &&
                hasResidentFragmentV1180 &&
                resources.PipelineLayout.Handle != 0)
            {
                fastKeyV1180 = new ResidentGraphicsExecutionKeyV1180(
                    residentVertexV1180.ShaderId,
                    residentFragmentV1180.ShaderId,
                    resources.PipelineLayout.Handle,
                    renderTargetLayoutV1180,
                    resources.HasDepthAttachment,
                    resources.Topology,
                    blendLayoutV1180,
                    vertexLayoutV1180,
                    resources.Raster,
                    resources.HasDepthAttachment ? resources.Depth : GuestDepthState.Default);

                if (_residentGraphicsExecutionV1180.TryGetValue(
                        fastKeyV1180.Value, out var residentPipelineV1180))
                {
                    resources.Pipeline = residentPipelineV1180;
                    resources.PipelineCached = true;
                    Interlocked.Increment(ref _v1180GraphicsPipelineFastHits);
                    return;
                }
            }

            var pipelineKey = new GraphicsPipelineKey(
                hasResidentVertexV1180 ? residentVertexV1180.Digest : GetShaderDigest(vertexSpirv),
                hasResidentFragmentV1180 ? residentFragmentV1180.Digest : GetShaderDigest(fragmentSpirv),
                renderTargetLayoutV1180,
                resources.HasDepthAttachment,
                resources.Topology,
                blendLayoutV1180,
                GetResourceLayoutKey(resources),
                vertexLayoutV1180,
                resources.Raster,
                resources.HasDepthAttachment ? resources.Depth : GuestDepthState.Default);
            if (_graphicsPipelines.TryGetValue(pipelineKey, out var cachedPipeline))
            {
                resources.Pipeline = cachedPipeline;
                resources.PipelineCached = true;
                if (fastKeyV1180 is { } fkV1180)
                {
                    _residentGraphicsExecutionV1180[fkV1180] = cachedPipeline;
                }
                return;
            }

            var pipelineCreateStartV74030 = _traceShaderPipelineTimingV74030
                ? Stopwatch.GetTimestamp()
                : 0L;
            var vertexModule = hasResidentVertexV1180
                ? residentVertexV1180.Module
                : CreateShaderModule(vertexSpirv);
            var fragmentModule = hasResidentFragmentV1180
                ? residentFragmentV1180.Module
                : CreateShaderModule(fragmentSpirv);
            if (hasResidentVertexV1180 && ++residentVertexV1180.PipelineVariantUses > 1)
            {
                Interlocked.Increment(ref _v1180ModuleReuseSavings);
            }
            if (hasResidentFragmentV1180 && ++residentFragmentV1180.PipelineVariantUses > 1)
            {
                Interlocked.Increment(ref _v1180ModuleReuseSavings);
            }
            var entryPoint = (byte*)SilkMarshal.StringToPtr("main");
'@ @'
            IReadOnlyList<Format> renderTargetFormats,
            Extent2D extent,
            ulong shaderAddress)
        {
            var hasResidentVertexV1180 = TryGetResidentShaderProgramV1180(
                vertexSpirv, ShaderStageFlags.VertexBit, 0, out var residentVertexV1180);
            var hasResidentFragmentV1180 = TryGetResidentShaderProgramV1180(
                fragmentSpirv, ShaderStageFlags.FragmentBit, shaderAddress, out var residentFragmentV1180);

            ResidentGraphicsExecutionKeyV1181? fastKeyV1181 = null;
            if (hasResidentVertexV1180 &&
                hasResidentFragmentV1180 &&
                resources.PipelineLayout.Handle != 0)
            {
                fastKeyV1181 = new ResidentGraphicsExecutionKeyV1181(
                    residentVertexV1180.ShaderId,
                    residentFragmentV1180.ShaderId,
                    resources.PipelineLayout.Handle,
                    BuildResidentGraphicsArraySignatureV1181(
                        resources,
                        renderTargetFormats),
                    resources.HasDepthAttachment,
                    resources.Topology,
                    resources.Raster,
                    resources.HasDepthAttachment
                        ? resources.Depth
                        : GuestDepthState.Default);

                if (TryGetResidentGraphicsPipelineV1181(
                        fastKeyV1181.Value,
                        resources,
                        renderTargetFormats,
                        out var residentPipelineV1181))
                {
                    resources.Pipeline = residentPipelineV1181;
                    resources.PipelineCached = true;
                    return;
                }
            }

            // Canonical cold/miss path is preserved.
            var renderTargetLayoutV1180 =
                string.Join(',', renderTargetFormats.Select(format => (uint)format));
            var blendLayoutV1180 =
                string.Join(';', resources.Blends.Select(blend =>
                    $"{(blend.Enable ? 1 : 0)}:{blend.ColorSrcFactor}:{blend.ColorDstFactor}:" +
                    $"{blend.ColorFunc}:{blend.AlphaSrcFactor}:{blend.AlphaDstFactor}:" +
                    $"{blend.AlphaFunc}:{(blend.SeparateAlphaBlend ? 1 : 0)}:{blend.WriteMask}"));
            var vertexLayoutV1180 = GetVertexLayoutKey(resources);

            var pipelineKey = new GraphicsPipelineKey(
                hasResidentVertexV1180 ? residentVertexV1180.Digest : GetShaderDigest(vertexSpirv),
                hasResidentFragmentV1180 ? residentFragmentV1180.Digest : GetShaderDigest(fragmentSpirv),
                renderTargetLayoutV1180,
                resources.HasDepthAttachment,
                resources.Topology,
                blendLayoutV1180,
                GetResourceLayoutKey(resources),
                vertexLayoutV1180,
                resources.Raster,
                resources.HasDepthAttachment ? resources.Depth : GuestDepthState.Default);
            if (_graphicsPipelines.TryGetValue(pipelineKey, out var cachedPipeline))
            {
                resources.Pipeline = cachedPipeline;
                resources.PipelineCached = true;
                if (fastKeyV1181 is { } fkV1181)
                {
                    RememberResidentGraphicsPipelineV1181(
                        fkV1181,
                        resources,
                        renderTargetFormats,
                        cachedPipeline);
                }
                return;
            }

            var pipelineCreateStartV74030 = _traceShaderPipelineTimingV74030
                ? Stopwatch.GetTimestamp()
                : 0L;
            var vertexModule = hasResidentVertexV1180
                ? residentVertexV1180.Module
                : CreateShaderModule(vertexSpirv);
            var fragmentModule = hasResidentFragmentV1180
                ? residentFragmentV1180.Module
                : CreateShaderModule(fragmentSpirv);
            if (hasResidentVertexV1180 && ++residentVertexV1180.PipelineVariantUses > 1)
            {
                Interlocked.Increment(ref _v1180ModuleReuseSavings);
            }
            if (hasResidentFragmentV1180 && ++residentFragmentV1180.PipelineVariantUses > 1)
            {
                Interlocked.Increment(ref _v1180ModuleReuseSavings);
            }
            var entryPoint = (byte*)SilkMarshal.StringToPtr("main");
'@ 'graphics-resident-fastpath-incremental'

$p=Replace-OnceV11811 $p @'
                        resources.PipelineCached = true;
                        _graphicsPipelines.Add(pipelineKey, pipeline);
                        if (fastKeyV1180 is { } fkV1180)
                        {
                            _residentGraphicsExecutionV1180[fkV1180] = pipeline;
                        }
'@ @'
                        resources.PipelineCached = true;
                        _graphicsPipelines.Add(pipelineKey, pipeline);
                        if (fastKeyV1181 is { } fkV1181)
                        {
                            RememberResidentGraphicsPipelineV1181(
                                fkV1181,
                                resources,
                                renderTargetFormats,
                                pipeline);
                        }
'@ 'graphics-fast-insert-incremental'

$p=Replace-OnceV11811 $p @'
            _graphicsPipelines.Clear();

            // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
            _residentComputeExecutionV1180.Clear();
            _residentGraphicsExecutionV1180.Clear();
            foreach (var shaderV1180 in _residentShadersByDigestV1180.Values)
            {
                if (shaderV1180.Module.Handle != 0)
                {
                    _vk.DestroyShaderModule(_device, shaderV1180.Module, null);
                }
            }
            _residentShadersByAddressV1180.Clear();
            _residentShadersByDigestV1180.Clear();

            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
'@ @'
            _graphicsPipelines.Clear();

            // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID
            _residentComputeExecutionV1180.Clear();
            _residentGraphicsExecutionV1181.Clear();
            foreach (var shaderV1180 in _residentShadersByDigestV1180.Values)
            {
                if (shaderV1180.Module.Handle != 0)
                {
                    _vk.DestroyShaderModule(_device, shaderV1180.Module, null);
                }
            }
            _residentShadersByAddressV1180.Clear();
            _residentShadersByDigestV1180.Clear();

            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
'@ 'resident-shutdown-incremental'

$q=Replace-OnceV11811 $q @'
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "512");

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");
'@ @'
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "512");

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");

        // SHARPEMU_V74_0_118_1_GPU_RESIDENT_FASTPATH_ENVELOPE
        Set("SHARPEMU_GPU_RESIDENT_GRAPHICS_FASTPATH_V1181", "1");
'@ 'resident-envelope-incremental'

Write-Utf8NoBomV11811 $OutputPresenter $p
Write-Utf8NoBomV11811 $OutputEnvelope $q
Write-Host '[V118.1.1-PATCH] patch_ready=1 incremental_from_v1180_1=1 v1181_transforms=7 allocation_free_graphics_fastpath=1 shader_reference_fastpath=1 descriptor_cache_preserved=1 image_change=0 buffer_change=0 queue_change=0 submit_change=0 barrier_change=0'
