param(
 [Parameter(Mandatory=$true)][string]$PresenterSource,
 [Parameter(Mandatory=$true)][string]$EnvelopeSource,
 [Parameter(Mandatory=$true)][string]$OutputPresenter,
 [Parameter(Mandatory=$true)][string]$OutputEnvelope
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Write-Utf8NoBomV1180([string]$Path,[string]$Text){
 $e=New-Object Text.UTF8Encoding($false)
 [IO.File]::WriteAllText($Path,$Text,$e)
}
function Normalize-NewlinesV1180([string]$Text){
 $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function Replace-OnceV1180([string]$Text,[string]$Old,[string]$New,[string]$Name){
 $usesCrlf=$Text.Contains("`r`n")
 $normalizedText=Normalize-NewlinesV1180 $Text
 $normalizedOld=Normalize-NewlinesV1180 $Old
 $normalizedNew=Normalize-NewlinesV1180 $New
 $count=([regex]::Matches($normalizedText,[regex]::Escape($normalizedOld))).Count
 if($count-ne1){throw "[V118.0.1-PATCH] anchor $Name count=$count expected=1"}
 $result=$normalizedText.Replace($normalizedOld,$normalizedNew)
 if($usesCrlf){$result=$result.Replace("`n","`r`n")}
 return $result
}
$p=[IO.File]::ReadAllText($PresenterSource)
$q=[IO.File]::ReadAllText($EnvelopeSource)
if($p.Contains('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID')){
 Write-Utf8NoBomV1180 $OutputPresenter $p;Write-Utf8NoBomV1180 $OutputEnvelope $q;Write-Host '[V118.0.1-PATCH] already_applied=1';exit 0
}
if(-not$p.Contains('SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE')){throw '[V118.0-PATCH] V117.16 base not installed in staging'}
if($p.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){throw '[V118.0-PATCH] V117.15 forbidden'}

$p=Replace-OnceV1180 $p @'
        private readonly Dictionary<ComputePipelineKey, Pipeline> _computePipelines = new();
        private readonly Dictionary<GraphicsPipelineKey, Pipeline> _graphicsPipelines = new();
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
'@ 'resident-fields'

$p=Replace-OnceV1180 $p @'
        private readonly record struct ComputePipelineKey(
            string ShaderDigest,
            string Resources);

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
'@ 'resident-types'

$p=Replace-OnceV1180 $p @'
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
'@ 'resident-helper'

# Pass shader address to graphics resource/pipeline creation.
$p=Replace-OnceV1180 $p @'
            IReadOnlyList<GuestImageResource>? feedbackTargets = null,
            bool hasDepthAttachment = false,
            GuestDepthResource? feedbackDepth = null)
'@ @'
            IReadOnlyList<GuestImageResource>? feedbackTargets = null,
            bool hasDepthAttachment = false,
            GuestDepthResource? feedbackDepth = null,
            ulong shaderAddress = 0)
'@ 'draw-resources-address-param'

$p=Replace-OnceV1180 $p @'
                    renderPass,
                    renderTargetFormats,
                    extent);
'@ @'
                    renderPass,
                    renderTargetFormats,
                    extent,
                    shaderAddress);
'@ 'pipeline-address-pass'

$p=Replace-OnceV1180 $p @'
                    hasDepthAttachment: depth is not null && !clearDepthSeparately,
                    feedbackDepth: clearDepthSeparately ? null : depth);
'@ @'
                    hasDepthAttachment: depth is not null && !clearDepthSeparately,
                    feedbackDepth: clearDepthSeparately ? null : depth,
                    shaderAddress: work.ShaderAddress);
'@ 'offscreen-address-pass'

$p=Replace-OnceV1180 $p @'
            IReadOnlyList<Format> renderTargetFormats,
            Extent2D extent)
        {
            var pipelineKey = new GraphicsPipelineKey(
                GetShaderDigest(vertexSpirv),
                GetShaderDigest(fragmentSpirv),
                string.Join(',', renderTargetFormats.Select(format => (uint)format)),
                resources.HasDepthAttachment,
                resources.Topology,
                string.Join(';', resources.Blends.Select(blend =>
                    $"{(blend.Enable ? 1 : 0)}:{blend.ColorSrcFactor}:{blend.ColorDstFactor}:" +
                    $"{blend.ColorFunc}:{blend.AlphaSrcFactor}:{blend.AlphaDstFactor}:" +
                    $"{blend.AlphaFunc}:{(blend.SeparateAlphaBlend ? 1 : 0)}:{blend.WriteMask}")),
                GetResourceLayoutKey(resources),
                GetVertexLayoutKey(resources),
                resources.Raster,
                resources.HasDepthAttachment ? resources.Depth : GuestDepthState.Default);
            if (_graphicsPipelines.TryGetValue(pipelineKey, out var cachedPipeline))
            {
                resources.Pipeline = cachedPipeline;
                resources.PipelineCached = true;
                return;
            }

            var pipelineCreateStartV74030 = _traceShaderPipelineTimingV74030
                ? Stopwatch.GetTimestamp()
                : 0L;
            var vertexModule = CreateShaderModule(vertexSpirv);
            var fragmentModule = CreateShaderModule(fragmentSpirv);
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
'@ 'graphics-resident-fastpath'

$p=Replace-OnceV1180 $p @'
                        resources.PipelineCached = true;
                        _graphicsPipelines.Add(pipelineKey, pipeline);
'@ @'
                        resources.PipelineCached = true;
                        _graphicsPipelines.Add(pipelineKey, pipeline);
                        if (fastKeyV1180 is { } fkV1180)
                        {
                            _residentGraphicsExecutionV1180[fkV1180] = pipeline;
                        }
'@ 'graphics-fast-insert'

$p=Replace-OnceV1180 $p @'
                SilkMarshal.Free((nint)entryPoint);
                _vk.DestroyShaderModule(_device, fragmentModule, null);
                _vk.DestroyShaderModule(_device, vertexModule, null);
                if (_traceShaderPipelineTimingV74030 && pipelineCreateStartV74030 != 0)
'@ @'
                SilkMarshal.Free((nint)entryPoint);
                if (!hasResidentFragmentV1180)
                {
                    _vk.DestroyShaderModule(_device, fragmentModule, null);
                }
                if (!hasResidentVertexV1180)
                {
                    _vk.DestroyShaderModule(_device, vertexModule, null);
                }
                if (_traceShaderPipelineTimingV74030 && pipelineCreateStartV74030 != 0)
'@ 'graphics-resident-module-lifetime'

# Compute address pass and resident direct-pipeline path.
$p=Replace-OnceV1180 $p @'
                CreateComputePipeline(resources, dispatch.ComputeSpirv);
'@ @'
                CreateComputePipeline(
                    resources,
                    dispatch.ComputeSpirv,
                    dispatch.ShaderAddress);
'@ 'compute-address-pass'

$p=Replace-OnceV1180 $p @'
        private void CreateComputePipeline(
            TranslatedDrawResources resources,
            byte[] computeSpirv)
        {
            var pipelineKey = new ComputePipelineKey(
                GetShaderDigest(computeSpirv),
                GetResourceLayoutKey(resources));
            if (_computePipelines.TryGetValue(pipelineKey, out var cachedPipeline))
            {
                resources.Pipeline = cachedPipeline;
                resources.PipelineCached = true;
                return;
            }

            var pipelineCreateStartV74030 = _traceShaderPipelineTimingV74030
                ? Stopwatch.GetTimestamp()
                : 0L;
            var computeModule = CreateShaderModule(computeSpirv);
'@ @'
        private void CreateComputePipeline(
            TranslatedDrawResources resources,
            byte[] computeSpirv,
            ulong shaderAddress)
        {
            var hasResidentV1180 = TryGetResidentShaderProgramV1180(
                computeSpirv,
                ShaderStageFlags.ComputeBit,
                shaderAddress,
                out var residentV1180);

            ResidentComputeExecutionKeyV1180? fastKeyV1180 = null;
            if (hasResidentV1180 && resources.PipelineLayout.Handle != 0)
            {
                fastKeyV1180 = new ResidentComputeExecutionKeyV1180(
                    residentV1180.ShaderId,
                    resources.PipelineLayout.Handle);
                if (_residentComputeExecutionV1180.TryGetValue(
                        fastKeyV1180.Value,
                        out var residentPipelineV1180))
                {
                    resources.Pipeline = residentPipelineV1180;
                    resources.PipelineCached = true;
                    Interlocked.Increment(ref _v1180ComputePipelineFastHits);
                    return;
                }
            }

            var pipelineKey = new ComputePipelineKey(
                hasResidentV1180 ? residentV1180.Digest : GetShaderDigest(computeSpirv),
                GetResourceLayoutKey(resources));
            if (_computePipelines.TryGetValue(pipelineKey, out var cachedPipeline))
            {
                resources.Pipeline = cachedPipeline;
                resources.PipelineCached = true;
                if (fastKeyV1180 is { } fkV1180)
                {
                    _residentComputeExecutionV1180[fkV1180] = cachedPipeline;
                }
                return;
            }

            var pipelineCreateStartV74030 = _traceShaderPipelineTimingV74030
                ? Stopwatch.GetTimestamp()
                : 0L;
            var computeModule = hasResidentV1180
                ? residentV1180.Module
                : CreateShaderModule(computeSpirv);
            if (hasResidentV1180 && ++residentV1180.PipelineVariantUses > 1)
            {
                Interlocked.Increment(ref _v1180ModuleReuseSavings);
            }
'@ 'compute-resident-fastpath'

$p=Replace-OnceV1180 $p @'
                    resources.PipelineCached = true;
                    _computePipelines.Add(pipelineKey, pipeline);
'@ @'
                    resources.PipelineCached = true;
                    _computePipelines.Add(pipelineKey, pipeline);
                    if (fastKeyV1180 is { } fkV1180)
                    {
                        _residentComputeExecutionV1180[fkV1180] = pipeline;
                    }
'@ 'compute-fast-insert'

$p=Replace-OnceV1180 $p @'
                SilkMarshal.Free((nint)entryPoint);
                _vk.DestroyShaderModule(_device, computeModule, null);
'@ @'
                SilkMarshal.Free((nint)entryPoint);
                if (!hasResidentV1180)
                {
                    _vk.DestroyShaderModule(_device, computeModule, null);
                }
'@ 'compute-resident-module-lifetime'

# Shutdown: after device idle and canonical pipelines are destroyed, destroy modules.
$p=Replace-OnceV1180 $p @'
            _graphicsPipelines.Clear();

            // SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE
'@ @'
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
'@ 'resident-shutdown'

$q=Replace-OnceV1180 $q @'
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "512");
'@ @'
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "512");

        // SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE
        Set("SHARPEMU_GPU_RESIDENT_SHADER_V1180", "1");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "4096");
'@ 'resident-envelope'

Write-Utf8NoBomV1180 $OutputPresenter $p
Write-Utf8NoBomV1180 $OutputEnvelope $q
Write-Host '[V118.0.1-PATCH] patch_ready=1 resident_shader_id=1 exact_content_guard=1 resident_module=1 direct_pipeline_fastpath=1 descriptor_cache_v11716=1 image_change=0 buffer_change=0 queue_change=0 submit_change=0 barrier_change=0'
