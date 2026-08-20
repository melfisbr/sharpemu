// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using Silk.NET.Core.Native;
using Silk.NET.Vulkan;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        private const uint UpscalerAbiVersion = 1;
        private NativeVulkanUpscaler? _nativeUpscaler;
        private GuestImageResource? _upscalerOutput;
        private bool _upscalerOutputReset = true;
        private long _upscalerLastFrameTimestamp;
        private ulong _upscalerFrameId;
        private bool _upscalerInitAttempted;
        private bool _upscalerFallbackLogged;
        private bool _upscalerRequiredExtensionMissing;
        private uint _upscalerInitWidth;
        private uint _upscalerInitHeight;
        private const int MaxNativeUpscalerExtensions = 16;

        private enum HostUpscalerBackend : int
        {
            Off = 0,
            Auto = 1,
            Dlss = 2,
            Fsr = 3,
        }

        private enum HostUpscalerQuality : int
        {
            NativeAa = 0,
            Quality = 1,
            Balanced = 2,
            Performance = 3,
            UltraPerformance = 4,
        }

        [Flags]
        private enum NativeUpscalerCapabilities : uint
        {
            None = 0,
            Dlss = 1u << 0,
            Fsr = 1u << 1,
            ColorOnly = 1u << 2,
            Temporal = 1u << 3,
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeUpscalerInitDesc
        {
            public uint Size;
            public uint AbiVersion;
            public ulong Instance;
            public ulong PhysicalDevice;
            public ulong Device;
            public ulong Queue;
            public uint QueueFamilyIndex;
            public uint VendorId;
            public uint OutputWidth;
            public uint OutputHeight;
            public uint Reserved0;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeUpscalerDispatchDesc
        {
            public uint Size;
            public uint AbiVersion;
            public int Backend;
            public int Quality;
            public ulong CommandBuffer;
            public ulong ColorImage;
            public ulong ColorView;
            public uint ColorFormat;
            public uint ColorWidth;
            public uint ColorHeight;
            public int ColorLayout;
            public ulong OutputImage;
            public ulong OutputView;
            public uint OutputFormat;
            public uint OutputWidth;
            public uint OutputHeight;
            public int OutputLayout;
            public ulong DepthImage;
            public ulong DepthView;
            public uint DepthFormat;
            public uint DepthWidth;
            public uint DepthHeight;
            public int DepthLayout;
            public ulong MotionImage;
            public ulong MotionView;
            public uint MotionFormat;
            public uint MotionWidth;
            public uint MotionHeight;
            public int MotionLayout;
            public float JitterX;
            public float JitterY;
            public float MotionVectorScaleX;
            public float MotionVectorScaleY;
            public float Sharpness;
            public float FrameTimeMilliseconds;
            public uint Reset;
            public uint Flags;
            public ulong FrameId;
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int GetExtensionListDelegate(
            ulong instance,
            ulong physicalDevice,
            byte* buffer,
            int capacity);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int InitDelegate(NativeUpscalerInitDesc* desc);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int DispatchDelegate(NativeUpscalerDispatchDesc* desc);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate uint CapabilitiesDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ShutdownDelegate();

        private sealed class NativeVulkanUpscaler : IDisposable
        {
            private readonly nint _library;
            private readonly GetExtensionListDelegate? _instanceExtensions;
            private readonly GetExtensionListDelegate? _deviceExtensions;
            private readonly InitDelegate _initialize;
            private readonly DispatchDelegate _dispatch;
            private readonly CapabilitiesDelegate _capabilities;
            private readonly ShutdownDelegate _shutdown;
            private bool _initialized;

            private NativeVulkanUpscaler(
                nint library,
                GetExtensionListDelegate? instanceExtensions,
                GetExtensionListDelegate? deviceExtensions,
                InitDelegate initialize,
                DispatchDelegate dispatch,
                CapabilitiesDelegate capabilities,
                ShutdownDelegate shutdown)
            {
                _library = library;
                _instanceExtensions = instanceExtensions;
                _deviceExtensions = deviceExtensions;
                _initialize = initialize;
                _dispatch = dispatch;
                _capabilities = capabilities;
                _shutdown = shutdown;
            }

            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();

            public static NativeVulkanUpscaler? TryLoad()
            {
                var configured = Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER_NATIVE");
                var candidates = new List<string>();
                if (!string.IsNullOrWhiteSpace(configured))
                {
                    candidates.Add(configured.Trim());
                }

                candidates.Add(Path.Combine(AppContext.BaseDirectory, "upscalers", "SharpEmu.VulkanUpscaler.Native.dll"));
                candidates.Add(Path.Combine(AppContext.BaseDirectory, "SharpEmu.VulkanUpscaler.Native.dll"));

                foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!File.Exists(candidate) || !NativeLibrary.TryLoad(candidate, out var library))
                    {
                        continue;
                    }

                    try
                    {
                        if (!TryGet(library, "sharpemu_vk_upscaler_initialize", out InitDelegate? initialize) ||
                            !TryGet(library, "sharpemu_vk_upscaler_dispatch", out DispatchDelegate? dispatch) ||
                            !TryGet(library, "sharpemu_vk_upscaler_get_capabilities", out CapabilitiesDelegate? capabilities) ||
                            !TryGet(library, "sharpemu_vk_upscaler_shutdown", out ShutdownDelegate? shutdown))
                        {
                            NativeLibrary.Free(library);
                            continue;
                        }

                        _ = TryGet(library, "sharpemu_vk_upscaler_get_instance_extensions", out GetExtensionListDelegate? instanceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_device_extensions", out GetExtensionListDelegate? deviceExtensions);
                        Console.Error.WriteLine($"[V74.0.64][UPSCALER] native provider loaded: {candidate}");
                        return new NativeVulkanUpscaler(
                            library,
                            instanceExtensions,
                            deviceExtensions,
                            initialize!,
                            dispatch!,
                            capabilities!,
                            shutdown!);
                    }
                    catch
                    {
                        NativeLibrary.Free(library);
                        throw;
                    }
                }

                return null;
            }

            private static bool TryGet<T>(nint library, string name, out T? value)
                where T : Delegate
            {
                value = null;
                if (!NativeLibrary.TryGetExport(library, name, out var address))
                {
                    return false;
                }

                value = Marshal.GetDelegateForFunctionPointer<T>(address);
                return true;
            }

            public unsafe IReadOnlyList<string> GetInstanceExtensions() =>
                ReadExtensions(_instanceExtensions, 0, 0);

            public unsafe IReadOnlyList<string> GetDeviceExtensions(Instance instance, PhysicalDevice physicalDevice) =>
                ReadExtensions(_deviceExtensions, (ulong)instance.Handle, (ulong)physicalDevice.Handle);

            private static unsafe IReadOnlyList<string> ReadExtensions(
                GetExtensionListDelegate? getter,
                ulong instance,
                ulong physicalDevice)
            {
                if (getter is null)
                {
                    return [];
                }

                const int capacity = 4096;
                var buffer = stackalloc byte[capacity];
                var length = getter(instance, physicalDevice, buffer, capacity);
                if (length <= 0 || length >= capacity)
                {
                    return [];
                }

                var text = Encoding.UTF8.GetString(new ReadOnlySpan<byte>(buffer, length));
                return text.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            }

            public unsafe bool Initialize(NativeUpscalerInitDesc desc)
            {
                if (_initialized)
                {
                    return true;
                }

                var result = _initialize(&desc);
                _initialized = result == 0;
                return _initialized;
            }

            public unsafe bool Dispatch(NativeUpscalerDispatchDesc desc) =>
                _initialized && _dispatch(&desc) == 0;

            public void Dispose()
            {
                if (_initialized)
                {
                    _shutdown();
                    _initialized = false;
                }

                if (_library != 0)
                {
                    NativeLibrary.Free(_library);
                }
            }
        }

        private static HostUpscalerBackend RequestedUpscalerBackend()
        {
            var value = Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER")?.Trim();
            return value?.ToLowerInvariant() switch
            {
                "auto" => HostUpscalerBackend.Auto,
                "dlss" => HostUpscalerBackend.Dlss,
                "fsr" or "fsr3" => HostUpscalerBackend.Fsr,
                _ => HostUpscalerBackend.Off,
            };
        }

        private static HostUpscalerQuality RequestedUpscalerQuality()
        {
            var value = Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER_QUALITY")?.Trim();
            return value?.ToLowerInvariant() switch
            {
                "native" or "nativeaa" or "dlaa" => HostUpscalerQuality.NativeAa,
                "balanced" => HostUpscalerQuality.Balanced,
                "performance" => HostUpscalerQuality.Performance,
                "ultra" or "ultraperformance" or "ultra-performance" => HostUpscalerQuality.UltraPerformance,
                _ => HostUpscalerQuality.Quality,
            };
        }

        private static float RequestedUpscalerSharpness()
        {
            return float.TryParse(
                    Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER_SHARPNESS"),
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var value)
                ? Math.Clamp(value, 0f, 1f)
                : 0.2f;
        }

        private static float ReadUpscalerFloat(string name, float fallback)
        {
            return float.TryParse(
                    Environment.GetEnvironmentVariable(name),
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var value) && float.IsFinite(value)
                ? value
                : fallback;
        }

        private static ulong ParseAddressEnvironment(string name)
        {
            var text = Environment.GetEnvironmentVariable(name)?.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                return 0;
            }

            if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            {
                text = text[2..];
            }

            return ulong.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value)
                ? value
                : 0;
        }

        private NativeVulkanUpscaler? EnsureUpscalerProviderLoaded()
        {
            if (RequestedUpscalerBackend() == HostUpscalerBackend.Off)
            {
                return null;
            }

            return _nativeUpscaler ??= NativeVulkanUpscaler.TryLoad();
        }

        private void AppendUpscalerInstanceExtensions(
            byte** enabledExtensions,
            ref int enabledExtensionCount,
            List<nint> allocatedPointers)
        {
            var provider = EnsureUpscalerProviderLoaded();
            if (provider is null)
            {
                return;
            }

            try
            {
                var appended = 0;
                foreach (var extension in provider.GetInstanceExtensions().Distinct(StringComparer.Ordinal))
                {
                    if (extension is DebugUtilsExtensionName or PortabilityEnumerationExtensionName or SwapchainColorspaceExtensionName)
                    {
                        continue;
                    }
                    if (!IsInstanceExtensionAvailable(extension))
                    {
                        _upscalerRequiredExtensionMissing = true;
                        Console.Error.WriteLine($"[V74.0.64][UPSCALER][WARN] required Vulkan instance extension unavailable: {extension}");
                        continue;
                    }
                    if (appended >= MaxNativeUpscalerExtensions)
                    {
                        _upscalerRequiredExtensionMissing = true;
                        Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider requested more than 16 Vulkan instance extensions; provider disabled.");
                        break;
                    }

                    var pointer = SilkMarshal.StringToPtr(extension);
                    allocatedPointers.Add(pointer);
                    enabledExtensions[enabledExtensionCount++] = (byte*)pointer;
                    appended++;
                }
            }
            catch (Exception ex)
            {
                _upscalerRequiredExtensionMissing = true;
                Console.Error.WriteLine($"[V74.0.64][UPSCALER][WARN] instance-extension query failed: {ex.Message}");
            }
        }

        private void AppendUpscalerDeviceExtensions(
            byte** enabledExtensions,
            ref uint enabledExtensionCount,
            List<nint> allocatedPointers)
        {
            var provider = EnsureUpscalerProviderLoaded();
            if (provider is null)
            {
                return;
            }

            try
            {
                var appended = 0;
                foreach (var extension in provider.GetDeviceExtensions(_instance, _physicalDevice).Distinct(StringComparer.Ordinal))
                {
                    if (extension is "VK_KHR_swapchain" or "VK_KHR_maintenance8" or "VK_EXT_robustness2" or PortabilitySubsetExtensionName)
                    {
                        continue;
                    }
                    if (!IsDeviceExtensionAvailable(extension))
                    {
                        _upscalerRequiredExtensionMissing = true;
                        Console.Error.WriteLine($"[V74.0.64][UPSCALER][WARN] required Vulkan device extension unavailable: {extension}");
                        continue;
                    }
                    if (appended >= MaxNativeUpscalerExtensions)
                    {
                        _upscalerRequiredExtensionMissing = true;
                        Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider requested more than 16 Vulkan device extensions; provider disabled.");
                        break;
                    }

                    var pointer = SilkMarshal.StringToPtr(extension);
                    allocatedPointers.Add(pointer);
                    enabledExtensions[enabledExtensionCount++] = (byte*)pointer;
                    appended++;
                }
            }
            catch (Exception ex)
            {
                _upscalerRequiredExtensionMissing = true;
                Console.Error.WriteLine($"[V74.0.64][UPSCALER][WARN] device-extension query failed: {ex.Message}");
            }
        }

        private bool TryInitializeUpscaler()
        {
            if (_upscalerInitAttempted &&
                _nativeUpscaler is not null &&
                (_upscalerInitWidth != _extent.Width || _upscalerInitHeight != _extent.Height))
            {
                // Temporal upscaler contexts are output-size dependent. Recreate the
                // native context after a window/swapchain resolution change.
                DestroyUpscalerOutput();
                _nativeUpscaler.Dispose();
                _nativeUpscaler = null;
                _upscalerInitAttempted = false;
                _upscalerOutputReset = true;
            }

            if (_upscalerInitAttempted)
            {
                return _nativeUpscaler is not null;
            }

            _upscalerInitAttempted = true;
            if (_upscalerRequiredExtensionMissing)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] required Vulkan extension negotiation failed; using normal Vulkan presentation.");
                return false;
            }

            var provider = EnsureUpscalerProviderLoaded();
            if (provider is null)
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER] provider DLL not present; Vulkan presenter fallback remains active.");
                return false;
            }

            _vk.GetPhysicalDeviceProperties(_physicalDevice, out var properties);
            var desc = new NativeUpscalerInitDesc
            {
                Size = (uint)sizeof(NativeUpscalerInitDesc),
                AbiVersion = UpscalerAbiVersion,
                Instance = (ulong)_instance.Handle,
                PhysicalDevice = (ulong)_physicalDevice.Handle,
                Device = (ulong)_device.Handle,
                Queue = (ulong)_queue.Handle,
                QueueFamilyIndex = _queueFamilyIndex,
                VendorId = properties.VendorID,
                OutputWidth = _extent.Width,
                OutputHeight = _extent.Height,
            };

            if (!provider.Initialize(desc))
            {
                Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider initialization failed; using normal Vulkan presentation.");
                provider.Dispose();
                _nativeUpscaler = null;
                return false;
            }

            _upscalerInitWidth = _extent.Width;
            _upscalerInitHeight = _extent.Height;
            Console.Error.WriteLine(
                $"[V74.0.64][UPSCALER] initialized backend={RequestedUpscalerBackend()} " +
                $"quality={RequestedUpscalerQuality()} caps={provider.Capabilities} output={_extent.Width}x{_extent.Height}");
            return true;
        }

        private bool TryEnsureUpscalerOutput(GuestImageResource source)
        {
            var formatProperties = default(FormatProperties);
            _vk.GetPhysicalDeviceFormatProperties(_physicalDevice, source.Format, out formatProperties);
            if ((formatProperties.OptimalTilingFeatures & FormatFeatureFlags.StorageImageBit) == 0)
            {
                return false;
            }

            if (_upscalerOutput is not null &&
                _upscalerOutput.Width == _extent.Width &&
                _upscalerOutput.Height == _extent.Height &&
                _upscalerOutput.Format == source.Format)
            {
                return true;
            }

            DestroyUpscalerOutput();
            var imageInfo = new ImageCreateInfo
            {
                SType = StructureType.ImageCreateInfo,
                ImageType = ImageType.Type2D,
                Format = source.Format,
                Extent = new Extent3D(_extent.Width, _extent.Height, 1),
                MipLevels = 1,
                ArrayLayers = 1,
                Samples = SampleCountFlags.Count1Bit,
                Tiling = ImageTiling.Optimal,
                Usage = ImageUsageFlags.StorageBit |
                        ImageUsageFlags.SampledBit |
                        ImageUsageFlags.TransferSrcBit |
                        ImageUsageFlags.TransferDstBit,
                SharingMode = SharingMode.Exclusive,
                InitialLayout = ImageLayout.Undefined,
            };
            Check(_vk.CreateImage(_device, &imageInfo, null, out var image), "vkCreateImage(upscaler output)");
            _vk.GetImageMemoryRequirements(_device, image, out var requirements);
            var allocationInfo = new MemoryAllocateInfo
            {
                SType = StructureType.MemoryAllocateInfo,
                AllocationSize = requirements.Size,
                MemoryTypeIndex = FindMemoryType(requirements.MemoryTypeBits, MemoryPropertyFlags.DeviceLocalBit),
            };
            Check(_vk.AllocateMemory(_device, &allocationInfo, null, out var memory), "vkAllocateMemory(upscaler output)");
            Check(_vk.BindImageMemory(_device, image, memory, 0), "vkBindImageMemory(upscaler output)");
            var viewInfo = new ImageViewCreateInfo
            {
                SType = StructureType.ImageViewCreateInfo,
                Image = image,
                ViewType = ImageViewType.Type2D,
                Format = source.Format,
                SubresourceRange = ColorSubresourceRange(),
            };
            Check(_vk.CreateImageView(_device, &viewInfo, null, out var view), "vkCreateImageView(upscaler output)");
            _upscalerOutput = new GuestImageResource
            {
                Address = 0,
                Width = _extent.Width,
                Height = _extent.Height,
                LogicalWidth = _extent.Width,
                LogicalHeight = _extent.Height,
                MipLevels = 1,
                Format = source.Format,
                Image = image,
                Memory = memory,
                View = view,
                Initialized = false,
                SupportsStorageUsage = true,
                Layout = ImageLayout.Undefined,
            };
            _upscalerOutputReset = true;
            SetDebugName(ObjectType.Image, image.Handle, "SharpEmu host-upscaler output");
            return true;
        }

        private GuestDepthResource? ResolveUpscalerDepth()
        {
            var requested = ParseAddressEnvironment("SHARPEMU_VK_UPSCALER_DEPTH_ADDR");
            if (requested == 0)
            {
                return null;
            }

            foreach (var depth in _guestDepthImages.Values)
            {
                if (depth.Address == requested || depth.ReadAddress == requested || depth.WriteAddress == requested)
                {
                    return depth;
                }
            }

            return null;
        }

        private GuestImageResource? ResolveUpscalerMotionVectors()
        {
            var requested = ParseAddressEnvironment("SHARPEMU_VK_UPSCALER_MOTION_ADDR");
            return requested != 0 && _guestImages.TryGetValue(requested, out var image)
                ? image
                : null;
        }

        private bool TryRecordUpscaledGuestImage(uint imageIndex, GuestImageResource source)
        {
            var requestedBackend = RequestedUpscalerBackend();
            var requestedQuality = RequestedUpscalerQuality();
            var sourceIsNativeSize = source.Width == _extent.Width && source.Height == _extent.Height;
            if (requestedBackend == HostUpscalerBackend.Off ||
                source.Width == 0 || source.Height == 0 ||
                (requestedQuality == HostUpscalerQuality.NativeAa && !sourceIsNativeSize) ||
                (requestedQuality != HostUpscalerQuality.NativeAa && sourceIsNativeSize))
            {
                return false;
            }

            if (!TryInitializeUpscaler() || _nativeUpscaler is null || !TryEnsureUpscalerOutput(source) || _upscalerOutput is null)
            {
                return false;
            }

            var caps = _nativeUpscaler.Capabilities;
            var selectedBackend = requestedBackend;
            if (selectedBackend == HostUpscalerBackend.Auto)
            {
                _vk.GetPhysicalDeviceProperties(_physicalDevice, out var properties);
                selectedBackend = properties.VendorID == 0x10DE && (caps & NativeUpscalerCapabilities.Dlss) != 0
                    ? HostUpscalerBackend.Dlss
                    : (caps & NativeUpscalerCapabilities.Fsr) != 0
                        ? HostUpscalerBackend.Fsr
                        : HostUpscalerBackend.Off;
            }

            if (selectedBackend == HostUpscalerBackend.Dlss && (caps & NativeUpscalerCapabilities.Dlss) == 0 ||
                selectedBackend == HostUpscalerBackend.Fsr && (caps & NativeUpscalerCapabilities.Fsr) == 0 ||
                selectedBackend == HostUpscalerBackend.Off)
            {
                return false;
            }

            var depth = ResolveUpscalerDepth();
            var motion = ResolveUpscalerMotionVectors();
            var temporalInputsReady = depth is not null && motion is not null;
            if ((caps & NativeUpscalerCapabilities.Temporal) != 0 &&
                (caps & NativeUpscalerCapabilities.ColorOnly) == 0 &&
                !temporalInputsReady)
            {
                if (!_upscalerFallbackLogged)
                {
                    _upscalerFallbackLogged = true;
                    Console.Error.WriteLine(
                        "[V74.0.64][UPSCALER][WARN] temporal backend requires depth + motion vectors. " +
                        "Set SHARPEMU_VK_UPSCALER_DEPTH_ADDR and SHARPEMU_VK_UPSCALER_MOTION_ADDR after identifying the guest targets; normal Vulkan blit remains active.");
                }
                return false;
            }

            // The native API descriptors describe resources as compute-readable.
            // Make that true in Vulkan before crossing the ABI instead of relying
            // on a vendor SDK to guess SharpEmu's tracked guest-image layouts.
            if (!source.Initialized || source.InitialUploadPending)
            {
                return false;
            }
            RecordGuestImageForSampling(source, PipelineStageFlags.ComputeShaderBit);
            if (source.Layout != ImageLayout.ShaderReadOnlyOptimal)
            {
                return false;
            }

            if ((caps & NativeUpscalerCapabilities.Temporal) != 0 &&
                (caps & NativeUpscalerCapabilities.ColorOnly) == 0)
            {
                if (depth is null || motion is null ||
                    !depth.Initialized || !motion.Initialized || motion.InitialUploadPending ||
                    ReferenceEquals(source, motion))
                {
                    return false;
                }

                RecordGuestDepthForSampling(depth, PipelineStageFlags.ComputeShaderBit);
                RecordGuestImageForSampling(motion, PipelineStageFlags.ComputeShaderBit);
                if (depth.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                    motion.Layout != ImageLayout.ShaderReadOnlyOptimal)
                {
                    return false;
                }
            }

            var output = _upscalerOutput;
            var outputToGeneral = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask = output.Initialized ? AccessFlags.ShaderReadBit | AccessFlags.TransferReadBit : AccessFlags.None,
                DstAccessMask = AccessFlags.ShaderWriteBit,
                OldLayout = output.Initialized ? output.Layout : ImageLayout.Undefined,
                NewLayout = ImageLayout.General,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = output.Image,
                SubresourceRange = ColorSubresourceRange(),
            };
            _vk.CmdPipelineBarrier(
                _commandBuffer,
                PipelineStageFlags.AllCommandsBit,
                PipelineStageFlags.ComputeShaderBit,
                0,
                0,
                null,
                0,
                null,
                1,
                &outputToGeneral);
            output.Layout = ImageLayout.General;
            output.Initialized = true;

            var now = Stopwatch.GetTimestamp();
            var frameTimeMilliseconds = _upscalerLastFrameTimestamp == 0
                ? 16.6667f
                : (float)((now - _upscalerLastFrameTimestamp) * 1000.0 / Stopwatch.Frequency);
            _upscalerLastFrameTimestamp = now;

            var dispatch = new NativeUpscalerDispatchDesc
            {
                Size = (uint)sizeof(NativeUpscalerDispatchDesc),
                AbiVersion = UpscalerAbiVersion,
                Backend = (int)selectedBackend,
                Quality = (int)requestedQuality,
                CommandBuffer = (ulong)_commandBuffer.Handle,
                ColorImage = (ulong)source.Image.Handle,
                ColorView = (ulong)source.View.Handle,
                ColorFormat = (uint)source.Format,
                ColorWidth = source.Width,
                ColorHeight = source.Height,
                ColorLayout = (int)source.Layout,
                OutputImage = (ulong)output.Image.Handle,
                OutputView = (ulong)output.View.Handle,
                OutputFormat = (uint)output.Format,
                OutputWidth = output.Width,
                OutputHeight = output.Height,
                OutputLayout = (int)output.Layout,
                DepthImage = depth is null ? 0UL : (ulong)depth.Image.Handle,
                DepthView = depth is null ? 0UL : (ulong)depth.View.Handle,
                DepthFormat = depth is null ? 0u : (uint)Format.D32Sfloat,
                DepthWidth = depth?.Width ?? 0,
                DepthHeight = depth?.Height ?? 0,
                DepthLayout = depth is null ? 0 : (int)depth.Layout,
                MotionImage = motion is null ? 0UL : (ulong)motion.Image.Handle,
                MotionView = motion is null ? 0UL : (ulong)motion.View.Handle,
                MotionFormat = motion is null ? 0u : (uint)motion.Format,
                MotionWidth = motion?.Width ?? 0,
                MotionHeight = motion?.Height ?? 0,
                MotionLayout = motion is null ? 0 : (int)motion.Layout,
                JitterX = ReadUpscalerFloat("SHARPEMU_VK_UPSCALER_JITTER_X", 0f),
                JitterY = ReadUpscalerFloat("SHARPEMU_VK_UPSCALER_JITTER_Y", 0f),
                MotionVectorScaleX = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_X",
                    motion?.Width ?? source.Width),
                MotionVectorScaleY = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_Y",
                    motion?.Height ?? source.Height),
                Sharpness = RequestedUpscalerSharpness(),
                FrameTimeMilliseconds = Math.Clamp(frameTimeMilliseconds, 1f, 1000f),
                Reset = _upscalerOutputReset ? 1u : 0u,
                Flags = 0,
                FrameId = ++_upscalerFrameId,
            };

            BeginDebugLabel(_commandBuffer, $"SharpEmu host upscaler {selectedBackend}");
            var dispatched = _nativeUpscaler.Dispatch(dispatch);
            EndDebugLabel(_commandBuffer);
            if (!dispatched)
            {
                _upscalerOutputReset = true;
                return false;
            }

            _upscalerOutputReset = false;
            // Provider contract: output is returned in GENERAL and input resources
            // are restored to the layouts passed in the dispatch descriptor.
            output.Layout = ImageLayout.General;
            var outputToRead = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask = AccessFlags.ShaderWriteBit,
                DstAccessMask = AccessFlags.ShaderReadBit,
                OldLayout = ImageLayout.General,
                NewLayout = ImageLayout.ShaderReadOnlyOptimal,
                SrcQueueFamilyIndex = Vk.QueueFamilyIgnored,
                DstQueueFamilyIndex = Vk.QueueFamilyIgnored,
                Image = output.Image,
                SubresourceRange = ColorSubresourceRange(),
            };
            _vk.CmdPipelineBarrier(
                _commandBuffer,
                PipelineStageFlags.ComputeShaderBit,
                GuestImageShaderReadStages,
                0,
                0,
                null,
                0,
                null,
                1,
                &outputToRead);
            output.Layout = ImageLayout.ShaderReadOnlyOptimal;

            // Reuse the mature presentation path for colorspace conversion,
            // letterbox/cover logic, diagnostics and final swapchain layout.
            RecordGuestImageBlit(imageIndex, output);
            return true;
        }

        private void DestroyUpscalerOutput()
        {
            if (_upscalerOutput is null || _device.Handle == 0)
            {
                _upscalerOutput = null;
                return;
            }

            if (_upscalerOutput.View.Handle != 0)
            {
                _vk.DestroyImageView(_device, _upscalerOutput.View, null);
            }
            if (_upscalerOutput.Image.Handle != 0)
            {
                _vk.DestroyImage(_device, _upscalerOutput.Image, null);
            }
            if (_upscalerOutput.Memory.Handle != 0)
            {
                _vk.FreeMemory(_device, _upscalerOutput.Memory, null);
            }
            _upscalerOutput = null;
            _upscalerOutputReset = true;
        }

        private void DisposeUpscaler()
        {
            DestroyUpscalerOutput();
            _nativeUpscaler?.Dispose();
            _nativeUpscaler = null;
            _upscalerInitAttempted = false;
            _upscalerInitWidth = 0;
            _upscalerInitHeight = 0;
        }
    }
}
