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
        // V74.0.67.2.10.2 lazy last-error + init-size retry
        private uint _upscalerInitFailedWidth;
        private uint _upscalerInitFailedHeight;
        private string _upscalerInitFailureReason = string.Empty;

        // V74.0.67.2.13 bounded provider activation retry
        private long _upscalerInitNextRetryTick;
        private int _upscalerInitRetryCount;
        private const long V74067213ProviderRetryMs = 2000;
        // V74.0.67 runtime proof counters. A frame is counted as fallback only
        // when an upscaler was requested and this method returns to the normal
        // Vulkan presentation path.
        private ulong _upscalerRuntimeDlssDispatches;
        private ulong _upscalerRuntimeFsrDispatches;
        private ulong _upscalerRuntimeFallbackFrames;
        private ulong _upscalerRuntimeDispatchFailures;
        private ulong _upscalerRuntimeLastReportedTotal;
        private string _upscalerRuntimeLastSignature = string.Empty;
        private const ulong UpscalerRuntimePeriodicReportFrames = 60;
        private const int MaxNativeUpscalerExtensions = 48;

        private const int MaxUpscalerTemporalBindings = 512;
        private long _upscalerTemporalBindingSerial;
        private readonly Dictionary<ulong, UpscalerTemporalBinding> _upscalerTemporalBindings = new();
        private readonly Dictionary<ulong, long> _upscalerTemporalAuditLastLoggedSerial = new();
        private readonly HashSet<ulong> _upscalerTemporalAuditMissingLogged = new();

        private readonly record struct UpscalerTemporalSibling(
            ulong Address,
            uint Width,
            uint Height,
            Format Format);

        private sealed record UpscalerTemporalBinding(
            ulong ColorAddress,
            ulong DepthAddress,
            ulong ShaderAddress,
            long Serial,
            UpscalerTemporalSibling[] Siblings);

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
            FrameGeneration = 1u << 4,
            MultiFrameGeneration = 1u << 5,
            DlssTransformer = 1u << 6,
            Streamline = 1u << 7,
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
            // ABI v1 extension (V74.0.98.4): fields are appended so legacy
            // providers that only consume the original prefix remain valid.
            public uint DlssModel;
            public uint FrameGenerationEnabled;
            public uint FrameGenerationMultiplier;
            public uint FrameGenerationReserved;
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
        private unsafe delegate int PrepareFrameGenerationDelegate(NativeUpscalerDispatchDesc* desc);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate uint CapabilitiesDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void ShutdownDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate nint GetLastErrorDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int FrameGenerationHooksReadyDelegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkCreateInstanceProxyDelegate(
            InstanceCreateInfo* createInfo, AllocationCallbacks* allocator, ulong* instance);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkCreateDeviceProxyDelegate(
            ulong physicalDevice, DeviceCreateInfo* createInfo, AllocationCallbacks* allocator, ulong* device);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkCreateWin32SurfaceProxyDelegate(
            ulong instance, nint hwnd, ulong* surface);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate void VkDestroySurfaceProxyDelegate(
            ulong instance, ulong surface, AllocationCallbacks* allocator);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkCreateSwapchainProxyDelegate(
            ulong device, SwapchainCreateInfoKHR* createInfo, AllocationCallbacks* allocator, ulong* swapchain);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate void VkDestroySwapchainProxyDelegate(
            ulong device, ulong swapchain, AllocationCallbacks* allocator);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkGetSwapchainImagesProxyDelegate(
            ulong device, ulong swapchain, uint* count, ulong* images);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkAcquireNextImageProxyDelegate(
            ulong device, ulong swapchain, ulong timeout, ulong semaphore, ulong fence, uint* imageIndex);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int VkQueuePresentProxyDelegate(
            ulong queue, PresentInfoKHR* presentInfo);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int VkDeviceWaitIdleProxyDelegate(ulong device);


        private sealed class NativeVulkanUpscaler : IDisposable
        {
            private readonly nint _library;
            private readonly GetExtensionListDelegate? _instanceExtensions;
            private readonly GetExtensionListDelegate? _deviceExtensions;
            private readonly InitDelegate _initialize;
            private readonly DispatchDelegate _dispatch;
            private readonly PrepareFrameGenerationDelegate? _prepareFrameGeneration;
            private readonly CapabilitiesDelegate _capabilities;
            private readonly ShutdownDelegate _shutdown;
            private readonly FrameGenerationHooksReadyDelegate? _frameGenerationHooksReady;
            private readonly VkCreateInstanceProxyDelegate? _vkCreateInstanceProxy;
            private readonly VkCreateDeviceProxyDelegate? _vkCreateDeviceProxy;
            private readonly VkCreateWin32SurfaceProxyDelegate? _vkCreateWin32SurfaceProxy;
            private readonly VkDestroySurfaceProxyDelegate? _vkDestroySurfaceProxy;
            private readonly VkCreateSwapchainProxyDelegate? _vkCreateSwapchainProxy;
            private readonly VkDestroySwapchainProxyDelegate? _vkDestroySwapchainProxy;
            private readonly VkGetSwapchainImagesProxyDelegate? _vkGetSwapchainImagesProxy;
            private readonly VkAcquireNextImageProxyDelegate? _vkAcquireNextImageProxy;
            private readonly VkQueuePresentProxyDelegate? _vkQueuePresentProxy;
            private readonly VkDeviceWaitIdleProxyDelegate? _vkDeviceWaitIdleProxy;
            private GetLastErrorDelegate? _getLastError;
            private bool _lastErrorExportResolved;
            private bool _initialized;
            private bool _disposed;

            public int LastInitializeResult { get; private set; }
            public bool IsInitialized => _initialized;

            private NativeVulkanUpscaler(
                nint library,
                GetExtensionListDelegate? instanceExtensions,
                GetExtensionListDelegate? deviceExtensions,
                InitDelegate initialize,
                DispatchDelegate dispatch,
                PrepareFrameGenerationDelegate? prepareFrameGeneration,
                CapabilitiesDelegate capabilities,
                ShutdownDelegate shutdown,
                FrameGenerationHooksReadyDelegate? frameGenerationHooksReady,
                VkCreateInstanceProxyDelegate? vkCreateInstanceProxy,
                VkCreateDeviceProxyDelegate? vkCreateDeviceProxy,
                VkCreateWin32SurfaceProxyDelegate? vkCreateWin32SurfaceProxy,
                VkDestroySurfaceProxyDelegate? vkDestroySurfaceProxy,
                VkCreateSwapchainProxyDelegate? vkCreateSwapchainProxy,
                VkDestroySwapchainProxyDelegate? vkDestroySwapchainProxy,
                VkGetSwapchainImagesProxyDelegate? vkGetSwapchainImagesProxy,
                VkAcquireNextImageProxyDelegate? vkAcquireNextImageProxy,
                VkQueuePresentProxyDelegate? vkQueuePresentProxy,
                VkDeviceWaitIdleProxyDelegate? vkDeviceWaitIdleProxy)
            {
                _library = library;
                _instanceExtensions = instanceExtensions;
                _deviceExtensions = deviceExtensions;
                _initialize = initialize;
                _dispatch = dispatch;
                _prepareFrameGeneration = prepareFrameGeneration;
                _capabilities = capabilities;
                _shutdown = shutdown;
                _frameGenerationHooksReady = frameGenerationHooksReady;
                _vkCreateInstanceProxy = vkCreateInstanceProxy;
                _vkCreateDeviceProxy = vkCreateDeviceProxy;
                _vkCreateWin32SurfaceProxy = vkCreateWin32SurfaceProxy;
                _vkDestroySurfaceProxy = vkDestroySurfaceProxy;
                _vkCreateSwapchainProxy = vkCreateSwapchainProxy;
                _vkDestroySwapchainProxy = vkDestroySwapchainProxy;
                _vkGetSwapchainImagesProxy = vkGetSwapchainImagesProxy;
                _vkAcquireNextImageProxy = vkAcquireNextImageProxy;
                _vkQueuePresentProxy = vkQueuePresentProxy;
                _vkDeviceWaitIdleProxy = vkDeviceWaitIdleProxy;
            }

            public NativeUpscalerCapabilities Capabilities =>
                (NativeUpscalerCapabilities)_capabilities();

            public bool HasLastErrorExport
            {
                get
                {
                    EnsureLastErrorExport();
                    return _getLastError is not null;
                }
            }

            public string LastError
            {
                get
                {
                    EnsureLastErrorExport();
                    if (_getLastError is null)
                    {
                        return string.Empty;
                    }

                    var pointer = _getLastError();
                    if (pointer == 0)
                    {
                        return string.Empty;
                    }

                    return (Marshal.PtrToStringUTF8(pointer) ?? string.Empty)
                        .Replace('\r', ' ')
                        .Replace('\n', ' ')
                        .Trim();
                }
            }

            private void EnsureLastErrorExport()
            {
                if (_lastErrorExportResolved)
                {
                    return;
                }

                _lastErrorExportResolved = true;
                if (NativeLibrary.TryGetExport(
                        _library,
                        "sharpemu_vk_upscaler_get_last_error",
                        out var symbol))
                {
                    _getLastError =
                        Marshal.GetDelegateForFunctionPointer<GetLastErrorDelegate>(
                            symbol);
                }
            }

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

                // V74.0.67.1 provider bootstrap/load diagnostics.
                foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!File.Exists(candidate))
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.1][UPSCALER][LOAD] candidate={candidate} exists=0 loaded=0");
                        continue;
                    }

                    if (!NativeLibrary.TryLoad(candidate, out var library))
                    {
                        Console.Error.WriteLine(
                            $"[V74.0.67.1][UPSCALER][LOAD] candidate={candidate} exists=1 loaded=0");
                        continue;
                    }

                    Console.Error.WriteLine(
                        $"[V74.0.67.1][UPSCALER][LOAD] candidate={candidate} exists=1 loaded=1");

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

                        _ = TryGet(library, "sharpemu_vk_upscaler_prepare_frame_generation", out PrepareFrameGenerationDelegate? prepareFrameGeneration);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_instance_extensions", out GetExtensionListDelegate? instanceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_get_device_extensions", out GetExtensionListDelegate? deviceExtensions);
                        _ = TryGet(library, "sharpemu_vk_upscaler_frame_generation_hooks_ready", out FrameGenerationHooksReadyDelegate? fgHooksReady);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_create_instance", out VkCreateInstanceProxyDelegate? vkCreateInstanceProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_create_device", out VkCreateDeviceProxyDelegate? vkCreateDeviceProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_create_win32_surface", out VkCreateWin32SurfaceProxyDelegate? vkCreateWin32SurfaceProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_destroy_surface", out VkDestroySurfaceProxyDelegate? vkDestroySurfaceProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_create_swapchain", out VkCreateSwapchainProxyDelegate? vkCreateSwapchainProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_destroy_swapchain", out VkDestroySwapchainProxyDelegate? vkDestroySwapchainProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_get_swapchain_images", out VkGetSwapchainImagesProxyDelegate? vkGetSwapchainImagesProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_acquire_next_image", out VkAcquireNextImageProxyDelegate? vkAcquireNextImageProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_queue_present", out VkQueuePresentProxyDelegate? vkQueuePresentProxy);
                        _ = TryGet(library, "sharpemu_vk_upscaler_vk_device_wait_idle", out VkDeviceWaitIdleProxyDelegate? vkDeviceWaitIdleProxy);
                        Console.Error.WriteLine($"[V74.0.64][UPSCALER] native provider loaded: {candidate}");
                        return new NativeVulkanUpscaler(
                            library, instanceExtensions, deviceExtensions, initialize!, dispatch!,
                            prepareFrameGeneration, capabilities!, shutdown!, fgHooksReady, vkCreateInstanceProxy,
                            vkCreateDeviceProxy, vkCreateWin32SurfaceProxy, vkDestroySurfaceProxy,
                            vkCreateSwapchainProxy, vkDestroySwapchainProxy, vkGetSwapchainImagesProxy,
                            vkAcquireNextImageProxy, vkQueuePresentProxy, vkDeviceWaitIdleProxy);
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
                // V74.0.67.2.8 strict provider extension negotiation
                //
                // Native providers use negative values to report a failed NGX
                // extension/support query. Treating every <=0 result as "no
                // extensions" silently allowed VkInstance/VkDevice creation to
                // continue without a valid provider contract.
                var length = getter(instance, physicalDevice, buffer, capacity);
                if (length < 0)
                {
                    throw new InvalidOperationException(
                        $"native Vulkan upscaler extension query failed: result={length}");
                }
                if (length == 0)
                {
                    return [];
                }
                if (length >= capacity)
                {
                    throw new InvalidOperationException(
                        $"native Vulkan upscaler extension list exceeds capacity: result={length} capacity={capacity}");
                }

                var text = Encoding.UTF8.GetString(new ReadOnlySpan<byte>(buffer, length));
                return text.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            }

            public unsafe bool Initialize(NativeUpscalerInitDesc desc)
            {
                if (_initialized)
                {
                    LastInitializeResult = 0;
                    return true;
                }

                var result = _initialize(&desc);
                LastInitializeResult = result;
                _initialized = result == 0;
                return _initialized;
            }

            public unsafe bool Dispatch(NativeUpscalerDispatchDesc desc) =>
                _initialized && _dispatch(&desc) == 0;

            public unsafe bool PrepareFrameGeneration(NativeUpscalerDispatchDesc desc) =>
                _prepareFrameGeneration is not null && _prepareFrameGeneration(&desc) == 0;

            public bool HasFrameGenerationPrepareExport => _prepareFrameGeneration is not null;

            public bool FrameGenerationHooksReady =>
                RequestedDlssFrameGeneration() &&
                _frameGenerationHooksReady is not null &&
                _frameGenerationHooksReady() != 0;

            public unsafe bool TryCreateInstance(InstanceCreateInfo* createInfo, out Instance instance)
            {
                instance = default;
                if (!FrameGenerationHooksReady || _vkCreateInstanceProxy is null) return false;
                ulong handle = 0;
                var result = (Result)_vkCreateInstanceProxy(createInfo, null, &handle);
                if (result != Result.Success)
                {
                    throw new InvalidOperationException($"Streamline vkCreateInstance proxy failed with {result}.");
                }
                instance = new Instance((nint)handle);
                return true;
            }

            public unsafe bool TryCreateDevice(PhysicalDevice physicalDevice, DeviceCreateInfo* createInfo, out Device device)
            {
                device = default;
                if (!FrameGenerationHooksReady || _vkCreateDeviceProxy is null) return false;
                ulong handle = 0;
                var result = (Result)_vkCreateDeviceProxy((ulong)physicalDevice.Handle, createInfo, null, &handle);
                if (result != Result.Success)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.101][DLSS-G] manual Vulkan device creation/registration failed with {result}; " +
                        "falling back to the host Vulkan device with Frame Generation disabled for this run.");
                    return false;
                }
                device = new Device((nint)handle);
                return true;
            }

            public unsafe bool TryCreateWin32Surface(Instance instance, nint hwnd, out SurfaceKHR surface)
            {
                surface = default;
                if (!FrameGenerationHooksReady || hwnd == 0 || _vkCreateWin32SurfaceProxy is null) return false;
                ulong handle = 0;
                var result = (Result)_vkCreateWin32SurfaceProxy((ulong)instance.Handle, hwnd, &handle);
                if (result != Result.Success)
                {
                    throw new InvalidOperationException($"Streamline vkCreateWin32SurfaceKHR proxy failed with {result}.");
                }
                surface = new SurfaceKHR(handle);
                return true;
            }

            public unsafe bool TryDestroySurface(Instance instance, SurfaceKHR surface)
            {
                if (!FrameGenerationHooksReady || _vkDestroySurfaceProxy is null) return false;
                _vkDestroySurfaceProxy((ulong)instance.Handle, surface.Handle, null);
                return true;
            }

            public unsafe bool TryCreateSwapchain(Device device, SwapchainCreateInfoKHR* createInfo, out SwapchainKHR swapchain)
            {
                swapchain = default;
                if (!FrameGenerationHooksReady || _vkCreateSwapchainProxy is null) return false;
                ulong handle = 0;
                var result = (Result)_vkCreateSwapchainProxy((ulong)device.Handle, createInfo, null, &handle);
                if (result != Result.Success) throw new InvalidOperationException($"Streamline vkCreateSwapchainKHR proxy failed with {result}.");
                swapchain = new SwapchainKHR(handle);
                return true;
            }

            public unsafe bool TryGetSwapchainImages(Device device, SwapchainKHR swapchain, uint* count, Image* images, out Result result)
            {
                result = Result.Success;
                if (!FrameGenerationHooksReady || _vkGetSwapchainImagesProxy is null) return false;
                result = (Result)_vkGetSwapchainImagesProxy((ulong)device.Handle, swapchain.Handle, count, (ulong*)images);
                return true;
            }

            public unsafe bool TryAcquireNextImage(Device device, SwapchainKHR swapchain, ulong timeout, Silk.NET.Vulkan.Semaphore semaphore, Fence fence, uint* imageIndex, out Result result)
            {
                result = Result.Success;
                if (!FrameGenerationHooksReady || _vkAcquireNextImageProxy is null) return false;
                result = (Result)_vkAcquireNextImageProxy((ulong)device.Handle, swapchain.Handle, timeout, semaphore.Handle, fence.Handle, imageIndex);
                return true;
            }

            public unsafe bool TryQueuePresent(Queue queue, PresentInfoKHR* presentInfo, out Result result)
            {
                result = Result.Success;
                if (!FrameGenerationHooksReady || _vkQueuePresentProxy is null) return false;
                result = (Result)_vkQueuePresentProxy((ulong)queue.Handle, presentInfo);
                return true;
            }

            public unsafe bool TryDestroySwapchain(Device device, SwapchainKHR swapchain)
            {
                if (!FrameGenerationHooksReady || _vkDestroySwapchainProxy is null) return false;
                _vkDestroySwapchainProxy((ulong)device.Handle, swapchain.Handle, null);
                return true;
            }

            public bool TryDeviceWaitIdle(Device device, out Result result)
            {
                result = Result.Success;
                if (!FrameGenerationHooksReady || _vkDeviceWaitIdleProxy is null) return false;
                result = (Result)_vkDeviceWaitIdleProxy((ulong)device.Handle);
                return true;
            }

            public void Dispose()
            {
                if (_disposed)
                {
                    return;
                }

                _disposed = true;
                // Streamline can be initialized by the Vulkan manual-hook path
                // before NGX Super Resolution initialization completes. Always
                // invoke the provider shutdown export while the Vulkan device is
                // still alive; the native shutdown routine is idempotent.
                _shutdown();
                _initialized = false;

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

        private static uint RequestedDlssModel()
        {
            var value = Environment.GetEnvironmentVariable("SHARPEMU_DLSS_MODEL")?.Trim();
            return value?.ToLowerInvariant() switch
            {
                "3" or "dlss3" or "legacy" or "cnn" => 3u,
                _ => 4u,
            };
        }

        private static bool RequestedDlssFrameGeneration() =>
            ReadUpscalerBool("SHARPEMU_DLSS_FRAME_GENERATION");

        private static uint RequestedDlssFrameMultiplier()
        {
            var model = RequestedDlssModel();
            if (model <= 3)
            {
                return 2;
            }

            var text = Environment.GetEnvironmentVariable("SHARPEMU_DLSS_FRAME_MULTIPLIER")?.Trim();
            if (text is not null && text.EndsWith("x", StringComparison.OrdinalIgnoreCase))
            {
                text = text[..^1];
            }

            return uint.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
                ? Math.Clamp(value, 2u, 4u)
                : 2u;
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

        private static bool ReadUpscalerBool(string name, bool fallback = false)
        {
            var text = Environment.GetEnvironmentVariable(name)?.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                return fallback;
            }

            return text.Equals("1", StringComparison.OrdinalIgnoreCase) ||
                text.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                text.Equals("yes", StringComparison.OrdinalIgnoreCase) ||
                text.Equals("on", StringComparison.OrdinalIgnoreCase);
        }

        private static bool UpscalerTemporalAuditEnabled() =>
            ReadUpscalerBool("SHARPEMU_VK_UPSCALER_TEMPORAL_AUDIT");

        private Result UpscalerAwareDeviceWaitIdle()
        {
            var provider = EnsureUpscalerProviderLoaded();
            if (provider is not null && provider.TryDeviceWaitIdle(_device, out var result))
            {
                return result;
            }

            return _vk.DeviceWaitIdle(_device);
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
                        Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider requested more than 48 Vulkan instance extensions; provider disabled.");
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
                        Console.Error.WriteLine("[V74.0.64][UPSCALER][WARN] native provider requested more than 48 Vulkan device extensions; provider disabled.");
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

        private void RecordUpscalerInitFailure(
            uint outputWidth,
            uint outputHeight,
            string reason)
        {
            _upscalerInitFailedWidth = outputWidth;
            _upscalerInitFailedHeight = outputHeight;
            _upscalerInitFailureReason = string.IsNullOrWhiteSpace(reason)
                ? "unspecified"
                : reason;
        }

        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;

            var retryNow = Environment.TickCount64;
            if (_upscalerInitAttempted &&
                !_upscalerRequiredExtensionMissing &&
                (_nativeUpscaler is null || !_nativeUpscaler.IsInitialized))
            {
                var failedSizeChanged =
                    _upscalerInitFailedWidth != outputWidth ||
                    _upscalerInitFailedHeight != outputHeight;
                var retryDelayElapsed =
                    _upscalerInitNextRetryTick == 0 ||
                    unchecked(retryNow - _upscalerInitNextRetryTick) >= 0;

                if (!failedSizeChanged && !retryDelayElapsed)
                {
                    return false;
                }

                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=retry " +
                    $"attempt={_upscalerInitRetryCount + 1} " +
                    $"previous={_upscalerInitFailedWidth}x{_upscalerInitFailedHeight} " +
                    $"requested={outputWidth}x{outputHeight} " +
                    $"size_changed={(failedSizeChanged ? 1 : 0)} " +
                    $"previous_reason={_upscalerInitFailureReason}");

                _upscalerInitAttempted = false;
                _upscalerOutputReset = true;
            }

            if (_upscalerInitAttempted &&
                _nativeUpscaler is { IsInitialized: true } &&
                (_upscalerInitWidth != outputWidth || _upscalerInitHeight != outputHeight))
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
                return _nativeUpscaler is { IsInitialized: true };
            }

            _upscalerInitAttempted = true;
            if (_upscalerRequiredExtensionMissing)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "required_vulkan_extension_negotiation_failed");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result=managed output={outputWidth}x{outputHeight} " +
                    $"last_error=required_vulkan_extension_negotiation_failed");
                return false;
            }

            var provider = EnsureUpscalerProviderLoaded();
            if (provider is null)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "provider_dll_not_loaded");
                _upscalerInitRetryCount++;
                _upscalerInitNextRetryTick =
                    retryNow + V74067213ProviderRetryMs;
                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"attempt={_upscalerInitRetryCount} result=managed " +
                    $"output={outputWidth}x{outputHeight} " +
                    $"retry_ms={V74067213ProviderRetryMs} " +
                    $"last_error=provider_dll_not_loaded");
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
                OutputWidth = outputWidth,
                OutputHeight = outputHeight,
            };

            if (!provider.Initialize(desc))
            {
                var nativeError = provider.LastError;
                if (string.IsNullOrWhiteSpace(nativeError))
                {
                    nativeError =
                        "native_provider_returned_failure_without_error_text";
                }

                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    nativeError);
                _upscalerInitRetryCount++;
                _upscalerInitNextRetryTick =
                    retryNow + V74067213ProviderRetryMs;

                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"attempt={_upscalerInitRetryCount} " +
                    $"result={provider.LastInitializeResult} " +
                    $"output={outputWidth}x{outputHeight} provider_loaded=1 " +
                    $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)} " +
                    $"retry_ms={V74067213ProviderRetryMs} " +
                    $"last_error={nativeError}");

                return false;
            }

            _upscalerInitWidth = outputWidth;
            _upscalerInitHeight = outputHeight;
            _upscalerInitFailedWidth = 0;
            _upscalerInitFailedHeight = 0;
            _upscalerInitFailureReason = string.Empty;
            _upscalerInitNextRetryTick = 0;
            _upscalerInitRetryCount = 0;

            Console.Error.WriteLine(
                $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active " +
                $"result=0 output={outputWidth}x{outputHeight} " +
                $"caps=0x{(uint)provider.Capabilities:X} " +
                $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)}");
            Console.Error.WriteLine(
                $"[V74.0.64][UPSCALER] initialized backend={RequestedUpscalerBackend()} " +
                $"quality={RequestedUpscalerQuality()} caps={provider.Capabilities} output={outputWidth}x{outputHeight}");
            return true;
        }

        private bool TryEnsureUpscalerOutput(GuestImageResource source, uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)
        {
            var outputWidth = requestedOutputWidth == 0 ? _extent.Width : requestedOutputWidth;
            var outputHeight = requestedOutputHeight == 0 ? _extent.Height : requestedOutputHeight;
            var formatProperties = default(FormatProperties);
            _vk.GetPhysicalDeviceFormatProperties(_physicalDevice, source.Format, out formatProperties);
            if ((formatProperties.OptimalTilingFeatures & FormatFeatureFlags.StorageImageBit) == 0)
            {
                return false;
            }

            if (_upscalerOutput is not null &&
                _upscalerOutput.Width == outputWidth &&
                _upscalerOutput.Height == outputHeight &&
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
                Extent = new Extent3D(outputWidth, outputHeight, 1),
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
                Width = outputWidth,
                Height = outputHeight,
                LogicalWidth = outputWidth,
                LogicalHeight = outputHeight,
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

        private void TrackUpscalerTemporalBinding(
            VulkanOffscreenGuestDraw work,
            GuestImageResource[] targets,
            GuestDepthResource? depth)
        {
            if (targets.Length == 0 ||
                (RequestedUpscalerBackend() == HostUpscalerBackend.Off &&
                 !UpscalerTemporalAuditEnabled()))
            {
                return;
            }

            var serial = ++_upscalerTemporalBindingSerial;
            for (var targetIndex = 0; targetIndex < targets.Length; targetIndex++)
            {
                var color = targets[targetIndex];
                if (color.Address == 0)
                {
                    continue;
                }

                var siblings = new UpscalerTemporalSibling[Math.Max(0, targets.Length - 1)];
                var siblingIndex = 0;
                for (var index = 0; index < targets.Length; index++)
                {
                    if (index == targetIndex || targets[index].Address == 0)
                    {
                        continue;
                    }

                    var sibling = targets[index];
                    siblings[siblingIndex++] = new UpscalerTemporalSibling(
                        sibling.Address,
                        sibling.Width,
                        sibling.Height,
                        sibling.Format);
                }

                if (siblingIndex != siblings.Length)
                {
                    Array.Resize(ref siblings, siblingIndex);
                }

                _upscalerTemporalBindings[color.Address] = new UpscalerTemporalBinding(
                    color.Address,
                    depth?.Address ?? 0,
                    work.ShaderAddress,
                    serial,
                    siblings);
            }

            if (_upscalerTemporalBindings.Count > MaxUpscalerTemporalBindings)
            {
                // Guest render-target addresses are normally stable. If a title
                // churns through transient RTs, prefer a bounded fresh map over
                // allowing an audit feature to become a residency leak.
                _upscalerTemporalBindings.Clear();
                _upscalerTemporalAuditLastLoggedSerial.Clear();
                _upscalerTemporalAuditMissingLogged.Clear();
            }
        }

        private GuestDepthResource? FindUpscalerDepthByAddress(ulong requested)
        {
            if (requested == 0)
            {
                return null;
            }

            foreach (var depth in _guestDepthImages.Values)
            {
                if (depth.Address == requested ||
                    depth.ReadAddress == requested ||
                    depth.WriteAddress == requested)
                {
                    return depth;
                }
            }

            return null;
        }

        // V74.0.67.2.2.2 exact-method temporal provenance rescue
        //
        // Uses only V74.0.65 common binding fields:
        // ColorAddress + DepthAddress + Serial + Siblings.
        private const long UpscalerTemporalRescueMaxAge = 64;
        private const long UpscalerTemporalRescueAmbiguityWindow = 8;
        // V74.0.67.2.3 stable depth disambiguation
        private ulong _upscalerDepthRescueSelected;
        private ulong _upscalerDepthRescueAmbiguous;
        private ulong _upscalerMotionRescueSelected;
        private ulong _upscalerMotionRescueAmbiguous;

        // V74.0.67.2.5 per-source content-generation confidence
        //
        // Depth confidence belongs to the color resource whose provenance is
        // being evaluated. Unrelated RTs must never reset another source.
        private const int UpscalerDepthStableStateMaxEntries = 64;

        private sealed class UpscalerDepthStableStateV7406725
        {
            public ulong NearestAddress;
            public ulong CompetingAddress;
            public long LastContentGeneration = -1;
            public int Confidence;
        }

        private readonly Dictionary<ulong, UpscalerDepthStableStateV7406725>
            _upscalerDepthStableBySourceV7406725 = new();

        // A second valid depth inside the temporal window must not block DLSS
        // forever when the same candidate remains strictly nearest across
        // distinct producer serials. Confidence never advances twice for the
        // same source serial and resets immediately if the ordering changes.
        private const int UpscalerDepthStableConfidenceRequired = 3;
        // V74.0.101.4: Frame Generation can bootstrap one generation earlier
        // once the same nearest/competing depth ordering has been observed
        // twice. DLSS-SR keeps the original three-generation requirement.
        private const int UpscalerDepthStableConfidenceRequiredFgV7401014 = 2;
        private const long UpscalerDepthStableMinimumAgeAdvantage = 2;

        private int UpscalerDepthStableConfidenceRequiredCurrentV7401014() =>
            RequestedDlssFrameGeneration() &&
            ReadUpscalerBool("SHARPEMU_DLSS_FG_FAST_TEMPORAL_BOOTSTRAP", true)
                ? UpscalerDepthStableConfidenceRequiredFgV7401014
                : UpscalerDepthStableConfidenceRequired;



        // V74.0.67.2.4.1 presented-sequence depth confidence
        // The internal scene RT is persistent and its provenance Serial can
        // remain unchanged for many visible frames. Use present sequence as
        // the confidence epoch instead.



        private long UpscalerTemporalRescueSourceSerial(GuestImageResource source)
        {
            return _upscalerTemporalBindings.TryGetValue(source.Address, out var sourceBinding)
                ? sourceBinding.Serial
                : _upscalerTemporalBindingSerial;
        }

        private bool UpscalerTemporalBindingMatchesExtent(
            UpscalerTemporalBinding binding,
            GuestImageResource source)
        {
            return binding.ColorAddress != 0 &&
                   _guestImages.TryGetValue(binding.ColorAddress, out var color) &&
                   color.Width == source.Width &&
                   color.Height == source.Height;
        }

        private GuestDepthResource? ResolveUpscalerDepthFromRecentBinding(
            GuestImageResource source)
        {
            var sourceSerial = UpscalerTemporalRescueSourceSerial(source);
            GuestDepthResource? best = null;
            ulong bestAddress = 0;
            var bestAge = long.MaxValue;

            foreach (var binding in _upscalerTemporalBindings.Values)
            {
                if (binding.DepthAddress == 0 ||
                    binding.Serial > sourceSerial ||
                    !UpscalerTemporalBindingMatchesExtent(binding, source))
                {
                    continue;
                }

                var age = sourceSerial - binding.Serial;
                if (age < 0 || age > UpscalerTemporalRescueMaxAge)
                {
                    continue;
                }

                var depth = FindUpscalerDepthByAddress(binding.DepthAddress);
                if (depth is null ||
                    !depth.Initialized ||
                    depth.Width != source.Width ||
                    depth.Height != source.Height)
                {
                    continue;
                }

                if (age < bestAge)
                {
                    best = depth;
                    bestAddress = binding.DepthAddress;
                    bestAge = age;
                }
            }

            if (best is null)
            {
                ResetUpscalerDepthStableConfidence(source.Address);
                return null;
            }

            ulong competingAddress = 0;
            var competingAge = long.MaxValue;
            foreach (var binding in _upscalerTemporalBindings.Values)
            {
                if (binding.DepthAddress == 0 ||
                    binding.DepthAddress == bestAddress ||
                    binding.Serial > sourceSerial ||
                    !UpscalerTemporalBindingMatchesExtent(binding, source))
                {
                    continue;
                }

                var age = sourceSerial - binding.Serial;
                if (age < 0 ||
                    age > UpscalerTemporalRescueMaxAge ||
                    age > bestAge + UpscalerTemporalRescueAmbiguityWindow)
                {
                    continue;
                }

                var competing = FindUpscalerDepthByAddress(binding.DepthAddress);
                if (competing is null ||
                    !competing.Initialized ||
                    competing.Width != source.Width ||
                    competing.Height != source.Height)
                {
                    continue;
                }

                if (age < competingAge)
                {
                    competingAge = age;
                    competingAddress = binding.DepthAddress;
                }
            }

            if (competingAddress == 0)
            {
                ResetUpscalerDepthStableConfidence(source.Address);
                return LogUpscalerDepthSelected(source, best, bestAddress, bestAge, "unique");
            }

            var ageAdvantage = competingAge - bestAge;
            if (ageAdvantage < UpscalerDepthStableMinimumAgeAdvantage)
            {
                ResetUpscalerDepthStableConfidence(source.Address);
                LogUpscalerDepthAmbiguous(
                    source, bestAddress, bestAge, competingAddress, competingAge,
                    "age_advantage_too_small", 0);
                return null;
            }

            var contentGeneration = source.ContentGeneration;
            var confidence = ObserveUpscalerDepthStableOrdering(
                source, bestAddress, competingAddress);
            if (contentGeneration <= 0)
            {
                LogUpscalerDepthAmbiguous(
                    source, bestAddress, bestAge, competingAddress, competingAge,
                    "content_generation_not_ready", 0);
                return null;
            }

            var requiredConfidence =
                UpscalerDepthStableConfidenceRequiredCurrentV7401014();
            if (confidence < requiredConfidence)
            {
                LogUpscalerDepthAmbiguous(
                    source, bestAddress, bestAge, competingAddress, competingAge,
                    "warming", confidence);
                return null;
            }

            if (requiredConfidence < UpscalerDepthStableConfidenceRequired &&
                confidence == requiredConfidence)
            {
                var bootstrapCount = ++_dlssFgTemporalDepthBootstrapCountV7401014;
                if (bootstrapCount <= 16 || bootstrapCount % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.101.4][DLSS-G][TEMPORAL_BOOTSTRAP] " +
                        $"kind=depth source=0x{source.Address:X16} " +
                        $"nearest=0x{bestAddress:X16} competing=0x{competingAddress:X16} " +
                        $"advantage={ageAdvantage} confidence={confidence} required={requiredConfidence} " +
                        $"count={bootstrapCount}");
                }
            }

            var selectedCount = ++_upscalerDepthRescueSelected;
            if (selectedCount <= 48 || selectedCount % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.3][UPSCALER][DEPTH_RESCUE] " +
                    $"state=stable_selected source=0x{source.Address:X16} " +
                    $"size={source.Width}x{source.Height} " +
                    $"depth=0x{bestAddress:X16} age={bestAge} " +
                    $"competing=0x{competingAddress:X16} competing_age={competingAge} " +
                    $"advantage={ageAdvantage} confidence={confidence} " +
                    $"content_gen={contentGeneration} count={selectedCount}");
            }
            return best;
        }

        private void ResetUpscalerDepthStableConfidence(ulong sourceAddress)
        {
            _upscalerDepthStableBySourceV7406725.Remove(sourceAddress);
        }

        private UpscalerDepthStableStateV7406725
            GetUpscalerDepthStableStateV7406725(ulong sourceAddress)
        {
            if (_upscalerDepthStableBySourceV7406725.TryGetValue(
                    sourceAddress,
                    out var existing))
            {
                return existing;
            }

            if (_upscalerDepthStableBySourceV7406725.Count >=
                UpscalerDepthStableStateMaxEntries)
            {
                ulong oldestSource = 0;
                var oldestGeneration = long.MaxValue;

                foreach (var pair in _upscalerDepthStableBySourceV7406725)
                {
                    if (pair.Value.LastContentGeneration < oldestGeneration)
                    {
                        oldestGeneration = pair.Value.LastContentGeneration;
                        oldestSource = pair.Key;
                    }
                }

                if (oldestSource != 0)
                {
                    _upscalerDepthStableBySourceV7406725.Remove(oldestSource);
                }
            }

            var created = new UpscalerDepthStableStateV7406725();
            _upscalerDepthStableBySourceV7406725[sourceAddress] = created;
            return created;
        }

        private int ObserveUpscalerDepthStableOrdering(
            GuestImageResource source,
            ulong nearestAddress,
            ulong competingAddress)
        {
            var state =
                GetUpscalerDepthStableStateV7406725(source.Address);

            if (state.NearestAddress != nearestAddress ||
                state.CompetingAddress != competingAddress)
            {
                state.NearestAddress = nearestAddress;
                state.CompetingAddress = competingAddress;
                state.LastContentGeneration = -1;
                state.Confidence = 0;
            }

            var contentGeneration = source.ContentGeneration;
            if (contentGeneration <= 0)
            {
                return 0;
            }

            if (state.LastContentGeneration != contentGeneration)
            {
                state.LastContentGeneration = contentGeneration;

                if (state.Confidence < int.MaxValue)
                {
                    state.Confidence++;
                }

                if (state.Confidence <=
                    UpscalerDepthStableConfidenceRequiredCurrentV7401014())
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.5][UPSCALER][DEPTH_CONFIDENCE] " +
                        $"source=0x{source.Address:X16} " +
                        $"content_gen={contentGeneration} " +
                        $"nearest=0x{nearestAddress:X16} " +
                        $"competing=0x{competingAddress:X16} " +
                        $"confidence={state.Confidence}");
                }
            }

            return state.Confidence;
        }
        private void LogUpscalerDepthAmbiguous(
            GuestImageResource source,
            ulong nearestAddress,
            long nearestAge,
            ulong competingAddress,
            long competingAge,
            string reason,
            int confidence)
        {
            var ambiguousCount = ++_upscalerDepthRescueAmbiguous;
            if (ambiguousCount <= 32 || ambiguousCount % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.3][UPSCALER][DEPTH_RESCUE] " +
                    $"state=ambiguous source=0x{source.Address:X16} " +
                    $"size={source.Width}x{source.Height} " +
                    $"nearest=0x{nearestAddress:X16} nearest_age={nearestAge} " +
                    $"competing=0x{competingAddress:X16} competing_age={competingAge} " +
                    $"reason={reason} confidence={confidence} count={ambiguousCount}");
            }
        }

        private GuestDepthResource LogUpscalerDepthSelected(
            GuestImageResource source,
            GuestDepthResource depth,
            ulong depthAddress,
            long age,
            string reason)
        {
            var selectedCount = ++_upscalerDepthRescueSelected;
            if (selectedCount <= 48 || selectedCount % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.3][UPSCALER][DEPTH_RESCUE] " +
                    $"state=selected source=0x{source.Address:X16} " +
                    $"size={source.Width}x{source.Height} " +
                    $"depth=0x{depthAddress:X16} age={age} reason={reason} " +
                    $"count={selectedCount}");
            }
            return depth;
        }

        private GuestImageResource? ResolveUpscalerMotionFromBindingSiblings(
            UpscalerTemporalBinding binding,
            GuestImageResource source)
        {
            GuestImageResource? candidate = null;

            foreach (var sibling in binding.Siblings)
            {
                if (sibling.Address == 0 ||
                    sibling.Address == source.Address ||
                    sibling.Width != source.Width ||
                    sibling.Height != source.Height ||
                    !IsLikelyUpscalerMotionVectorFormat(sibling.Format) ||
                    !_guestImages.TryGetValue(sibling.Address, out var image) ||
                    !image.Initialized ||
                    image.InitialUploadPending)
                {
                    continue;
                }

                if (candidate is not null && candidate.Address != image.Address)
                {
                    return null;
                }

                candidate = image;
            }

            return candidate;
        }

        private GuestImageResource? ResolveUpscalerMotionFromRecentBinding(
            GuestImageResource source)
        {
            var sourceSerial = UpscalerTemporalRescueSourceSerial(source);
            GuestImageResource? best = null;
            ulong bestAddress = 0;
            var bestAge = long.MaxValue;

            foreach (var binding in _upscalerTemporalBindings.Values)
            {
                if (binding.Serial > sourceSerial ||
                    !UpscalerTemporalBindingMatchesExtent(binding, source))
                {
                    continue;
                }

                var age = sourceSerial - binding.Serial;
                if (age < 0 || age > UpscalerTemporalRescueMaxAge)
                {
                    continue;
                }

                var motion = ResolveUpscalerMotionFromBindingSiblings(binding, source);
                if (motion is null)
                {
                    continue;
                }

                if (age < bestAge)
                {
                    best = motion;
                    bestAddress = motion.Address;
                    bestAge = age;
                }
            }

            if (best is null)
            {
                return null;
            }

            foreach (var binding in _upscalerTemporalBindings.Values)
            {
                if (binding.Serial > sourceSerial ||
                    !UpscalerTemporalBindingMatchesExtent(binding, source))
                {
                    continue;
                }

                var age = sourceSerial - binding.Serial;
                if (age < 0 ||
                    age > UpscalerTemporalRescueMaxAge ||
                    age > bestAge + UpscalerTemporalRescueAmbiguityWindow)
                {
                    continue;
                }

                var competing = ResolveUpscalerMotionFromBindingSiblings(binding, source);
                if (competing is null || competing.Address == bestAddress)
                {
                    continue;
                }

                var ambiguousCount = ++_upscalerMotionRescueAmbiguous;
                if (ambiguousCount <= 24 || ambiguousCount % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.2.2][UPSCALER][MOTION_RESCUE] " +
                        $"state=ambiguous source=0x{source.Address:X16} " +
                        $"size={source.Width}x{source.Height} " +
                        $"nearest=0x{bestAddress:X16} nearest_age={bestAge} " +
                        $"competing=0x{competing.Address:X16} competing_age={age} " +
                        $"count={ambiguousCount}");
                }

                return null;
            }

            var selectedCount = ++_upscalerMotionRescueSelected;
            if (selectedCount <= 48 || selectedCount % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.2.2][UPSCALER][MOTION_RESCUE] " +
                    $"state=selected source=0x{source.Address:X16} " +
                    $"size={source.Width}x{source.Height} " +
                    $"motion=0x{bestAddress:X16} age={bestAge} " +
                    $"count={selectedCount}");
            }

            return best;
        }
        private GuestDepthResource? ResolveUpscalerDepth(GuestImageResource source)
        {
            var requested = ParseAddressEnvironment("SHARPEMU_VK_UPSCALER_DEPTH_ADDR");
            if (requested != 0)
            {
                return FindUpscalerDepthByAddress(requested);
            }

            if (_upscalerTemporalBindings.TryGetValue(source.Address, out var binding))
            {
                var direct = FindUpscalerDepthByAddress(binding.DepthAddress);
                if (direct?.Initialized == true &&
                    direct.Width == source.Width &&
                    direct.Height == source.Height)
                {
                    return direct;
                }
            }

            return ResolveUpscalerDepthFromRecentBinding(source);
        }

        private static bool IsLikelyUpscalerMotionVectorFormat(Format format) =>
            format is Format.R16G16Sfloat or Format.R32G32Sfloat;

        // V74.0.67.2.6 global same-extent motion provenance
        //
        // Some titles produce velocity outside the color MRT sibling set.
        // Preserve the existing binding/recent-binding provenance first. Only
        // when those paths fail, scan initialized same-extent guest images for
        // the already-approved motion formats.
        private const long UpscalerGlobalMotionMaxGenerationDeltaV7406726 = 256;
        private const long UpscalerGlobalMotionSecondCandidateAdvantageV7406726 = 8;
        private const int UpscalerGlobalMotionStableObservationsV7406726 = 3;
        // V74.0.101.4: if exactly one initialized motion-vector-format image
        // exists inside the temporal window, FG may accept that unique
        // candidate after one observation. Ambiguous/multiple candidates keep
        // the original three-generation confidence requirement.
        private const int UpscalerGlobalMotionUniqueFgObservationsV7401014 = 1;
        private const int UpscalerGlobalMotionStateMaxEntriesV7406726 = 64;

        private sealed class UpscalerGlobalMotionStateV7406726
        {
            public ulong CandidateAddress;
            public long LastSourceGeneration = -1;
            public int Confidence;
        }

        private readonly Dictionary<ulong, UpscalerGlobalMotionStateV7406726>
            _upscalerGlobalMotionStateV7406726 = new();

        private ulong _upscalerGlobalMotionNoneV7406726;
        private ulong _upscalerGlobalMotionAmbiguousV7406726;
        private ulong _upscalerGlobalMotionWarmingV7406726;
        private ulong _upscalerGlobalMotionSelectedV7406726;

        private UpscalerGlobalMotionStateV7406726
            GetUpscalerGlobalMotionStateV7406726(ulong sourceAddress)
        {
            if (_upscalerGlobalMotionStateV7406726.TryGetValue(
                    sourceAddress,
                    out var existing))
            {
                return existing;
            }

            if (_upscalerGlobalMotionStateV7406726.Count >=
                UpscalerGlobalMotionStateMaxEntriesV7406726)
            {
                ulong oldestSource = 0;
                var oldestGeneration = long.MaxValue;

                foreach (var pair in _upscalerGlobalMotionStateV7406726)
                {
                    if (pair.Value.LastSourceGeneration < oldestGeneration)
                    {
                        oldestGeneration = pair.Value.LastSourceGeneration;
                        oldestSource = pair.Key;
                    }
                }

                if (oldestSource != 0)
                {
                    _upscalerGlobalMotionStateV7406726.Remove(oldestSource);
                }
            }

            var created = new UpscalerGlobalMotionStateV7406726();
            _upscalerGlobalMotionStateV7406726[sourceAddress] = created;
            return created;
        }

        private static long UpscalerGenerationDeltaV7406726(long left, long right)
        {
            if (left <= 0 || right <= 0)
            {
                return long.MaxValue;
            }

            return left >= right ? left - right : right - left;
        }

        private GuestImageResource? ResolveUpscalerMotionFromGlobalSameExtentV7406726(
            GuestImageResource source)
        {
            var sourceGeneration = source.ContentGeneration;
            GuestImageResource? best = null;
            GuestImageResource? second = null;
            var bestDelta = long.MaxValue;
            var secondDelta = long.MaxValue;
            var sameExtent = 0;
            var likelyFormat = 0;
            var withinWindow = 0;

            foreach (var image in _guestImages.Values)
            {
                if (image.Address == 0 ||
                    image.Address == source.Address ||
                    !image.Initialized ||
                    image.InitialUploadPending ||
                    image.Width != source.Width ||
                    image.Height != source.Height)
                {
                    continue;
                }

                sameExtent++;

                if (!IsLikelyUpscalerMotionVectorFormat(image.Format))
                {
                    continue;
                }

                likelyFormat++;

                var delta = UpscalerGenerationDeltaV7406726(
                    sourceGeneration,
                    image.ContentGeneration);

                if (delta > UpscalerGlobalMotionMaxGenerationDeltaV7406726)
                {
                    continue;
                }

                withinWindow++;

                if (delta < bestDelta ||
                    delta == bestDelta &&
                    best is not null &&
                    image.ContentGeneration > best.ContentGeneration)
                {
                    second = best;
                    secondDelta = bestDelta;
                    best = image;
                    bestDelta = delta;
                }
                else if (delta < secondDelta ||
                         delta == secondDelta &&
                         second is not null &&
                         image.ContentGeneration > second.ContentGeneration)
                {
                    second = image;
                    secondDelta = delta;
                }
            }

            if (best is null)
            {
                _upscalerGlobalMotionStateV7406726.Remove(source.Address);

                var count = ++_upscalerGlobalMotionNoneV7406726;
                if (count <= 24 || count % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.6][UPSCALER][MOTION_GLOBAL] " +
                        $"state=none source=0x{source.Address:X16} " +
                        $"size={source.Width}x{source.Height} " +
                        $"source_gen={sourceGeneration} same_extent={sameExtent} " +
                        $"likely_format={likelyFormat} within_window={withinWindow} " +
                        $"max_delta={UpscalerGlobalMotionMaxGenerationDeltaV7406726} " +
                        $"count={count}");
                }

                return null;
            }

            if (second is not null &&
                secondDelta - bestDelta <
                    UpscalerGlobalMotionSecondCandidateAdvantageV7406726)
            {
                _upscalerGlobalMotionStateV7406726.Remove(source.Address);

                var count = ++_upscalerGlobalMotionAmbiguousV7406726;
                if (count <= 24 || count % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.6][UPSCALER][MOTION_GLOBAL] " +
                        $"state=ambiguous source=0x{source.Address:X16} " +
                        $"size={source.Width}x{source.Height} " +
                        $"source_gen={sourceGeneration} " +
                        $"nearest=0x{best.Address:X16} nearest_gen={best.ContentGeneration} " +
                        $"nearest_delta={bestDelta} format={best.Format} guest_format={best.GuestFormat} " +
                        $"competing=0x{second.Address:X16} competing_gen={second.ContentGeneration} " +
                        $"competing_delta={secondDelta} format2={second.Format} guest_format2={second.GuestFormat} " +
                        $"count={count}");
                }

                return null;
            }

            var state = GetUpscalerGlobalMotionStateV7406726(source.Address);
            if (state.CandidateAddress != best.Address)
            {
                state.CandidateAddress = best.Address;
                state.LastSourceGeneration = -1;
                state.Confidence = 0;
            }

            if (sourceGeneration > 0 &&
                state.LastSourceGeneration != sourceGeneration)
            {
                state.LastSourceGeneration = sourceGeneration;
                if (state.Confidence < int.MaxValue)
                {
                    state.Confidence++;
                }
            }

            var requiredObservations =
                RequestedDlssFrameGeneration() &&
                ReadUpscalerBool("SHARPEMU_DLSS_FG_FAST_TEMPORAL_BOOTSTRAP", true) &&
                likelyFormat == 1 &&
                withinWindow == 1
                    ? UpscalerGlobalMotionUniqueFgObservationsV7401014
                    : UpscalerGlobalMotionStableObservationsV7406726;

            if (state.Confidence < requiredObservations)
            {
                var count = ++_upscalerGlobalMotionWarmingV7406726;
                if (count <= 32 || count % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.6][UPSCALER][MOTION_GLOBAL] " +
                        $"state=warming source=0x{source.Address:X16} " +
                        $"size={source.Width}x{source.Height} " +
                        $"source_gen={sourceGeneration} " +
                        $"motion=0x{best.Address:X16} motion_gen={best.ContentGeneration} " +
                        $"delta={bestDelta} format={best.Format} guest_format={best.GuestFormat} " +
                        $"confidence={state.Confidence} " +
                        $"same_extent={sameExtent} likely_format={likelyFormat} " +
                        $"within_window={withinWindow} count={count}");
                }

                return null;
            }

            if (requiredObservations < UpscalerGlobalMotionStableObservationsV7406726 &&
                state.Confidence == requiredObservations)
            {
                var bootstrapCount = ++_dlssFgTemporalMotionBootstrapCountV7401014;
                if (bootstrapCount <= 16 || bootstrapCount % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.101.4][DLSS-G][TEMPORAL_BOOTSTRAP] " +
                        $"kind=motion_unique source=0x{source.Address:X16} " +
                        $"motion=0x{best.Address:X16} delta={bestDelta} " +
                        $"confidence={state.Confidence} required={requiredObservations} " +
                        $"same_extent={sameExtent} likely_format={likelyFormat} within_window={withinWindow} " +
                        $"count={bootstrapCount}");
                }
            }

            var selectedCount = ++_upscalerGlobalMotionSelectedV7406726;
            if (selectedCount <= 48 || selectedCount % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.6][UPSCALER][MOTION_GLOBAL] " +
                    $"state=selected source=0x{source.Address:X16} " +
                    $"size={source.Width}x{source.Height} " +
                    $"source_gen={sourceGeneration} " +
                    $"motion=0x{best.Address:X16} motion_gen={best.ContentGeneration} " +
                    $"delta={bestDelta} format={best.Format} guest_format={best.GuestFormat} " +
                    $"confidence={state.Confidence} " +
                    $"same_extent={sameExtent} likely_format={likelyFormat} " +
                    $"within_window={withinWindow} count={selectedCount}");
            }

            return best;
        }
        private GuestImageResource? ResolveUpscalerMotionVectors(GuestImageResource source)
        {
            var requested = ParseAddressEnvironment("SHARPEMU_VK_UPSCALER_MOTION_ADDR");
            if (requested != 0)
            {
                return _guestImages.TryGetValue(requested, out var explicitImage)
                    ? explicitImage
                    : null;
            }

            if (!ReadUpscalerBool("SHARPEMU_VK_UPSCALER_AUTO_MOTION", true))
            {
                return null;
            }

            if (_upscalerTemporalBindings.TryGetValue(source.Address, out var binding))
            {
                var direct = ResolveUpscalerMotionFromBindingSiblings(binding, source);
                if (direct is not null)
                {
                    return direct;
                }
            }

            var recent = ResolveUpscalerMotionFromRecentBinding(source);
            if (recent is not null)
            {
                return recent;
            }

            return ResolveUpscalerMotionFromGlobalSameExtentV7406726(source);
        }

        private void TraceUpscalerTemporalAudit(GuestImageResource source)
        {
            if (!UpscalerTemporalAuditEnabled() || source.Address == 0)
            {
                return;
            }

            if (!_upscalerTemporalBindings.TryGetValue(source.Address, out var binding))
            {
                if (_upscalerTemporalAuditMissingLogged.Add(source.Address))
                {
                    Console.Error.WriteLine(
                        $"[V74.0.65][UPSCALER][TEMPORAL_AUDIT] " +
                        $"color=0x{source.Address:X16} size={source.Width}x{source.Height} " +
                        $"format={source.Format} no_binding=1");
                }
                return;
            }

            if (_upscalerTemporalAuditLastLoggedSerial.TryGetValue(
                    source.Address,
                    out var loggedSerial) &&
                loggedSerial == binding.Serial)
            {
                return;
            }

            _upscalerTemporalAuditLastLoggedSerial[source.Address] = binding.Serial;
            var depth = FindUpscalerDepthByAddress(binding.DepthAddress);
            var likelyMotion = new List<string>();
            var siblingText = new StringBuilder();
            for (var index = 0; index < binding.Siblings.Length; index++)
            {
                var sibling = binding.Siblings[index];
                if (index != 0)
                {
                    siblingText.Append(',');
                }

                siblingText.Append(
                    $"0x{sibling.Address:X16}:{sibling.Width}x{sibling.Height}:{sibling.Format}");
                if (sibling.Width == source.Width &&
                    sibling.Height == source.Height &&
                    IsLikelyUpscalerMotionVectorFormat(sibling.Format))
                {
                    likelyMotion.Add($"0x{sibling.Address:X16}");
                }
            }

            Console.Error.WriteLine(
                $"[V74.0.65][UPSCALER][TEMPORAL_AUDIT] " +
                $"color=0x{source.Address:X16} size={source.Width}x{source.Height} format={source.Format} " +
                $"depth=0x{binding.DepthAddress:X16} depth_ready={(depth?.Initialized == true ? 1 : 0)} " +
                $"shader=0x{binding.ShaderAddress:X16} siblings=[{siblingText}] " +
                $"likely_motion=[{string.Join(',', likelyMotion)}]");
        }

        private static string UpscalerBackendToken(HostUpscalerBackend backend) =>
            backend switch
            {
                HostUpscalerBackend.Auto => "auto",
                HostUpscalerBackend.Dlss => "dlss",
                HostUpscalerBackend.Fsr => "fsr",
                _ => "off",
            };

        private static string UpscalerQualityToken(HostUpscalerQuality quality) =>
            quality switch
            {
                HostUpscalerQuality.NativeAa => "nativeaa",
                HostUpscalerQuality.Balanced => "balanced",
                HostUpscalerQuality.Performance => "performance",
                HostUpscalerQuality.UltraPerformance => "ultraperformance",
                _ => "quality",
            };

        private static bool UpscalerJitterConfigured()
        {
            return float.TryParse(
                       Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER_JITTER_X"),
                       NumberStyles.Float,
                       CultureInfo.InvariantCulture,
                       out var x) &&
                   float.IsFinite(x) &&
                   float.TryParse(
                       Environment.GetEnvironmentVariable("SHARPEMU_VK_UPSCALER_JITTER_Y"),
                       NumberStyles.Float,
                       CultureInfo.InvariantCulture,
                       out var y) &&
                   float.IsFinite(y);
        }

        private void PublishUpscalerRuntime(
            GuestImageResource source,
            HostUpscalerBackend requestedBackend,
            HostUpscalerBackend selectedBackend,
            HostUpscalerQuality quality,
            NativeUpscalerCapabilities caps,
            GuestDepthResource? depth,
            GuestImageResource? motion,
            string state,
            string reason)
        {
            var providerReady = _nativeUpscaler is not null;
            var colorReady = source.Initialized && !source.InitialUploadPending;
            var depthReady = depth is not null && depth.Initialized;
            var motionReady = motion is not null && motion.Initialized && !motion.InitialUploadPending;
            var jitterReady = UpscalerJitterConfigured();
            var total = _upscalerRuntimeDlssDispatches +
                        _upscalerRuntimeFsrDispatches +
                        _upscalerRuntimeFallbackFrames;
            var signature =
                $"{UpscalerBackendToken(requestedBackend)}|" +
                $"{UpscalerBackendToken(selectedBackend)}|" +
                $"{UpscalerQualityToken(quality)}|" +
                $"{state}|{reason}|{source.Width}x{source.Height}|" +
                $"{_extent.Width}x{_extent.Height}|{providerReady}|" +
                $"{colorReady}|{depthReady}|{motionReady}|{jitterReady}|0x{(uint)caps:X}";

            if (string.Equals(signature, _upscalerRuntimeLastSignature, StringComparison.Ordinal) &&
                total < _upscalerRuntimeLastReportedTotal + UpscalerRuntimePeriodicReportFrames)
            {
                return;
            }

            _upscalerRuntimeLastSignature = signature;
            _upscalerRuntimeLastReportedTotal = total;
            Console.Error.WriteLine(
                $"[V74.0.67][UPSCALER][RUNTIME] " +
                $"requested={UpscalerBackendToken(requestedBackend)} " +
                $"selected={UpscalerBackendToken(selectedBackend)} " +
                $"state={state} quality={UpscalerQualityToken(quality)} " +
                $"provider={(providerReady ? 1 : 0)} caps=0x{(uint)caps:X} " +
                $"input={source.Width}x{source.Height} output={_extent.Width}x{_extent.Height} " +
                $"color={(colorReady ? 1 : 0)} depth={(depthReady ? 1 : 0)} " +
                $"motion={(motionReady ? 1 : 0)} jitter={(jitterReady ? 1 : 0)} " +
                $"dlss_dispatches={_upscalerRuntimeDlssDispatches} " +
                $"fsr_dispatches={_upscalerRuntimeFsrDispatches} " +
                $"fallback_frames={_upscalerRuntimeFallbackFrames} " +
                $"dispatch_failures={_upscalerRuntimeDispatchFailures} " +
                $"reason={reason}");
        }

        private bool ReportUpscalerFallback(
            GuestImageResource source,
            HostUpscalerBackend requestedBackend,
            HostUpscalerBackend selectedBackend,
            HostUpscalerQuality quality,
            NativeUpscalerCapabilities caps,
            GuestDepthResource? depth,
            GuestImageResource? motion,
            string reason,
            bool dispatchFailure = false)
        {
            _upscalerRuntimeFallbackFrames++;
            if (dispatchFailure)
            {
                _upscalerRuntimeDispatchFailures++;
            }

            PublishUpscalerRuntime(
                source,
                requestedBackend,
                selectedBackend,
                quality,
                caps,
                depth,
                motion,
                dispatchFailure ? "error" : "fallback",
                reason);
            return false;
        }
        // V74.0.67.2.1 pre-composite DLSS redirect
        private bool _upscalerPreCompositeConsumerActive;
        private bool _upscalerPreCompositeFrameReady;
        private ulong _upscalerPreCompositeSourceAddress;
        private ulong _upscalerPreCompositeConsumerShader;
        private uint _upscalerPreCompositeOutputWidth;
        private uint _upscalerPreCompositeOutputHeight;
        private ulong _upscalerPreCompositeDispatches;
        private ulong _upscalerPreCompositeReplacements;
        // V74.0.101.2: keep the most recent authoritative temporal pair so
        // DLSS-G can be prepared at present even when DLSS-SR is not eligible.
        private GuestDepthResource? _dlssFgLastDepth;
        private GuestImageResource? _dlssFgLastMotion;
        private ulong _dlssFgLastTemporalSourceAddress;
        private ulong _dlssFgPrepareAttempts;
        private ulong _dlssFgPrepareSuccesses;
        private ulong _dlssFgTemporalDepthBootstrapCountV7401014;
        private ulong _dlssFgTemporalMotionBootstrapCountV7401014;

        private sealed record UpscalerPreCompositeCandidate(
            GuestImageResource Source,
            GuestDepthResource Depth,
            GuestImageResource Motion,
            UpscalerTemporalBinding Binding);

        private GuestImageResource? ResolveUpscalerMotionVectorsPreComposite(GuestImageResource source)
        {
            // V74.0.67.2.1: consume the cumulative public-in-class resolver.
            // This supports both the V74.0.65 inline sibling implementation
            // and the V74.0.66 lineage implementation without depending on a
            // private helper name that later hot-path rollups may refactor.
            return ResolveUpscalerMotionVectors(source);
        }

        private static bool UpscalerPreCompositeAspectMatches(
            uint sourceWidth,
            uint sourceHeight,
            uint outputWidth,
            uint outputHeight)
        {
            if (sourceWidth == 0 || sourceHeight == 0 ||
                outputWidth == 0 || outputHeight == 0)
            {
                return false;
            }

            var left = (long)sourceWidth * outputHeight;
            var right = (long)outputWidth * sourceHeight;
            var difference = Math.Abs(left - right);
            var tolerance = Math.Max(Math.Abs(right) / 50L, 1L); // 2%
            return difference <= tolerance;
        }

        private HostUpscalerQuality ResolveUpscalerPreCompositeEffectiveQuality(
            HostUpscalerQuality requested,
            GuestImageResource source,
            uint outputWidth,
            uint outputHeight)
        {
            if (requested == HostUpscalerQuality.NativeAa)
            {
                return requested;
            }

            // A title may already render internally at a fixed resolution that
            // does not match the UI-selected preset. Keep the actual guest
            // render resolution authoritative and select the nearest NGX SR
            // quality family instead of lying about UltraPerformance while
            // feeding a 1440p input to a 4K output.
            var ratioX = (float)source.Width / Math.Max(outputWidth, 1u);
            var ratioY = (float)source.Height / Math.Max(outputHeight, 1u);
            var ratio = Math.Min(ratioX, ratioY);
            if (ratio >= 0.62f)
            {
                return HostUpscalerQuality.Quality;
            }
            if (ratio >= 0.54f)
            {
                return HostUpscalerQuality.Balanced;
            }
            if (ratio >= 0.44f)
            {
                return HostUpscalerQuality.Performance;
            }
            return HostUpscalerQuality.UltraPerformance;
        }

        private bool TrySelectUpscalerPreCompositeCandidate(
            VulkanOffscreenGuestDraw work,
            IReadOnlyList<GuestImageResource> consumerTargets,
            out UpscalerPreCompositeCandidate candidate,
            out string reason)
        {
            candidate = null!;
            reason = "no_temporal_scene_input";
            if (consumerTargets.Count == 0)
            {
                reason = "no_consumer_target";
                return false;
            }

            var outputWidth = consumerTargets[0].Width;
            var outputHeight = consumerTargets[0].Height;
            if (outputWidth < 1920 || outputHeight < 1080)
            {
                reason = "consumer_not_high_resolution";
                return false;
            }

            var explicitSource = ParseAddressEnvironment(
                "SHARPEMU_VK_UPSCALER_PRECOMPOSITE_SOURCE_ADDR");
            var candidates = new List<UpscalerPreCompositeCandidate>();
            var missingDepth = 0;
            var missingMotion = 0;

            foreach (var texture in work.Draw.Textures)
            {
                if (texture.IsStorage ||
                    texture.Address == 0 ||
                    (explicitSource != 0 && texture.Address != explicitSource) ||
                    !_guestImages.TryGetValue(texture.Address, out var source) ||
                    !source.Initialized ||
                    source.InitialUploadPending ||
                    source.Width < 960 ||
                    source.Height < 540 ||
                    source.Width >= outputWidth ||
                    source.Height >= outputHeight ||
                    !UpscalerPreCompositeAspectMatches(
                        source.Width,
                        source.Height,
                        outputWidth,
                        outputHeight) ||
                    !_upscalerTemporalBindings.TryGetValue(source.Address, out var binding))
                {
                    continue;
                }

                var depth = ResolveUpscalerDepth(source);
                if (depth is null || !depth.Initialized)
                {
                    missingDepth++;
                    continue;
                }

                var motion = ResolveUpscalerMotionVectorsPreComposite(source);
                if (motion is null ||
                    !motion.Initialized ||
                    motion.InitialUploadPending ||
                    ReferenceEquals(source, motion) ||
                    motion.Width != source.Width ||
                    motion.Height != source.Height)
                {
                    missingMotion++;
                    continue;
                }

                candidates.Add(new UpscalerPreCompositeCandidate(
                    source,
                    depth,
                    motion,
                    binding));
            }

            if (candidates.Count == 0)
            {
                reason = missingDepth != 0
                    ? "precomposite_depth_missing"
                    : missingMotion != 0
                        ? "precomposite_motion_missing"
                        : "no_temporal_scene_input";
                return false;
            }

            // Prefer the largest temporal input. If multiple candidates of the
            // same largest size exist, require an explicit source address
            // rather than silently substituting an unrelated MRT.
            var ordered = candidates
                .OrderByDescending(static item =>
                    (ulong)item.Source.Width * item.Source.Height)
                .ThenByDescending(static item => item.Binding.Serial)
                .ToArray();
            var bestArea =
                (ulong)ordered[0].Source.Width * ordered[0].Source.Height;
            var bestCount = ordered.Count(item =>
                (ulong)item.Source.Width * item.Source.Height == bestArea);

            // V74.0.67.2.7 stable temporal source disambiguation
            // V74.0.67.2.9 distinct source-identity disambiguation
            //
            // A source may appear several times because several temporal
            // bindings resolve to the same GuestImageResource. Those entries
            // are observations of one scene source, not competing sources.
            // Collapse by Source.Address before comparing confidence.
            if (bestCount > 1 && explicitSource == 0)
            {
                const int minTemporalConfidence = 3;
                const int minConfidenceAdvantage = 2;
                const int minSumAdvantage = 4;

                var rawLargest = ordered
                    .Where(item =>
                        (ulong)item.Source.Width * item.Source.Height == bestArea)
                    .ToArray();

                var distinctLargest = rawLargest
                    .GroupBy(static item => item.Source.Address)
                    .Select(static group =>
                        group
                            .OrderByDescending(static item =>
                                item.Source.ContentGeneration)
                            .ThenByDescending(static item => item.Binding.Serial)
                            .First())
                    .ToArray();

                var largest = distinctLargest
                    .Select(item =>
                    {
                        var depthConfidence =
                            _upscalerDepthStableBySourceV7406725.TryGetValue(
                                item.Source.Address,
                                out var depthState)
                                ? depthState.Confidence
                                : 0;
                        var motionConfidence =
                            _upscalerGlobalMotionStateV7406726.TryGetValue(
                                item.Source.Address,
                                out var motionState)
                                ? motionState.Confidence
                                : 0;
                        var temporalConfidence =
                            Math.Min(depthConfidence, motionConfidence);
                        var confidenceSum =
                            depthConfidence + motionConfidence;

                        return new
                        {
                            Candidate = item,
                            DepthConfidence = depthConfidence,
                            MotionConfidence = motionConfidence,
                            TemporalConfidence = temporalConfidence,
                            ConfidenceSum = confidenceSum
                        };
                    })
                    .OrderByDescending(static item => item.TemporalConfidence)
                    .ThenByDescending(static item => item.ConfidenceSum)
                    .ThenByDescending(static item =>
                        item.Candidate.Source.ContentGeneration)
                    .ThenByDescending(static item => item.Candidate.Binding.Serial)
                    .ToArray();

                var winner = largest[0];
                var runnerUp = largest.Length > 1 ? largest[1] : null;

                if (runnerUp is not null &&
                    runnerUp.Candidate.Source.Address ==
                        winner.Candidate.Source.Address)
                {
                    throw new InvalidOperationException(
                        "V74.0.67.2.9 source identity de-dup invariant failed.");
                }

                var confidenceAdvantage = runnerUp is null
                    ? winner.TemporalConfidence
                    : winner.TemporalConfidence - runnerUp.TemporalConfidence;
                var sumAdvantage = runnerUp is null
                    ? winner.ConfidenceSum
                    : winner.ConfidenceSum - runnerUp.ConfidenceSum;

                if (winner.TemporalConfidence < minTemporalConfidence ||
                    runnerUp is not null &&
                    confidenceAdvantage < minConfidenceAdvantage &&
                    sumAdvantage < minSumAdvantage)
                {
                    var runnerSource = runnerUp is null
                        ? 0UL
                        : runnerUp.Candidate.Source.Address;
                    var runnerDepth = runnerUp is null
                        ? 0
                        : runnerUp.DepthConfidence;
                    var runnerMotion = runnerUp is null
                        ? 0
                        : runnerUp.MotionConfidence;
                    var runnerTemporal = runnerUp is null
                        ? 0
                        : runnerUp.TemporalConfidence;

                    Console.Error.WriteLine(
                        $"[V74.0.67.2.9][UPSCALER][SOURCE_RESOLVE] " +
                        $"state=ambiguous area={bestArea} " +
                        $"raw_candidates={bestCount} " +
                        $"distinct_sources={largest.Length} " +
                        $"winner=0x{winner.Candidate.Source.Address:X16} " +
                        $"depth_conf={winner.DepthConfidence} " +
                        $"motion_conf={winner.MotionConfidence} " +
                        $"temporal_conf={winner.TemporalConfidence} " +
                        $"runner=0x{runnerSource:X16} " +
                        $"runner_depth_conf={runnerDepth} " +
                        $"runner_motion_conf={runnerMotion} " +
                        $"runner_temporal_conf={runnerTemporal} " +
                        $"confidence_advantage={confidenceAdvantage} " +
                        $"sum_advantage={sumAdvantage}");

                    reason = "ambiguous_precomposite_source";
                    return false;
                }

                candidate = winner.Candidate;
                Console.Error.WriteLine(
                    $"[V74.0.67.2.9][UPSCALER][SOURCE_RESOLVE] " +
                    $"state=selected source=0x{candidate.Source.Address:X16} " +
                    $"size={candidate.Source.Width}x{candidate.Source.Height} " +
                    $"content_gen={candidate.Source.ContentGeneration} " +
                    $"binding_serial={candidate.Binding.Serial} " +
                    $"depth=0x{candidate.Depth.Address:X16} " +
                    $"motion=0x{candidate.Motion.Address:X16} " +
                    $"depth_conf={winner.DepthConfidence} " +
                    $"motion_conf={winner.MotionConfidence} " +
                    $"temporal_conf={winner.TemporalConfidence} " +
                    $"confidence_advantage={confidenceAdvantage} " +
                    $"sum_advantage={sumAdvantage} " +
                    $"raw_candidates={bestCount} " +
                    $"distinct_sources={largest.Length}");
                reason = "ready";
                return true;
            }

            candidate = ordered[0];
            reason = "ready";
            return true;
        }

        private void EmitUpscalerPreCompositeRuntime(
            HostUpscalerBackend requested,
            HostUpscalerBackend selected,
            HostUpscalerQuality requestedQuality,
            HostUpscalerQuality effectiveQuality,
            NativeUpscalerCapabilities caps,
            UpscalerPreCompositeCandidate candidate,
            uint outputWidth,
            uint outputHeight,
            string state,
            string reason)
        {
            Console.Error.WriteLine(
                $"[V74.0.67.2.1.3][UPSCALER][PRECOMPOSITE] " +
                $"requested={UpscalerBackendToken(requested)} " +
                $"selected={UpscalerBackendToken(selected)} " +
                $"state={state} " +
                $"requested_quality={UpscalerQualityToken(requestedQuality)} " +
                $"effective_quality={UpscalerQualityToken(effectiveQuality)} " +
                $"provider={(_nativeUpscaler is null ? 0 : 1)} caps=0x{(uint)caps:X} " +
                $"source=0x{candidate.Source.Address:X16} " +
                $"input={candidate.Source.Width}x{candidate.Source.Height} " +
                $"output={outputWidth}x{outputHeight} " +
                $"depth=0x{candidate.Depth.Address:X16} " +
                $"motion=0x{candidate.Motion.Address:X16} " +
                $"shader=0x{_upscalerPreCompositeConsumerShader:X16} " +
                $"precomposite_dispatches={_upscalerPreCompositeDispatches} " +
                $"descriptor_replacements={_upscalerPreCompositeReplacements} " +
                $"dlss_dispatches={_upscalerRuntimeDlssDispatches} " +
                $"fsr_dispatches={_upscalerRuntimeFsrDispatches} " +
                $"reason={reason}");

            // Feed the existing V74.0.67 GUI parser with the actual temporal
            // input/output dimensions. The final scanout will not overwrite
            // this ACTIVE state for the same frame.
            Console.Error.WriteLine(
                $"[V74.0.67][UPSCALER][RUNTIME] " +
                $"requested={UpscalerBackendToken(requested)} " +
                $"selected={UpscalerBackendToken(selected)} " +
                $"state={state} quality={UpscalerQualityToken(effectiveQuality)} " +
                $"provider={(_nativeUpscaler is null ? 0 : 1)} caps=0x{(uint)caps:X} " +
                $"input={candidate.Source.Width}x{candidate.Source.Height} " +
                $"output={outputWidth}x{outputHeight} " +
                $"color=1 depth=1 motion=1 jitter={(UpscalerJitterConfigured() ? 1 : 0)} " +
                $"dlss_dispatches={_upscalerRuntimeDlssDispatches} " +
                $"fsr_dispatches={_upscalerRuntimeFsrDispatches} " +
                $"fallback_frames={_upscalerRuntimeFallbackFrames} " +
                $"dispatch_failures={_upscalerRuntimeDispatchFailures} " +
                $"reason={reason}");
        }

        private bool TryPrepareUpscalerPreCompositeForConsumer(
            VulkanOffscreenGuestDraw work,
            IReadOnlyList<GuestImageResource> consumerTargets)
        {
            _upscalerPreCompositeConsumerActive = false;
            _upscalerPreCompositeSourceAddress = 0;
            _upscalerPreCompositeConsumerShader = work.ShaderAddress;

            var requestedBackend = RequestedUpscalerBackend();
            var requestedQuality = RequestedUpscalerQuality();
            if (requestedBackend == HostUpscalerBackend.Off ||
                requestedQuality == HostUpscalerQuality.NativeAa ||
                consumerTargets.Count == 0)
            {
                return false;
            }

            if (!ReadUpscalerBool("SHARPEMU_VK_UPSCALER_PRECOMPOSITE", true))
            {
                return false;
            }

            if (!TrySelectUpscalerPreCompositeCandidate(
                    work,
                    consumerTargets,
                    out var candidate,
                    out var candidateReason))
            {
                if (work.Draw.Textures.Any(static texture =>
                        !texture.IsStorage && texture.Address != 0))
                {
                    Console.Error.WriteLine(
                        $"[V74.0.67.2.1.3][UPSCALER][PRECOMPOSITE] " +
                        $"state=fallback shader=0x{work.ShaderAddress:X16} " +
                        $"output={consumerTargets[0].Width}x{consumerTargets[0].Height} " +
                        $"reason={candidateReason}");
                }
                return false;
            }

            // V74.0.101.2: retain the strict temporal pair as soon as the
            // selector proves it, before DLSS-SR eligibility/initialization.
            // Frame Generation must not depend on a successful SR dispatch.
            if (RequestedDlssFrameGeneration())
            {
                _dlssFgLastDepth = candidate.Depth;
                _dlssFgLastMotion = candidate.Motion;
                _dlssFgLastTemporalSourceAddress = candidate.Source.Address;
            }

            var outputWidth = consumerTargets[0].Width;
            var outputHeight = consumerTargets[0].Height;
            // V74.0.67.2.19 strict requested quality profile passthrough.
            //
            // The old pre-composite logic derived an "effective" preset from
            // the observed render/output ratio. That silently changed user
            // selections (for example UltraPerformance -> Quality at
            // 2560x1440 -> 3840x2160). Keep the inferred value only for
            // diagnostics, but send the requested enum unchanged to NGX/FSR.
            var autoResolvedQualityV74067219 = ResolveUpscalerPreCompositeEffectiveQuality(
                requestedQuality,
                candidate.Source,
                outputWidth,
                outputHeight);
            var effectiveQuality = requestedQuality;

            if (requestedQuality != autoResolvedQualityV74067219 &&
                (_upscalerPreCompositeDispatches < 16 ||
                 (_upscalerPreCompositeDispatches & 255) == 0))
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.19][UPSCALER][QUALITY_PROFILE] " +
                    $"requested={requestedQuality.ToString().ToLowerInvariant()} " +
                    $"previous_auto={autoResolvedQualityV74067219.ToString().ToLowerInvariant()} " +
                    $"effective={effectiveQuality.ToString().ToLowerInvariant()} " +
                    $"action=strict-requested-passthrough");
            }

            if (!TryInitializeUpscaler(outputWidth, outputHeight) ||
                _nativeUpscaler is null)
            {
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    HostUpscalerBackend.Off,
                    requestedQuality,
                    effectiveQuality,
                    NativeUpscalerCapabilities.None,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_provider_init_failed");
                return false;
            }

            var caps = _nativeUpscaler.Capabilities;
            var selectedBackend = requestedBackend;
            if (selectedBackend == HostUpscalerBackend.Auto)
            {
                _vk.GetPhysicalDeviceProperties(_physicalDevice, out var properties);
                selectedBackend =
                    properties.VendorID == 0x10DE &&
                    (caps & NativeUpscalerCapabilities.Dlss) != 0
                        ? HostUpscalerBackend.Dlss
                        : (caps & NativeUpscalerCapabilities.Fsr) != 0
                            ? HostUpscalerBackend.Fsr
                            : HostUpscalerBackend.Off;
            }

            if (selectedBackend == HostUpscalerBackend.Dlss &&
                    (caps & NativeUpscalerCapabilities.Dlss) == 0 ||
                selectedBackend == HostUpscalerBackend.Fsr &&
                    (caps & NativeUpscalerCapabilities.Fsr) == 0 ||
                selectedBackend == HostUpscalerBackend.Off)
            {
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_backend_not_supported");
                return false;
            }

            if (!TryEnsureUpscalerOutput(
                    candidate.Source,
                    outputWidth,
                    outputHeight) ||
                _upscalerOutput is null)
            {
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_output_unavailable");
                return false;
            }

            // V74.0.67.2.14 pre-composite command-buffer ownership.
            //
            // TryPrepareUpscalerPreCompositeForConsumer is invoked before the
            // normal ExecuteOffscreenDrawCore BeginBatchedGuestCommands call so
            // the DLSS output can participate in texture descriptor translation.
            // Therefore _commandBuffer may still refer to the presentation
            // command buffer or another non-recording handle at this point.
            //
            // Acquire/reuse the shared guest batch and rebind _commandBuffer
            // before ANY RecordGuest* call, VkCmdPipelineBarrier, or NGX
            // Create/Evaluate operation.
            var preCompositeBatchWasOpen = _batchOpen;
            var preCompositeCommandBuffer = BeginBatchedGuestCommands();
            _commandBuffer = preCompositeCommandBuffer;
            CloseOpenTranslatedRenderPass();

            if (!_batchOpen || preCompositeCommandBuffer.Handle == 0)
            {
                _upscalerOutputReset = true;
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_command_buffer_unavailable");
                return false;
            }

            if (_upscalerPreCompositeDispatches < 8)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.14][UPSCALER][COMMAND_BUFFER] " +
                    $"state=recording handle=0x{(ulong)preCompositeCommandBuffer.Handle:X16} " +
                    $"batch_was_open={(preCompositeBatchWasOpen ? 1 : 0)} " +
                    $"batch_open={(_batchOpen ? 1 : 0)}");
            }
            RecordGuestImageForSampling(
                candidate.Source,
                PipelineStageFlags.ComputeShaderBit);
            RecordGuestDepthForSampling(
                candidate.Depth,
                PipelineStageFlags.ComputeShaderBit);
            RecordGuestImageForSampling(
                candidate.Motion,
                PipelineStageFlags.ComputeShaderBit);

            if (candidate.Source.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                candidate.Depth.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                candidate.Motion.Layout != ImageLayout.ShaderReadOnlyOptimal)
            {
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "fallback",
                    "precomposite_temporal_layout_not_ready");
                return false;
            }

            var output = _upscalerOutput;
            var outputToGeneral = new ImageMemoryBarrier
            {
                SType = StructureType.ImageMemoryBarrier,
                SrcAccessMask = output.Initialized
                    ? AccessFlags.ShaderReadBit | AccessFlags.TransferReadBit
                    : AccessFlags.None,
                DstAccessMask = AccessFlags.ShaderWriteBit,
                OldLayout = output.Initialized
                    ? output.Layout
                    : ImageLayout.Undefined,
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
                : (float)((now - _upscalerLastFrameTimestamp) * 1000.0 /
                    Stopwatch.Frequency);
            _upscalerLastFrameTimestamp = now;

            var dispatch = new NativeUpscalerDispatchDesc
            {
                Size = (uint)sizeof(NativeUpscalerDispatchDesc),
                AbiVersion = UpscalerAbiVersion,
                Backend = (int)selectedBackend,
                Quality = (int)effectiveQuality,
                CommandBuffer = (ulong)_commandBuffer.Handle,
                ColorImage = (ulong)candidate.Source.Image.Handle,
                ColorView = (ulong)candidate.Source.View.Handle,
                ColorFormat = (uint)candidate.Source.Format,
                ColorWidth = candidate.Source.Width,
                ColorHeight = candidate.Source.Height,
                ColorLayout = (int)candidate.Source.Layout,
                OutputImage = (ulong)output.Image.Handle,
                OutputView = (ulong)output.View.Handle,
                OutputFormat = (uint)output.Format,
                OutputWidth = outputWidth,
                OutputHeight = outputHeight,
                OutputLayout = (int)output.Layout,
                DepthImage = (ulong)candidate.Depth.Image.Handle,
                DepthView = (ulong)candidate.Depth.View.Handle,
                DepthFormat = (uint)Format.D32Sfloat,
                DepthWidth = candidate.Depth.Width,
                DepthHeight = candidate.Depth.Height,
                DepthLayout = (int)candidate.Depth.Layout,
                MotionImage = (ulong)candidate.Motion.Image.Handle,
                MotionView = (ulong)candidate.Motion.View.Handle,
                MotionFormat = (uint)candidate.Motion.Format,
                MotionWidth = candidate.Motion.Width,
                MotionHeight = candidate.Motion.Height,
                MotionLayout = (int)candidate.Motion.Layout,
                JitterX = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_JITTER_X", 0f),
                JitterY = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_JITTER_Y", 0f),
                MotionVectorScaleX = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_X",
                    candidate.Motion.Width),
                MotionVectorScaleY = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_Y",
                    candidate.Motion.Height),
                Sharpness = RequestedUpscalerSharpness(),
                FrameTimeMilliseconds =
                    Math.Clamp(frameTimeMilliseconds, 1f, 1000f),
                Reset = _upscalerOutputReset ? 1u : 0u,
                Flags = 0,
                FrameId = ++_upscalerFrameId,
                DlssModel = RequestedDlssModel(),
                FrameGenerationEnabled = 0u, // V74.0.101.2: FG is prepared independently at present.
                FrameGenerationMultiplier = RequestedDlssFrameMultiplier(),
                FrameGenerationReserved = 0,
            };

            BeginDebugLabel(
                _commandBuffer,
                $"SharpEmu pre-composite upscaler {selectedBackend}");
            var dispatched = _nativeUpscaler.Dispatch(dispatch);
            EndDebugLabel(_commandBuffer);
            if (!dispatched)
            {
                _upscalerOutputReset = true;
                _upscalerRuntimeDispatchFailures++;
                EmitUpscalerPreCompositeRuntime(
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    effectiveQuality,
                    caps,
                    candidate,
                    outputWidth,
                    outputHeight,
                    "error",
                    "precomposite_native_dispatch_failed");
                return false;
            }

            _upscalerOutputReset = false;
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

            if (selectedBackend == HostUpscalerBackend.Dlss)
            {
                _upscalerRuntimeDlssDispatches++;
            }
            else if (selectedBackend == HostUpscalerBackend.Fsr)
            {
                _upscalerRuntimeFsrDispatches++;
            }

            _upscalerPreCompositeDispatches++;
            _upscalerPreCompositeSourceAddress = candidate.Source.Address;
            _upscalerPreCompositeOutputWidth = outputWidth;
            _upscalerPreCompositeOutputHeight = outputHeight;
            _upscalerPreCompositeConsumerActive = true;
            _upscalerPreCompositeFrameReady = true;
            _dlssFgLastDepth = candidate.Depth;
            _dlssFgLastMotion = candidate.Motion;
            _dlssFgLastTemporalSourceAddress = candidate.Source.Address;

            EmitUpscalerPreCompositeRuntime(
                requestedBackend,
                selectedBackend,
                requestedQuality,
                effectiveQuality,
                caps,
                candidate,
                outputWidth,
                outputHeight,
                "active",
                "precomposite_dispatch_ok");
            return true;
        }

        private void EndUpscalerPreCompositeConsumer()
        {
            _upscalerPreCompositeConsumerActive = false;
            _upscalerPreCompositeSourceAddress = 0;
            _upscalerPreCompositeConsumerShader = 0;
        }

        private bool TryResolveUpscalerPreCompositeTexture(
            SharpEmu.Libs.Gpu.GuestDrawTexture texture,
            out TextureResource resource)
        {
            resource = null!;
            if (!_upscalerPreCompositeConsumerActive ||
                _upscalerOutput is null ||
                !_upscalerOutput.Initialized ||
                _upscalerOutput.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                texture.IsStorage ||
                texture.Address == 0 ||
                texture.Address != _upscalerPreCompositeSourceAddress ||
                texture.ArrayedView ||
                texture.BaseMipLevel != 0)
            {
                return false;
            }

            // The temporal output is created with the selected source format.
            // Use its canonical view here so V74.0.73 texture-view alias/cache
            // internals stay untouched by the pre-composite redirect.
            var view = _upscalerOutput.View;

            _upscalerPreCompositeReplacements++;
            if (_upscalerPreCompositeReplacements <= 32 ||
                _upscalerPreCompositeReplacements % 120 == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.1.3][UPSCALER][REDIRECT] " +
                    $"source=0x{texture.Address:X16} " +
                    $"consumer_shader=0x{_upscalerPreCompositeConsumerShader:X16} " +
                    $"output={_upscalerOutput.Width}x{_upscalerOutput.Height} " +
                    $"replacement_count={_upscalerPreCompositeReplacements}");
            }

            resource = new TextureResource
            {
                Address = texture.Address,
                Image = _upscalerOutput.Image,
                View = view,
                Width = _upscalerOutput.Width,
                Height = _upscalerOutput.Height,
                Depth = 1,
                Type = _upscalerOutput.Type,
                RowLength = _upscalerOutput.Width,
                DstSelect = texture.DstSelect,
                SamplerState = texture.Sampler,
                GuestImage = _upscalerOutput,
            };
            return true;
        }
        private bool TryPrepareDlssFrameGenerationForPresent(GuestImageResource? presentedGuestImage)
        {
            if (!RequestedDlssFrameGeneration() || presentedGuestImage is null)
            {
                return false;
            }

            var provider = EnsureUpscalerProviderLoaded();
            if (provider is null || !provider.HasFrameGenerationPrepareExport)
            {
                if (_dlssFgPrepareAttempts++ < 4)
                {
                    Console.Error.WriteLine(
                        "[V74.0.101.2][DLSS-G] stage=fg_present_prepare available=0 reason=provider_or_export_missing");
                }
                return false;
            }

            var depth = ResolveUpscalerDepth(presentedGuestImage);
            var motion = ResolveUpscalerMotionVectors(presentedGuestImage);
            var temporalSource = presentedGuestImage.Address;

            // Scanout can be a post-composite surface with no direct temporal
            // binding. Reuse only a pair that was previously selected by the
            // strict pre-composite temporal selector; never guess resources.
            if ((depth is null || motion is null) &&
                _dlssFgLastDepth is not null &&
                _dlssFgLastMotion is not null &&
                _dlssFgLastDepth.Initialized &&
                _dlssFgLastMotion.Initialized &&
                !_dlssFgLastMotion.InitialUploadPending)
            {
                depth = _dlssFgLastDepth;
                motion = _dlssFgLastMotion;
                temporalSource = _dlssFgLastTemporalSourceAddress;
            }

            _dlssFgPrepareAttempts++;
            if (depth is null || motion is null ||
                !depth.Initialized || !motion.Initialized || motion.InitialUploadPending ||
                ReferenceEquals(presentedGuestImage, motion))
            {
                if (_dlssFgPrepareAttempts <= 16 || _dlssFgPrepareAttempts % 120 == 0)
                {
                    Console.Error.WriteLine(
                        $"[V74.0.101.2][DLSS-G] stage=fg_present_inputs " +
                        $"ready=0 frame={_upscalerFrameId + 1} " +
                        $"scanout=0x{presentedGuestImage.Address:X16} temporal_source=0x{temporalSource:X16} " +
                        $"depth={(depth is null ? 0 : 1)} motion={(motion is null ? 0 : 1)} " +
                        $"swapchain={_extent.Width}x{_extent.Height}");
                }
                return false;
            }

            RecordGuestDepthForSampling(depth, PipelineStageFlags.AllCommandsBit);
            RecordGuestImageForSampling(motion, PipelineStageFlags.AllCommandsBit);
            if (depth.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                motion.Layout != ImageLayout.ShaderReadOnlyOptimal)
            {
                Console.Error.WriteLine(
                    $"[V74.0.101.2][DLSS-G] stage=fg_present_inputs ready=0 reason=layout " +
                    $"depth_layout={depth.Layout} motion_layout={motion.Layout}");
                return false;
            }

            var now = Stopwatch.GetTimestamp();
            var frameTimeMilliseconds = _upscalerLastFrameTimestamp == 0
                ? 16.6667f
                : (float)((now - _upscalerLastFrameTimestamp) * 1000.0 / Stopwatch.Frequency);
            _upscalerLastFrameTimestamp = now;

            var dispatch = new NativeUpscalerDispatchDesc
            {
                Size = (uint)sizeof(NativeUpscalerDispatchDesc),
                AbiVersion = UpscalerAbiVersion,
                Backend = (int)HostUpscalerBackend.Dlss,
                Quality = (int)RequestedUpscalerQuality(),
                CommandBuffer = (ulong)_commandBuffer.Handle,
                // Final color/backbuffer is intercepted by Streamline at present.
                // Do not mis-tag a differently-sized guest scanout as HUD-less color.
                ColorImage = 0,
                ColorView = 0,
                ColorFormat = (uint)_swapchainFormat,
                ColorWidth = _extent.Width,
                ColorHeight = _extent.Height,
                ColorLayout = (int)ImageLayout.PresentSrcKhr,
                OutputImage = 0,
                OutputView = 0,
                OutputFormat = (uint)_swapchainFormat,
                OutputWidth = _extent.Width,
                OutputHeight = _extent.Height,
                OutputLayout = (int)ImageLayout.PresentSrcKhr,
                DepthImage = (ulong)depth.Image.Handle,
                DepthView = (ulong)depth.View.Handle,
                DepthFormat = (uint)Format.D32Sfloat,
                DepthWidth = depth.Width,
                DepthHeight = depth.Height,
                DepthLayout = (int)depth.Layout,
                MotionImage = (ulong)motion.Image.Handle,
                MotionView = (ulong)motion.View.Handle,
                MotionFormat = (uint)motion.Format,
                MotionWidth = motion.Width,
                MotionHeight = motion.Height,
                MotionLayout = (int)motion.Layout,
                JitterX = ReadUpscalerFloat("SHARPEMU_VK_UPSCALER_JITTER_X", 0f),
                JitterY = ReadUpscalerFloat("SHARPEMU_VK_UPSCALER_JITTER_Y", 0f),
                MotionVectorScaleX = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_X", motion.Width),
                MotionVectorScaleY = ReadUpscalerFloat(
                    "SHARPEMU_VK_UPSCALER_MV_SCALE_Y", motion.Height),
                Sharpness = 0f,
                FrameTimeMilliseconds = Math.Clamp(frameTimeMilliseconds, 1f, 1000f),
                Reset = _upscalerOutputReset ? 1u : 0u,
                Flags = 0,
                FrameId = ++_upscalerFrameId,
                DlssModel = RequestedDlssModel(),
                FrameGenerationEnabled = 1u,
                FrameGenerationMultiplier = RequestedDlssFrameMultiplier(),
                FrameGenerationReserved = 0,
            };

            Console.Error.WriteLine(
                $"[V74.0.101.2][DLSS-G] stage=fg_present_inputs ready=1 frame={dispatch.FrameId} " +
                $"temporal_source=0x{temporalSource:X16} depth={depth.Width}x{depth.Height} " +
                $"motion={motion.Width}x{motion.Height} swapchain={_extent.Width}x{_extent.Height}");

            var prepared = provider.PrepareFrameGeneration(dispatch);
            if (prepared)
            {
                _dlssFgPrepareSuccesses++;
            }
            else
            {
                var reason = provider.LastError;
                Console.Error.WriteLine(
                    $"[V74.0.101.2][DLSS-G] stage=fg_present_prepare success=0 " +
                    $"frame={dispatch.FrameId} reason={(string.IsNullOrWhiteSpace(reason) ? "native_failure" : reason)}");
            }

            return prepared;
        }

        private bool TryRecordUpscaledGuestImage(uint imageIndex, GuestImageResource source)
        {
            TraceUpscalerTemporalAudit(source);
            var requestedBackend = RequestedUpscalerBackend();
            var requestedQuality = RequestedUpscalerQuality();
            var selectedBackend = HostUpscalerBackend.Off;
            var caps = NativeUpscalerCapabilities.None;
            GuestDepthResource? depth = null;
            GuestImageResource? motion = null;

            if (requestedBackend == HostUpscalerBackend.Off)
            {
                PublishUpscalerRuntime(
                    source,
                    requestedBackend,
                    selectedBackend,
                    requestedQuality,
                    caps,
                    depth,
                    motion,
                    "off",
                    "disabled");
                return false;
            }

            if (_upscalerPreCompositeFrameReady &&
                source.Width == _upscalerPreCompositeOutputWidth &&
                source.Height == _upscalerPreCompositeOutputHeight)
            {
                _upscalerPreCompositeFrameReady = false;
                Console.Error.WriteLine(
                    $"[V74.0.67.2.1.3][UPSCALER][SCANOUT] " +
                    $"guest={source.Width}x{source.Height} " +
                    $"swapchain={_extent.Width}x{_extent.Height} " +
                    $"action=normal_blit reason=precomposite_already_applied");
                return false;
            }
            if (source.Width == 0 || source.Height == 0)
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "invalid_source_size");
            }

            var sourceIsNativeSize = source.Width == _extent.Width && source.Height == _extent.Height;
            if ((requestedQuality == HostUpscalerQuality.NativeAa && !sourceIsNativeSize) ||
                (requestedQuality != HostUpscalerQuality.NativeAa && sourceIsNativeSize))
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "input_resolution_not_eligible");
            }

            // DLSS SR/FSR SR may only move from a smaller render surface to a
            // larger presentation target. The previous 3840x2160 -> 1920x1080
            // path was a downscale and must never be labelled as DLSS execution.
            if (requestedQuality != HostUpscalerQuality.NativeAa &&
                (source.Width >= _extent.Width || source.Height >= _extent.Height))
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "invalid_upscale_direction");
            }

            if (!TryInitializeUpscaler() || _nativeUpscaler is null)
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion,
                    _upscalerRequiredExtensionMissing
                        ? "required_vulkan_extension_missing"
                        : "provider_unavailable_or_init_failed");
            }

            caps = _nativeUpscaler.Capabilities;
            if (!TryEnsureUpscalerOutput(source) || _upscalerOutput is null)
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "output_image_unavailable");
            }

            selectedBackend = requestedBackend;
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
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "requested_backend_not_supported");
            }

            depth = ResolveUpscalerDepth(source);
            motion = ResolveUpscalerMotionVectors(source);
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
                        "Normal Vulkan blit remains active until both resources are identified.");
                }

                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "temporal_inputs_missing");
            }

            // The native API descriptors describe resources as compute-readable.
            if (!source.Initialized || source.InitialUploadPending)
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "color_not_ready");
            }

            RecordGuestImageForSampling(source, PipelineStageFlags.ComputeShaderBit);
            if (source.Layout != ImageLayout.ShaderReadOnlyOptimal)
            {
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "color_layout_not_ready");
            }

            if ((caps & NativeUpscalerCapabilities.Temporal) != 0 &&
                (caps & NativeUpscalerCapabilities.ColorOnly) == 0)
            {
                if (depth is null || motion is null ||
                    !depth.Initialized || !motion.Initialized || motion.InitialUploadPending ||
                    ReferenceEquals(source, motion))
                {
                    return ReportUpscalerFallback(
                        source, requestedBackend, selectedBackend, requestedQuality,
                        caps, depth, motion, "temporal_resources_not_ready");
                }

                RecordGuestDepthForSampling(depth, PipelineStageFlags.ComputeShaderBit);
                RecordGuestImageForSampling(motion, PipelineStageFlags.ComputeShaderBit);
                if (depth.Layout != ImageLayout.ShaderReadOnlyOptimal ||
                    motion.Layout != ImageLayout.ShaderReadOnlyOptimal)
                {
                    return ReportUpscalerFallback(
                        source, requestedBackend, selectedBackend, requestedQuality,
                        caps, depth, motion, "temporal_layout_not_ready");
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
                DlssModel = RequestedDlssModel(),
                FrameGenerationEnabled = 0u, // V74.0.101.2: FG is prepared independently at present.
                FrameGenerationMultiplier = RequestedDlssFrameMultiplier(),
                FrameGenerationReserved = 0,
            };

            BeginDebugLabel(_commandBuffer, $"SharpEmu host upscaler {selectedBackend}");
            var dispatched = _nativeUpscaler.Dispatch(dispatch);
            EndDebugLabel(_commandBuffer);
            if (!dispatched)
            {
                _upscalerOutputReset = true;
                return ReportUpscalerFallback(
                    source, requestedBackend, selectedBackend, requestedQuality,
                    caps, depth, motion, "native_dispatch_failed", dispatchFailure: true);
            }

            _upscalerOutputReset = false;
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

            if (selectedBackend == HostUpscalerBackend.Dlss)
            {
                _upscalerRuntimeDlssDispatches++;
            }
            else if (selectedBackend == HostUpscalerBackend.Fsr)
            {
                _upscalerRuntimeFsrDispatches++;
            }

            PublishUpscalerRuntime(
                source,
                requestedBackend,
                selectedBackend,
                requestedQuality,
                caps,
                depth,
                motion,
                "active",
                "dispatch_ok");

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
