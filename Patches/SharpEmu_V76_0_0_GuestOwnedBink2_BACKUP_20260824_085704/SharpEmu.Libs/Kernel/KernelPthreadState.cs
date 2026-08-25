// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;
using SharpEmu.HLE;

namespace SharpEmu.Libs.Kernel;

internal static class KernelPthreadState
{
    private const int ThreadObjectSize = 0x1000;

    private static readonly ConcurrentDictionary<ulong, ThreadIdentity> Threads = new();
    private static readonly byte[] ZeroThreadObject = new byte[ThreadObjectSize];
    private static long _nextUniqueThreadId = 1;

    [ThreadStatic]
    private static ulong _currentThreadHandle;

    [ThreadStatic]
    private static ulong _currentThreadUniqueId;

    // SHARPEMU_PTHREAD_IDENTITY_CACHE_V1_8_24
    // Persistent guest runners remain bound to a guest pthread for long
    // stretches. Cache its already-registered identity per host thread so
    // pthread/TLS/mutex hot calls do not hit ConcurrentDictionary each time.
    [ThreadStatic]
    private static ulong _cachedGuestThreadHandleV1824;

    [ThreadStatic]
    private static ulong _cachedGuestThreadUniqueIdV1824;

    internal readonly record struct ThreadIdentity(ulong UniqueId, string Name);

    internal static ulong GetCurrentThreadHandle()
    {
        var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;
        if (guestThreadHandle != 0)
        {
            if (_cachedGuestThreadHandleV1824 != guestThreadHandle)
            {
                var identity = EnsureGuestThreadIdentity(guestThreadHandle);
                _cachedGuestThreadHandleV1824 = guestThreadHandle;
                _cachedGuestThreadUniqueIdV1824 = identity.UniqueId;
            }

            return guestThreadHandle;
        }

        EnsureCurrentThreadRegistered();
        return _currentThreadHandle;
    }

    internal static ulong GetCurrentThreadUniqueId()
    {
        var guestThreadHandle = GuestThreadExecution.CurrentGuestThreadHandle;
        if (guestThreadHandle != 0)
        {
            if (_cachedGuestThreadHandleV1824 != guestThreadHandle)
            {
                var identity = EnsureGuestThreadIdentity(guestThreadHandle);
                _cachedGuestThreadHandleV1824 = guestThreadHandle;
                _cachedGuestThreadUniqueIdV1824 = identity.UniqueId;
            }

            return _cachedGuestThreadUniqueIdV1824;
        }

        EnsureCurrentThreadRegistered();
        return _currentThreadUniqueId;
    }

    internal static string DescribeThreadHandle(ulong threadHandle)
    {
        if (threadHandle == 0)
        {
            return "none";
        }

        return TryGetThreadIdentity(threadHandle, out var identity)
            ? $"0x{threadHandle:X16}('{identity.Name}')"
            : $"0x{threadHandle:X16}";
    }

    internal static ulong CreateThreadHandle(string name)
    {
        var uniqueId = unchecked((ulong)Interlocked.Increment(ref _nextUniqueThreadId));
        return AllocateThreadHandle(uniqueId, name);
    }

    internal static bool TryGetThreadIdentity(ulong threadHandle, out ThreadIdentity identity)
    {
        return Threads.TryGetValue(threadHandle, out identity);
    }

    internal static bool TryGetCurrentThreadIdentity(
        out ulong threadHandle,
        out ThreadIdentity identity)
    {
        threadHandle = GuestThreadExecution.CurrentGuestThreadHandle;
        if (threadHandle != 0 && TryGetThreadIdentity(threadHandle, out identity))
        {
            return true;
        }

        threadHandle = _currentThreadHandle;
        if (threadHandle != 0 && TryGetThreadIdentity(threadHandle, out identity))
        {
            return true;
        }

        identity = default;
        return false;
    }

    private static ThreadIdentity EnsureGuestThreadIdentity(ulong guestThreadHandle)
    {
        if (Threads.TryGetValue(guestThreadHandle, out var existing))
        {
            return existing;
        }

        var uniqueId = unchecked((ulong)Interlocked.Increment(ref _nextUniqueThreadId));
        var identity = new ThreadIdentity(uniqueId, $"Guest-0x{guestThreadHandle:X}");
        return Threads.GetOrAdd(guestThreadHandle, identity);
    }

    private static void EnsureCurrentThreadRegistered()
    {
        if (_currentThreadHandle != 0)
        {
            return;
        }

        var uniqueId = unchecked((ulong)Interlocked.Increment(ref _nextUniqueThreadId));
        var name = $"Thread-{uniqueId:X}";
        _currentThreadHandle = AllocateThreadHandle(uniqueId, name);
        _currentThreadUniqueId = uniqueId;
    }

    private static ulong AllocateThreadHandle(ulong uniqueId, string name)
    {
        var pointer = Marshal.AllocHGlobal(ThreadObjectSize);
        Marshal.Copy(ZeroThreadObject, 0, pointer, ThreadObjectSize);

        var handle = unchecked((ulong)pointer.ToInt64());
        Threads[handle] = new ThreadIdentity(uniqueId, string.IsNullOrWhiteSpace(name) ? $"Thread-{uniqueId:X}" : name);

        return handle;
    }
}
