// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// SHARPEMU_V74_0_118_7_6_3_2_RAD_BGRA_FINAL_GUEST_IMAGE_COMPOSITE

using SharpEmu.ShaderCompiler.Vulkan;
using Silk.NET.Core.Native;
using Silk.NET.Vulkan;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private DescriptorSetLayout _v1187632DescriptorSetLayout;
        private DescriptorPool _v1187632DescriptorPool;
        private DescriptorSet[] _v1187632DescriptorSets = [];
        private PipelineLayout _v1187632PipelineLayout;
        private Pipeline _v1187632Pipeline;
        private Sampler _v1187632Sampler;
        private long _v1187632CompositeCount;

        private void EnsureRadFinalGuestCompositeResourcesV1187632()
        {
            if (_v1187632Pipeline.Handle != 0)
            {
                return;
            }

            if (_v11875RadMainMenuOverlayRenderPass.Handle == 0)
            {
                throw new InvalidOperationException(
                    "V118.7.6.3.2 overlay render pass is not ready");
            }

            var binding = new DescriptorSetLayoutBinding
            {
                Binding = 1,
                DescriptorType = DescriptorType.CombinedImageSampler,
                DescriptorCount = 1,
                StageFlags = ShaderStageFlags.FragmentBit,
            };
            var descriptorLayoutInfo = new DescriptorSetLayoutCreateInfo
            {
                SType = StructureType.DescriptorSetLayoutCreateInfo,
                BindingCount = 1,
                PBindings = &binding,
            };
            Check(
                _vk.CreateDescriptorSetLayout(
                    _device,
                    &descriptorLayoutInfo,
                    null,
                    out _v1187632DescriptorSetLayout),
                "vkCreateDescriptorSetLayout(V118.7.6.3.2)");

            var poolSize = new DescriptorPoolSize
            {
                Type = DescriptorType.CombinedImageSampler,
                DescriptorCount = checked((uint)MaxFramesInFlight),
            };
            var poolInfo = new DescriptorPoolCreateInfo
            {
                SType = StructureType.DescriptorPoolCreateInfo,
                MaxSets = checked((uint)MaxFramesInFlight),
                PoolSizeCount = 1,
                PPoolSizes = &poolSize,
            };
            Check(
                _vk.CreateDescriptorPool(
                    _device,
                    &poolInfo,
                    null,
                    out _v1187632DescriptorPool),
                "vkCreateDescriptorPool(V118.7.6.3.2)");

            var samplerInfo = new SamplerCreateInfo
            {
                SType = StructureType.SamplerCreateInfo,
                MagFilter = Filter.Linear,
                MinFilter = Filter.Linear,
                MipmapMode = SamplerMipmapMode.Linear,
                AddressModeU = SamplerAddressMode.ClampToEdge,
                AddressModeV = SamplerAddressMode.ClampToEdge,
                AddressModeW = SamplerAddressMode.ClampToEdge,
                MaxLod = 1f,
            };
            Check(
                _vk.CreateSampler(
                    _device,
                    &samplerInfo,
                    null,
                    out _v1187632Sampler),
                "vkCreateSampler(V118.7.6.3.2)");

            _v1187632DescriptorSets =
                new DescriptorSet[MaxFramesInFlight];
            for (var index = 0;
                 index < _v1187632DescriptorSets.Length;
                 index++)
            {
                var layout = _v1187632DescriptorSetLayout;
                var allocateInfo = new DescriptorSetAllocateInfo
                {
                    SType = StructureType.DescriptorSetAllocateInfo,
                    DescriptorPool = _v1187632DescriptorPool,
                    DescriptorSetCount = 1,
                    PSetLayouts = &layout,
                };
                Check(
                    _vk.AllocateDescriptorSets(
                        _device,
                        &allocateInfo,
                        out _v1187632DescriptorSets[index]),
                    "vkAllocateDescriptorSets(V118.7.6.3.2)");
            }

            var descriptorSetLayout =
                _v1187632DescriptorSetLayout;
            var pipelineLayoutInfo = new PipelineLayoutCreateInfo
            {
                SType = StructureType.PipelineLayoutCreateInfo,
                SetLayoutCount = 1,
                PSetLayouts = &descriptorSetLayout,
            };
            Check(
                _vk.CreatePipelineLayout(
                    _device,
                    &pipelineLayoutInfo,
                    null,
                    out _v1187632PipelineLayout),
                "vkCreatePipelineLayout(V118.7.6.3.2)");

            var vertexModule =
                CreateShaderModule(
                    SpirvFixedShaders.CreateFullscreenVertex(1));
            var fragmentModule =
                CreateShaderModule(
                    RadUiBlackKeyShaderV1187632.Create());
            var entryPoint =
                (byte*)SilkMarshal.StringToPtr("main");

            try
            {
                var stages =
                    stackalloc PipelineShaderStageCreateInfo[2];
                stages[0] = new PipelineShaderStageCreateInfo
                {
                    SType =
                        StructureType.PipelineShaderStageCreateInfo,
                    Stage = ShaderStageFlags.VertexBit,
                    Module = vertexModule,
                    PName = entryPoint,
                };
                stages[1] = new PipelineShaderStageCreateInfo
                {
                    SType =
                        StructureType.PipelineShaderStageCreateInfo,
                    Stage = ShaderStageFlags.FragmentBit,
                    Module = fragmentModule,
                    PName = entryPoint,
                };

                var vertexInput =
                    new PipelineVertexInputStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineVertexInputStateCreateInfo,
                    };
                var inputAssembly =
                    new PipelineInputAssemblyStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineInputAssemblyStateCreateInfo,
                        Topology = PrimitiveTopology.TriangleList,
                    };
                var viewport =
                    new Viewport(
                        0,
                        0,
                        _extent.Width,
                        _extent.Height,
                        0,
                        1);
                var scissor =
                    new Rect2D(
                        new Offset2D(0, 0),
                        _extent);
                var viewportState =
                    new PipelineViewportStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineViewportStateCreateInfo,
                        ViewportCount = 1,
                        PViewports = &viewport,
                        ScissorCount = 1,
                        PScissors = &scissor,
                    };
                var rasterization =
                    new PipelineRasterizationStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineRasterizationStateCreateInfo,
                        PolygonMode = PolygonMode.Fill,
                        CullMode = CullModeFlags.None,
                        FrontFace = FrontFace.CounterClockwise,
                        LineWidth = 1,
                    };
                var multisample =
                    new PipelineMultisampleStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineMultisampleStateCreateInfo,
                        RasterizationSamples =
                            SampleCountFlags.Count1Bit,
                    };
                var blendAttachment =
                    new PipelineColorBlendAttachmentState
                    {
                        BlendEnable = true,
                        SrcColorBlendFactor = BlendFactor.SrcAlpha,
                        DstColorBlendFactor =
                            BlendFactor.OneMinusSrcAlpha,
                        ColorBlendOp = BlendOp.Add,
                        SrcAlphaBlendFactor = BlendFactor.One,
                        DstAlphaBlendFactor =
                            BlendFactor.OneMinusSrcAlpha,
                        AlphaBlendOp = BlendOp.Add,
                        ColorWriteMask =
                            ColorComponentFlags.RBit |
                            ColorComponentFlags.GBit |
                            ColorComponentFlags.BBit |
                            ColorComponentFlags.ABit,
                    };
                var blend =
                    new PipelineColorBlendStateCreateInfo
                    {
                        SType =
                            StructureType.PipelineColorBlendStateCreateInfo,
                        AttachmentCount = 1,
                        PAttachments = &blendAttachment,
                    };
                var pipelineInfo =
                    new GraphicsPipelineCreateInfo
                    {
                        SType =
                            StructureType.GraphicsPipelineCreateInfo,
                        StageCount = 2,
                        PStages = stages,
                        PVertexInputState = &vertexInput,
                        PInputAssemblyState = &inputAssembly,
                        PViewportState = &viewportState,
                        PRasterizationState = &rasterization,
                        PMultisampleState = &multisample,
                        PColorBlendState = &blend,
                        Layout = _v1187632PipelineLayout,
                        RenderPass =
                            _v11875RadMainMenuOverlayRenderPass,
                    };
                Check(
                    _vk.CreateGraphicsPipelines(
                        _device,
                        _pipelineCache,
                        1,
                        &pipelineInfo,
                        null,
                        out _v1187632Pipeline),
                    "vkCreateGraphicsPipelines(V118.7.6.3.2)");
                MarkPipelineCacheDirty();
            }
            finally
            {
                SilkMarshal.Free((nint)entryPoint);
                _vk.DestroyShaderModule(
                    _device,
                    fragmentModule,
                    null);
                _vk.DestroyShaderModule(
                    _device,
                    vertexModule,
                    null);
            }
        }

        private void RecordRadFinalGuestImageCompositeV1187632(
            uint imageIndex,
            int frameSlot,
            GuestImageResource source)
        {
            EnsureRadFinalGuestCompositeResourcesV1187632();

            BeginDebugLabel(
                _commandBuffer,
                "V118.7.6.3.2 RAD BGRA + final guest image");

            // _frameUploadBuffers[frameSlot] already contains the current official
            // RAD BGRA capture because Present() broadens V118.7.5 preparation to
            // the final GuestImage path before command recording.
            RecordRadMainMenuBackgroundUploadV11875(
                imageIndex,
                frameSlot);

            GetGuestImageSourceSync(
                source,
                out var sourceStage,
                out var sourceAccess);
            var sourceToSample = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask =
                    sourceAccess |
                    AccessFlags.MemoryWriteBit,
                DstAccessMask = AccessFlags.ShaderReadBit,
                OldLayout = source.Layout,
                NewLayout = ImageLayout.ShaderReadOnlyOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = source.Image,
                SubresourceRange = ColorSubresourceRange(),
            };
            _vk.CmdPipelineBarrier(
                _commandBuffer,
                sourceStage,
                PipelineStageFlags.FragmentShaderBit,
                0,
                0,
                null,
                0,
                null,
                1,
                &sourceToSample);
            source.Layout = ImageLayout.ShaderReadOnlyOptimal;

            var descriptorSet =
                _v1187632DescriptorSets[frameSlot];
            var imageInfo = new DescriptorImageInfo
            {
                Sampler = _v1187632Sampler,
                ImageView = source.View,
                ImageLayout = ImageLayout.ShaderReadOnlyOptimal,
            };
            var write = new WriteDescriptorSet
            {
                SType = StructureType.WriteDescriptorSet,
                DstSet = descriptorSet,
                DstBinding = 1,
                DescriptorCount = 1,
                DescriptorType =
                    DescriptorType.CombinedImageSampler,
                PImageInfo = &imageInfo,
            };
            _vk.UpdateDescriptorSets(
                _device,
                1,
                &write,
                0,
                null);

            BeginTranslatedRenderPass(
                _v11875RadMainMenuOverlayRenderPass,
                _framebuffers[imageIndex],
                _extent);
            _vk.CmdBindPipeline(
                _commandBuffer,
                PipelineBindPoint.Graphics,
                _v1187632Pipeline);
            _vk.CmdBindDescriptorSets(
                _commandBuffer,
                PipelineBindPoint.Graphics,
                _v1187632PipelineLayout,
                0,
                1,
                &descriptorSet,
                0,
                null);
            _vk.CmdDraw(
                _commandBuffer,
                3,
                1,
                0,
                0);
            _vk.CmdEndRenderPass(_commandBuffer);

            var composite =
                System.Threading.Interlocked.Increment(
                    ref _v1187632CompositeCount);
            if (composite <= 16 ||
                (composite & (composite - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.118.7.6.3.2][RAD_MAIN_MENU_FINAL_GUEST_COMPOSITE] " +
                    $"count={composite} frame={_hostMovieFrameSerial} " +
                    $"capture_serial={_v1187ExternalRadCaptureSourceSerial} " +
                    $"guest_image=0x{source.Address:X16} " +
                    $"guest_format={source.Format} " +
                    "background=official-rad-bgra " +
                    "overlay=final-guest-image-black-key " +
                    "same_surface=True");
            }

            EndDebugLabel(_commandBuffer);
        }
    }
}
