// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// SHARPEMU_V74_0_118_7_6_3_9_GLYPH_PRESERVE_OVERLAY

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

        // SHARPEMU_V74_0_118_7_6_3_6_TRANSFER_RESOLVE
        // Direct fragment sampling of the raw guest scanout recorded valid
        // commands but produced no visible UI on RTX 5060 Ti. Resolve the guest
        // image through a transfer-visible clean image before black-key sampling.
        private Image[] _v1187636UiResolveImages = [];
        private DeviceMemory[] _v1187636UiResolveMemories = [];
        private ImageView[] _v1187636UiResolveViews = [];
        private ImageLayout[] _v1187636UiResolveLayouts = [];
        private Format[] _v1187636UiResolveFormats = [];
        private uint[] _v1187636UiResolveWidths = [];
        private uint[] _v1187636UiResolveHeights = [];
        private long _v1187636ResolveCount;

        // SHARPEMU_V74_0_118_7_6_3_8_MENU_SCISSOR_TELEMETRY
        private long _v118638MenuScissorLogCount;

        private void EnsureRadFinalGuestCompositeResourcesV1187632()
        {
            if (_v1187632Pipeline.Handle != 0)
            {
                return;
            }

            if (_v11875RadMainMenuOverlayRenderPass.Handle == 0)
            {
                throw new InvalidOperationException(
                    "V118.7.6.3.6 overlay render pass is not ready");
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
                // SHARPEMU_V74_0_118_7_6_3_8_STRUCTURAL_MENU_SCISSOR
                // The V118.7.6.3.6 resolved source is a complete guest frame.
                // Physically clip the guest overlay to the menu side of the
                // screen so it cannot cover the official RAD background.
                var menuScissorXV118638 =
                    checked((int)(_extent.Width * 15u / 100u));
                var menuScissorYV118638 =
                    checked((int)(_extent.Height * 28u / 100u));
                var menuScissorHeightV118638 =
                    Math.Max(
                        1u,
                        _extent.Height * 32u / 100u);
                var menuScissorWidthV118638 =
                    Math.Max(
                        1u,
                        _extent.Width * 33u / 100u);
                var scissor =
                    new Rect2D(
                        new Offset2D(
                            menuScissorXV118638,
                            menuScissorYV118638),
                        new Extent2D(
                            menuScissorWidthV118638,
                            menuScissorHeightV118638));
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
                    "vkCreateGraphicsPipelines(V118.7.6.3.8 structural menu)");
                MarkPipelineCacheDirty();

                var menuScissorLogV118638 =
                    System.Threading.Interlocked.Increment(
                        ref _v118638MenuScissorLogCount);
                if (menuScissorLogV118638 <= 4)
                {
                    Console.Error.WriteLine(
                        "[V74.0.118.7.6.3.9][RAD_MAIN_MENU_UI_GLYPH_REGION] " +
                        $"count={menuScissorLogV118638} " +
                        $"rect={menuScissorXV118638},{menuScissorYV118638}," +
                        $"{menuScissorWidthV118638}x" +
                        $"{menuScissorHeightV118638} " +
                        "owner=overlay-pipeline neighborhood-alpha=glyph-preserve " +
                        "background=official-rad-bgra");
                }
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

        private void EnsureRadUiResolveArraysV1187636()
        {
            if (_v1187636UiResolveImages.Length ==
                MaxFramesInFlight)
            {
                return;
            }

            _v1187636UiResolveImages =
                new Image[MaxFramesInFlight];
            _v1187636UiResolveMemories =
                new DeviceMemory[MaxFramesInFlight];
            _v1187636UiResolveViews =
                new ImageView[MaxFramesInFlight];
            _v1187636UiResolveLayouts =
                new ImageLayout[MaxFramesInFlight];
            _v1187636UiResolveFormats =
                new Format[MaxFramesInFlight];
            _v1187636UiResolveWidths =
                new uint[MaxFramesInFlight];
            _v1187636UiResolveHeights =
                new uint[MaxFramesInFlight];
        }

        private void DestroyRadUiResolveSlotV1187636(
            int frameSlot)
        {
            if (_v1187636UiResolveViews[frameSlot].Handle != 0)
            {
                _vk.DestroyImageView(
                    _device,
                    _v1187636UiResolveViews[frameSlot],
                    null);
                _v1187636UiResolveViews[frameSlot] = default;
            }

            if (_v1187636UiResolveImages[frameSlot].Handle != 0)
            {
                _vk.DestroyImage(
                    _device,
                    _v1187636UiResolveImages[frameSlot],
                    null);
                _v1187636UiResolveImages[frameSlot] = default;
            }

            if (_v1187636UiResolveMemories[frameSlot].Handle != 0)
            {
                _vk.FreeMemory(
                    _device,
                    _v1187636UiResolveMemories[frameSlot],
                    null);
                _v1187636UiResolveMemories[frameSlot] = default;
            }

            _v1187636UiResolveLayouts[frameSlot] =
                ImageLayout.Undefined;
            _v1187636UiResolveFormats[frameSlot] =
                Format.Undefined;
            _v1187636UiResolveWidths[frameSlot] = 0;
            _v1187636UiResolveHeights[frameSlot] = 0;
        }

        private void EnsureRadUiResolveImageV1187636(
            int frameSlot,
            GuestImageResource source)
        {
            EnsureRadUiResolveArraysV1187636();

            if (_v1187636UiResolveImages[frameSlot].Handle != 0 &&
                _v1187636UiResolveFormats[frameSlot] == source.Format &&
                _v1187636UiResolveWidths[frameSlot] == source.Width &&
                _v1187636UiResolveHeights[frameSlot] == source.Height)
            {
                return;
            }

            if (_v1187636UiResolveImages[frameSlot].Handle != 0)
            {
                // A format/extent change is rare here. Make the replacement
                // explicit and safe rather than destroying an in-flight image.
                UpscalerAwareDeviceWaitIdle();
                DestroyRadUiResolveSlotV1187636(frameSlot);
            }

            var imageInfo = new ImageCreateInfo
            {
                SType = StructureType.ImageCreateInfo,
                ImageType = ImageType.Type2D,
                Format = source.Format,
                Extent = new Extent3D(
                    source.Width,
                    source.Height,
                    1),
                MipLevels = 1,
                ArrayLayers = 1,
                Samples = SampleCountFlags.Count1Bit,
                Tiling = ImageTiling.Optimal,
                Usage =
                    ImageUsageFlags.TransferDstBit |
                    ImageUsageFlags.SampledBit,
                SharingMode = SharingMode.Exclusive,
                InitialLayout = ImageLayout.Undefined,
            };
            Check(
                _vk.CreateImage(
                    _device,
                    &imageInfo,
                    null,
                    out _v1187636UiResolveImages[frameSlot]),
                "vkCreateImage(V118.7.6.3.6 UI resolve)");

            _vk.GetImageMemoryRequirements(
                _device,
                _v1187636UiResolveImages[frameSlot],
                out var requirements);
            var allocationInfo = new MemoryAllocateInfo
            {
                SType = StructureType.MemoryAllocateInfo,
                AllocationSize = requirements.Size,
                MemoryTypeIndex = FindMemoryType(
                    requirements.MemoryTypeBits,
                    MemoryPropertyFlags.DeviceLocalBit),
            };
            Check(
                _vk.AllocateMemory(
                    _device,
                    &allocationInfo,
                    null,
                    out _v1187636UiResolveMemories[frameSlot]),
                "vkAllocateMemory(V118.7.6.3.6 UI resolve)");
            Check(
                _vk.BindImageMemory(
                    _device,
                    _v1187636UiResolveImages[frameSlot],
                    _v1187636UiResolveMemories[frameSlot],
                    0),
                "vkBindImageMemory(V118.7.6.3.6 UI resolve)");

            var viewInfo = new ImageViewCreateInfo
            {
                SType = StructureType.ImageViewCreateInfo,
                Image = _v1187636UiResolveImages[frameSlot],
                ViewType = ImageViewType.Type2D,
                Format = source.Format,
                Components = new ComponentMapping(
                    ComponentSwizzle.Identity,
                    ComponentSwizzle.Identity,
                    ComponentSwizzle.Identity,
                    ComponentSwizzle.Identity),
                SubresourceRange = ColorSubresourceRange(),
            };
            Check(
                _vk.CreateImageView(
                    _device,
                    &viewInfo,
                    null,
                    out _v1187636UiResolveViews[frameSlot]),
                "vkCreateImageView(V118.7.6.3.6 UI resolve)");

            _v1187636UiResolveFormats[frameSlot] =
                source.Format;
            _v1187636UiResolveWidths[frameSlot] =
                source.Width;
            _v1187636UiResolveHeights[frameSlot] =
                source.Height;
            _v1187636UiResolveLayouts[frameSlot] =
                ImageLayout.Undefined;

            SetDebugName(
                ObjectType.Image,
                _v1187636UiResolveImages[frameSlot].Handle,
                $"SharpEmu V118.7.6.3.6 UI resolve {frameSlot} " +
                $"{source.Width}x{source.Height} {source.Format}");
            SetDebugName(
                ObjectType.ImageView,
                _v1187636UiResolveViews[frameSlot].Handle,
                $"SharpEmu V118.7.6.3.6 UI resolve view {frameSlot}");
        }

        private void ResolveRadGuestUiForSamplingV1187636(
            int frameSlot,
            GuestImageResource source)
        {
            EnsureRadUiResolveImageV1187636(
                frameSlot,
                source);

            GetGuestImageSourceSync(
                source,
                out _,
                out var sourceAccess);

            var sourceToTransfer = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                // Match the known-good generic RecordGuestImageBlit ordering:
                // make ALL earlier guest writes visible to transfer. Direct
                // shader sampling was recording successfully but produced an
                // all-black overlay on the tested NVIDIA path.
                SrcAccessMask =
                    sourceAccess |
                    AccessFlags.MemoryWriteBit,
                DstAccessMask =
                    AccessFlags.TransferReadBit,
                OldLayout = source.Layout,
                NewLayout = ImageLayout.TransferSrcOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = source.Image,
                SubresourceRange = ColorSubresourceRange(),
            };

            var resolveOldLayout =
                _v1187636UiResolveLayouts[frameSlot];
            var resolveToTransfer = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask =
                    resolveOldLayout ==
                    ImageLayout.ShaderReadOnlyOptimal
                        ? AccessFlags.ShaderReadBit
                        : 0,
                DstAccessMask =
                    AccessFlags.TransferWriteBit,
                OldLayout = resolveOldLayout,
                NewLayout = ImageLayout.TransferDstOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = _v1187636UiResolveImages[frameSlot],
                SubresourceRange = ColorSubresourceRange(),
            };

            var preCopyBarriers =
                stackalloc ImageMemoryBarrier[2];
            preCopyBarriers[0] = sourceToTransfer;
            preCopyBarriers[1] = resolveToTransfer;
            _vk.CmdPipelineBarrier(
                _commandBuffer,
                PipelineStageFlags.AllCommandsBit,
                PipelineStageFlags.TransferBit,
                0,
                0,
                null,
                0,
                null,
                2,
                preCopyBarriers);

            source.Layout =
                ImageLayout.TransferSrcOptimal;
            _v1187636UiResolveLayouts[frameSlot] =
                ImageLayout.TransferDstOptimal;

            var copyRegion = new ImageCopy
            {
                SrcSubresource = new ImageSubresourceLayers(
                    ImageAspectFlags.ColorBit,
                    0,
                    0,
                    1),
                DstSubresource = new ImageSubresourceLayers(
                    ImageAspectFlags.ColorBit,
                    0,
                    0,
                    1),
                Extent = new Extent3D(
                    source.Width,
                    source.Height,
                    1),
            };
            _vk.CmdCopyImage(
                _commandBuffer,
                source.Image,
                ImageLayout.TransferSrcOptimal,
                _v1187636UiResolveImages[frameSlot],
                ImageLayout.TransferDstOptimal,
                1,
                &copyRegion);

            var sourceToShaderRead = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask =
                    AccessFlags.TransferReadBit,
                DstAccessMask =
                    AccessFlags.ShaderReadBit,
                OldLayout =
                    ImageLayout.TransferSrcOptimal,
                NewLayout =
                    ImageLayout.ShaderReadOnlyOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = source.Image,
                SubresourceRange = ColorSubresourceRange(),
            };
            var resolveToShaderRead = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask =
                    AccessFlags.TransferWriteBit,
                DstAccessMask =
                    AccessFlags.ShaderReadBit,
                OldLayout =
                    ImageLayout.TransferDstOptimal,
                NewLayout =
                    ImageLayout.ShaderReadOnlyOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = _v1187636UiResolveImages[frameSlot],
                SubresourceRange = ColorSubresourceRange(),
            };
            var postCopyBarriers =
                stackalloc ImageMemoryBarrier[2];
            postCopyBarriers[0] = sourceToShaderRead;
            postCopyBarriers[1] = resolveToShaderRead;
            _vk.CmdPipelineBarrier(
                _commandBuffer,
                PipelineStageFlags.TransferBit,
                PipelineStageFlags.AllCommandsBit,
                0,
                0,
                null,
                0,
                null,
                2,
                postCopyBarriers);

            source.Layout =
                ImageLayout.ShaderReadOnlyOptimal;
            _v1187636UiResolveLayouts[frameSlot] =
                ImageLayout.ShaderReadOnlyOptimal;

            var resolved =
                System.Threading.Interlocked.Increment(
                    ref _v1187636ResolveCount);
            if (resolved <= 16 ||
                (resolved & (resolved - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.118.7.6.3.6][RAD_MAIN_MENU_UI_RESOLVE] " +
                    $"count={resolved} frame={_hostMovieFrameSerial} " +
                    $"source=0x{source.Address:X16} " +
                    $"source_layout={source.Layout} " +
                    $"source_format={source.Format} " +
                    $"size={source.Width}x{source.Height} " +
                    $"resolve_image=0x{_v1187636UiResolveImages[frameSlot].Handle:X} " +
                    $"slot={frameSlot} method=transfer-copy " +
                    "src_stage=all-commands " +
                    "dst=clean-sampled-image");
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
                "V118.7.6.3.9 RAD BGRA + glyph-preserving guest UI");

            // Important: do not sample source.View directly. The generic guest
            // presentation path has a transfer visibility barrier specifically
            // because raw guest images can otherwise appear stale/black.
            ResolveRadGuestUiForSamplingV1187636(
                frameSlot,
                source);

            // Official RAD remains the only Bink movie/background decoder.
            RecordRadMainMenuBackgroundUploadV11875(
                imageIndex,
                frameSlot);

            var descriptorSet =
                _v1187632DescriptorSets[frameSlot];
            var imageInfo = new DescriptorImageInfo
            {
                Sampler = _v1187632Sampler,
                ImageView =
                    _v1187636UiResolveViews[frameSlot],
                ImageLayout =
                    ImageLayout.ShaderReadOnlyOptimal,
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
                    "[V74.0.118.7.6.3.9][RAD_MAIN_MENU_GLYPH_UI_COMPOSITE] " +
                    $"count={composite} frame={_hostMovieFrameSerial} " +
                    $"capture_serial={_v1187ExternalRadCaptureSourceSerial} " +
                    $"guest_image=0x{source.Address:X16} " +
                    $"guest_format={source.Format} " +
                    $"resolve_image=0x{_v1187636UiResolveImages[frameSlot].Handle:X} " +
                    "background=official-rad-bgra " +
                    "overlay=transfer-resolved-final-guest-image-menu-region-neighborhood-alpha " +
                    "same_surface=True");
            }

            EndDebugLabel(_commandBuffer);
        }
    }
}
