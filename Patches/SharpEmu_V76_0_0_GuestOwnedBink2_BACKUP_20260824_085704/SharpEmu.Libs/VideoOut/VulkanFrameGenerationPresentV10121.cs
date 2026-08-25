// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using Silk.NET.Vulkan;
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.VideoOut;

internal static unsafe partial class VulkanVideoPresenter
{
    private sealed partial class Presenter
    {
        // V74.0.101.2.1: DLSS-G owns a present-time path that is independent
        // from DLSS Super Resolution eligibility/evaluation.
        [StructLayout(LayoutKind.Sequential)]
        private struct NativeFrameGenerationPresentDescV10121
        {
            public uint Size;
            public uint AbiVersion;
            public ulong BackbufferImage;
            public ulong BackbufferView;
            public uint BackbufferFormat;
            public uint BackbufferWidth;
            public uint BackbufferHeight;
            public int BackbufferLayout;
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
            public float FrameTimeMilliseconds;
            public uint Reset;
            public uint DlssModel;
            public uint FrameGenerationMultiplier;
            public uint Reserved0;
            public ulong FrameId;
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private unsafe delegate int PrepareFrameGenerationV10121Delegate(
            NativeFrameGenerationPresentDescV10121* desc);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void SuspendFrameGenerationV10121Delegate();

        private static class FrameGenerationInteropV10121
        {
            private static readonly object Gate = new();
            private static nint _library;
            private static bool _attempted;
            private static PrepareFrameGenerationV10121Delegate? _prepare;
            private static SuspendFrameGenerationV10121Delegate? _suspend;

            private static bool EnsureLoaded()
            {
                lock (Gate)
                {
                    if (_prepare is not null)
                    {
                        return true;
                    }
                    if (_attempted)
                    {
                        return false;
                    }
                    _attempted = true;

                    var configured = Environment.GetEnvironmentVariable(
                        "SHARPEMU_VK_UPSCALER_NATIVE")?.Trim();
                    var candidates = new[]
                    {
                        configured,
                        Path.Combine(AppContext.BaseDirectory, "upscalers", "SharpEmu.VulkanUpscaler.Native.dll"),
                        Path.Combine(AppContext.BaseDirectory, "SharpEmu.VulkanUpscaler.Native.dll"),
                    };

                    foreach (var candidate in candidates.Where(static item =>
                                 !string.IsNullOrWhiteSpace(item)).Distinct(StringComparer.OrdinalIgnoreCase))
                    {
                        if (!File.Exists(candidate) || !NativeLibrary.TryLoad(candidate, out var library))
                        {
                            continue;
                        }

                        if (!NativeLibrary.TryGetExport(
                                library,
                                "sharpemu_vk_upscaler_prepare_frame_generation",
                                out var prepareAddress))
                        {
                            NativeLibrary.Free(library);
                            continue;
                        }

                        _library = library;
                        _prepare = Marshal.GetDelegateForFunctionPointer<PrepareFrameGenerationV10121Delegate>(
                            prepareAddress);
                        if (NativeLibrary.TryGetExport(
                                library,
                                "sharpemu_vk_upscaler_suspend_frame_generation",
                                out var suspendAddress))
                        {
                            _suspend = Marshal.GetDelegateForFunctionPointer<SuspendFrameGenerationV10121Delegate>(
                                suspendAddress);
                        }

                        Console.Error.WriteLine(
                            $"[V74.0.101.2.1][DLSS-G] stage=present_interop_loaded path={candidate}");
                        return true;
                    }

                    Console.Error.WriteLine(
                        "[V74.0.101.2.1][DLSS-G] stage=present_interop_loaded success=0");
                    return false;
                }
            }

            internal static unsafe bool Prepare(ref NativeFrameGenerationPresentDescV10121 desc)
            {
                if (!EnsureLoaded() || _prepare is null)
                {
                    return false;
                }

                // Copy the ref value to an unmanaged stack local. Taking the address of
                // that local avoids pinning/ref-address corner cases and exactly matches
                // the native sequential descriptor for the duration of this call.
                var local = desc;
                return _prepare(&local) == 0;
            }

            internal static void Suspend()
            {
                if (EnsureLoaded())
                {
                    _suspend?.Invoke();
                }
            }
        }

        private GuestDepthResource? _v10121FrameGenerationDepth;
        private GuestImageResource? _v10121FrameGenerationMotion;
        private ulong _v10121FrameGenerationSourceAddress;
        private ulong _v10121FrameGenerationFrameId;
        private long _v10121FrameGenerationLastTimestamp;
        private bool _v10121FrameGenerationReset = true;
        private ulong _v10121FrameGenerationCaptureCount;

        private void CaptureFrameGenerationTemporalInputsV10121(
            UpscalerPreCompositeCandidate candidate)
        {
            if (!RequestedDlssFrameGeneration())
            {
                return;
            }

            if (!candidate.Depth.Initialized ||
                !candidate.Motion.Initialized ||
                candidate.Motion.InitialUploadPending ||
                ReferenceEquals(candidate.Source, candidate.Motion))
            {
                return;
            }

            _v10121FrameGenerationDepth = candidate.Depth;
            _v10121FrameGenerationMotion = candidate.Motion;
            _v10121FrameGenerationSourceAddress = candidate.Source.Address;
            var count = ++_v10121FrameGenerationCaptureCount;
            if (count <= 8 || (count & 127) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.101.2.1][DLSS-G] stage=fg_temporal_capture " +
                    $"count={count} color=0x{candidate.Source.Address:X16} " +
                    $"depth={candidate.Depth.Width}x{candidate.Depth.Height} " +
                    $"motion={candidate.Motion.Width}x{candidate.Motion.Height}");
            }
        }

        private bool FrameGenerationTemporalInputsAliveV10121()
        {
            var depth = _v10121FrameGenerationDepth;
            var motion = _v10121FrameGenerationMotion;
            if (depth is null || motion is null ||
                !depth.Initialized || !motion.Initialized || motion.InitialUploadPending)
            {
                return false;
            }

            if (!_guestImages.TryGetValue(motion.Address, out var currentMotion) ||
                !ReferenceEquals(currentMotion, motion))
            {
                return false;
            }

            return _guestDepthImages.Values.Any(candidate => ReferenceEquals(candidate, depth));
        }

        private void TryPrepareFrameGenerationForPresentV10121(uint imageIndex)
        {
            if (!RequestedDlssFrameGeneration())
            {
                return;
            }

            // RUN_6 validates Streamline registration/support only. Do not arm
            // DLSS-G during that phase even if valid temporal inputs appear.
            if (string.Equals(
                    Environment.GetEnvironmentVariable("SHARPEMU_DLSS_FG_ARM_ONLY"),
                    "1",
                    StringComparison.Ordinal))
            {
                return;
            }

            if (imageIndex >= _swapchainImages.Length ||
                imageIndex >= _swapchainImageViews.Length ||
                _swapchainImages[imageIndex].Handle == 0 ||
                _swapchainImageViews[imageIndex].Handle == 0 ||
                !FrameGenerationTemporalInputsAliveV10121())
            {
                Console.Error.WriteLine(
                    $"[V74.0.101.2.1][DLSS-G] stage=fg_present_inputs ready=0 " +
                    $"backbuffer={(imageIndex < _swapchainImages.Length && _swapchainImages[imageIndex].Handle != 0 ? 1 : 0)} " +
                    $"depth={(_v10121FrameGenerationDepth is not null ? 1 : 0)} " +
                    $"motion={(_v10121FrameGenerationMotion is not null ? 1 : 0)}");
                return;
            }

            var depth = _v10121FrameGenerationDepth!;
            var motion = _v10121FrameGenerationMotion!;
            var now = Stopwatch.GetTimestamp();
            var frameTimeMilliseconds = _v10121FrameGenerationLastTimestamp == 0
                ? 16.6667f
                : (float)((now - _v10121FrameGenerationLastTimestamp) * 1000.0 / Stopwatch.Frequency);
            _v10121FrameGenerationLastTimestamp = now;

            var desc = new NativeFrameGenerationPresentDescV10121
            {
                Size = (uint)sizeof(NativeFrameGenerationPresentDescV10121),
                AbiVersion = UpscalerAbiVersion,
                BackbufferImage = (ulong)_swapchainImages[imageIndex].Handle,
                BackbufferView = (ulong)_swapchainImageViews[imageIndex].Handle,
                BackbufferFormat = (uint)_swapchainFormat,
                BackbufferWidth = _extent.Width,
                BackbufferHeight = _extent.Height,
                BackbufferLayout = (int)ImageLayout.PresentSrcKhr,
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
                FrameTimeMilliseconds = Math.Clamp(frameTimeMilliseconds, 1f, 1000f),
                Reset = _v10121FrameGenerationReset ? 1u : 0u,
                DlssModel = RequestedDlssModel(),
                FrameGenerationMultiplier = RequestedDlssFrameMultiplier(),
                Reserved0 = 0,
                FrameId = ++_v10121FrameGenerationFrameId,
            };

            Console.Error.WriteLine(
                $"[V74.0.101.2.1][DLSS-G] stage=fg_present_inputs ready=1 " +
                $"frame={desc.FrameId} backbuffer={desc.BackbufferWidth}x{desc.BackbufferHeight} " +
                $"depth={desc.DepthWidth}x{desc.DepthHeight} " +
                $"motion={desc.MotionWidth}x{desc.MotionHeight} " +
                $"source=0x{_v10121FrameGenerationSourceAddress:X16}");

            if (FrameGenerationInteropV10121.Prepare(ref desc))
            {
                _v10121FrameGenerationReset = false;
            }
        }

        private void SuspendFrameGenerationForSwapchainV10121()
        {
            FrameGenerationInteropV10121.Suspend();
            _v10121FrameGenerationDepth = null;
            _v10121FrameGenerationMotion = null;
            _v10121FrameGenerationSourceAddress = 0;
            _v10121FrameGenerationLastTimestamp = 0;
            _v10121FrameGenerationReset = true;
        }
    }
}
