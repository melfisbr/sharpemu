// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Reflection;
using System.Threading;

namespace SharpEmu.Libs.Gpu;

/// <summary>
/// V74.0.110.0.1
/// Compatibility bridge for the V74.0.110 waiter-priority experiment.
///
/// The original V74.0.110 patch added calls through IGuestGpuBackend to two
/// backend-specific progress helpers but did not add them to the interface.
/// Keeping this as an extension adapter avoids changing the process-wide GPU ABI
/// and lets Vulkan/other backends opt into the helpers without forcing every
/// backend implementation to change at once.
/// </summary>
internal static class GuestGpuBackendV740110Extensions
{
    private static readonly object CacheGate = new();
    private static readonly Dictionary<(Type Type, string Name, int Arity), MethodInfo?> MethodCache = new();

    private static int _completedFallbackLogged;
    private static int _progressFallbackLogged;

    // params object?[] deliberately accepts the exact V74.0.110 call shapes
    // without leaking Vulkan-only parameter types into IGuestGpuBackend.
    internal static bool IsGuestWorkCompletedV740110(
        this IGuestGpuBackend backend,
        params object?[] args)
    {
        if (backend is null)
        {
            return false;
        }

        MethodInfo? method = ResolveConcreteHelper(
            backend.GetType(),
            nameof(IsGuestWorkCompletedV740110),
            args.Length);

        if (method is not null)
        {
            try
            {
                object? result = method.Invoke(backend, args);
                return result is bool completed && completed;
            }
            catch (TargetInvocationException tie)
            {
                Console.WriteLine(
                    $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                    $"helper={nameof(IsGuestWorkCompletedV740110)} action=invoke-failed " +
                    $"backend={backend.GetType().FullName} error={tie.InnerException?.GetType().Name ?? tie.GetType().Name}");
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                    $"helper={nameof(IsGuestWorkCompletedV740110)} action=invoke-failed " +
                    $"backend={backend.GetType().FullName} error={ex.GetType().Name}");
                return false;
            }
        }

        // Never claim completion without backend evidence.
        if (Interlocked.Exchange(ref _completedFallbackLogged, 1) == 0)
        {
            Console.WriteLine(
                $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                $"helper={nameof(IsGuestWorkCompletedV740110)} action=conservative-fallback " +
                $"backend={backend.GetType().FullName}");
        }

        return false;
    }

    internal static bool WaitForGuestWorkProgressV740110(
        this IGuestGpuBackend backend,
        params object?[] args)
    {
        if (backend is null)
        {
            Thread.Yield();
            return false;
        }

        MethodInfo? method = ResolveConcreteHelper(
            backend.GetType(),
            nameof(WaitForGuestWorkProgressV740110),
            args.Length);

        if (method is not null)
        {
            try
            {
                object? result = method.Invoke(backend, args);

                // A concrete helper may be void or bool.  A void helper did the
                // progress wait successfully; a bool helper communicates whether
                // progress was observed.
                if (method.ReturnType == typeof(void))
                {
                    return true;
                }

                return result is bool progressed && progressed;
            }
            catch (TargetInvocationException tie)
            {
                Console.WriteLine(
                    $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                    $"helper={nameof(WaitForGuestWorkProgressV740110)} action=invoke-failed " +
                    $"backend={backend.GetType().FullName} error={tie.InnerException?.GetType().Name ?? tie.GetType().Name}");
                Thread.Yield();
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                    $"helper={nameof(WaitForGuestWorkProgressV740110)} action=invoke-failed " +
                    $"backend={backend.GetType().FullName} error={ex.GetType().Name}");
                Thread.Yield();
                return false;
            }
        }

        if (Interlocked.Exchange(ref _progressFallbackLogged, 1) == 0)
        {
            Console.WriteLine(
                $"[V74.0.110.0.1][GPU_PROGRESS_BRIDGE] " +
                $"helper={nameof(WaitForGuestWorkProgressV740110)} action=yield-fallback " +
                $"backend={backend.GetType().FullName}");
        }

        // Conservative portable fallback: do not block for an invented timeout
        // and do not report completion.  Yield once so the producer can advance.
        Thread.Yield();
        return false;
    }

    private static MethodInfo? ResolveConcreteHelper(Type type, string name, int arity)
    {
        var key = (type, name, arity);

        lock (CacheGate)
        {
            if (MethodCache.TryGetValue(key, out MethodInfo? cached))
            {
                return cached;
            }

            MethodInfo? resolved = type
                .GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .FirstOrDefault(m =>
                    m.Name == name &&
                    !m.IsStatic &&
                    m.GetParameters().Length == arity &&
                    m.DeclaringType != typeof(GuestGpuBackendV740110Extensions));

            MethodCache[key] = resolved;
            return resolved;
        }
    }
}
