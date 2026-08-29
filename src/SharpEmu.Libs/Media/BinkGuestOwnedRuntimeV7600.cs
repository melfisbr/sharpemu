// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
// V76.2.5.1: host hybrid default for boot Bink (Demon's Souls logo noise fix).
// Guest GPU path still runs when SHARPEMU_BINK_FORCE_GUEST=1.

using System.Collections.Concurrent;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;

namespace SharpEmu.Libs.Media;

internal static class BinkGuestOwnedRuntimeV7600
{
    internal const string Marker = "V76.0.2_GUEST_BINK2_EXACT_YUV_PRODUCER";
    internal const string GuestOnlyMarkerV7618 =
        "V76.0.18_BINK2_HARD_GUEST_ONLY_EBOOT_HANDOFF";

    private static readonly ConcurrentDictionary<string, byte> ObservedMovies =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<int, string> OpenGuestMovieFds =
        new();
    private static string? _lastActiveMoviePath;
    private static long _openSerial;
    private static long _closeSerial;
    private static long _sessionEpoch;
    private static int _hostDecision = -1; // -1 unset, 0 guest, 1 host

    // V76.3.2: a guest title may keep the .bk2 descriptor open after decode
    // has stopped. Using FD lifetime as the strict GPU-ordering lifetime kept
    // graphics/compute lane switches serialized for the rest of the title.
    // Strict ordering now follows actual Bink GPU producer activity instead.
    private static long _lastStrictGpuActivityTick;
    private static int _strictGpuActivityState;
    private static long _strictGpuActivitySerial;
    private static readonly int StrictGpuIdleLeaseMsV7632 =
        ReadIntEnvironment(
            "SHARPEMU_BINK_GUEST_STRICT_IDLE_MS",
            defaultValue: 500,
            minimum: 100,
            maximum: 5000);

    /// <summary>
    /// Guest-owned when host decoder is NOT allowed.
    /// </summary>
    internal static bool Enabled => !HostBinkDecoderAllowed;

    internal static bool HostBinkDecoderAllowed =>
        ResolveHostBinkDecoderAllowed();

    private static bool ResolveHostBinkDecoderAllowed()
    {
        var cached = Volatile.Read(ref _hostDecision);
        if (cached >= 0)
        {
            return cached == 1;
        }

        bool host;
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_FORCE_GUEST"),
                "1",
                StringComparison.Ordinal))
        {
            host = false;
        }
        else if (string.Equals(
                     Environment.GetEnvironmentVariable(
                         "SHARPEMU_BINK_ALLOW_HOST_DECODER"),
                     "0",
                     StringComparison.Ordinal))
        {
            // Explicit opt-out of host.
            host = false;
        }
        else
        {
            // Default: host hybrid ON (boot logos / attract). Guest path was
            // dispatching compute but presenting rainbow noise on NVIDIA.
            host = true;
        }

        Interlocked.CompareExchange(ref _hostDecision, host ? 1 : 0, -1);
        return Volatile.Read(ref _hostDecision) == 1;
    }

    internal static bool StrictGuestGpuEnabled =>
        Enabled &&
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_GUEST_STRICT_GPU"),
            "0",
            StringComparison.Ordinal);

    internal static bool IsGuestMovieActive =>
        Enabled && !OpenGuestMovieFds.IsEmpty;

    internal static bool UseStrictGpuOrdering =>
        StrictGuestGpuEnabled &&
        IsGuestMovieActive &&
        IsStrictGpuActivityLeaseActiveV7632();

    // The host upscaler only needs to stay suppressed while guest Bink is
    // actively producing/consuming its strict YUV pipeline. A stale open FD
    // must not disable DLSS/FSR for later UI or gameplay.
    internal static bool SuppressHostUpscaler => UseStrictGpuOrdering;

    internal static bool ExactYuvProducerEnabled =>
        Enabled &&
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_EXACT_YUV_PRODUCER"),
            "0",
            StringComparison.Ordinal);

    internal static bool YuvSessionEpochEnabled =>
        ExactYuvProducerEnabled &&
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_YUV_SESSION_EPOCH"),
            "0",
            StringComparison.Ordinal);

    internal static long ActiveSessionEpoch =>
        IsGuestMovieActive ? Volatile.Read(ref _sessionEpoch) : 0;

    internal static int ActiveGuestMovieCount => OpenGuestMovieFds.Count;

    internal static string? ActiveGuestMoviePath =>
        Volatile.Read(ref _lastActiveMoviePath);

    [ModuleInitializer]
    internal static void Initialize()
    {
        var hostAllowed = HostBinkDecoderAllowed;

        if (!hostAllowed)
        {
            Set("SHARPEMU_BINK_MODE", "guest");
            Set("SHARPEMU_BINK_HOST_AUDIO", "0");
            Set("SHARPEMU_BINK_NATIVE_PREFER", "0");
            Set("SHARPEMU_BINK_NATIVE_EXCLUSIVE", "0");
        }
        else
        {
            if (string.IsNullOrEmpty(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE")))
            {
                Set("SHARPEMU_BINK_MODE", "native-rad");
            }

            if (string.IsNullOrEmpty(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO")))
            {
                Set("SHARPEMU_BINK_HOST_AUDIO", "1");
            }

            if (string.IsNullOrEmpty(
                    Environment.GetEnvironmentVariable("SHARPEMU_BINK_NATIVE_PREFER")))
            {
                Set("SHARPEMU_BINK_NATIVE_PREFER", "1");
            }

            Set("SHARPEMU_BINK_ALLOW_HOST_DECODER", "1");
        }

        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_BINK_BOOT_SEQUENCE", null);
        Set("SHARPEMU_BINK_THROTTLE_GUEST_CPU", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");
        Set("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "0");
        Set("SHARPEMU_DS_INTRO_WAVEOUT_CLOCK", "0");
        Set("SHARPEMU_DS_ATTRACT_EMBED_AUDIO", "0");
        Set("SHARPEMU_RAD_POST_ATTRACT_LOOP_INTERNAL", "0");
        Set("SHARPEMU_DEMONS_ATTRACT_GUEST_FRAME_HANDOFF", "0");
        Set("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY", "0");
        Set("SHARPEMU_BINK_STARTUP_COMPLETION_SHIM", "0");
        Set("SHARPEMU_BINK_DIRECT_PRESENT_ONLY", "0");

        Console.Error.WriteLine(
            $"[BINK-GUEST][V76.2.5.1] hard_guest_only={!hostAllowed} " +
            $"host_decoder={hostAllowed} " +
            $"ffmpeg_bink={hostAllowed} nihav_bink={hostAllowed} rad_host={hostAllowed} " +
            $"host_audio={hostAllowed} " +
            "policy=host-hybrid-default-unless-FORCE_GUEST");
    }

    internal static bool ObserveGuestMovie(string? hostPath)
    {
        if (!Enabled || !IsBinkPath(hostPath))
        {
            return false;
        }

        var path = hostPath!;
        var fileName = Path.GetFileName(path);
        if (ObservedMovies.TryAdd(path, 0))
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.2] natural_guest_movie " +
                $"file='{fileName}' action=observe-only " +
                "host_takeover=False header_patch=False wait=False");
        }

        return true;
    }

    internal static bool GuestMovieOpened(int fd, string? hostPath)
    {
        if (!Enabled || fd < 0 || !IsBinkPath(hostPath))
        {
            return false;
        }

        var path = hostPath!;
        var previousPath = Volatile.Read(ref _lastActiveMoviePath);
        var startsNewSessionV7632 =
            string.IsNullOrEmpty(previousPath) ||
            !string.Equals(previousPath, path, StringComparison.OrdinalIgnoreCase) ||
            !IsStrictGpuActivityLeaseActiveV7632(logExpiry: false);

        OpenGuestMovieFds[fd] = path;
        Volatile.Write(ref _lastActiveMoviePath, path);
        var n = Interlocked.Increment(ref _openSerial);
        if (n == 1 || OpenGuestMovieFds.Count == 1 || startsNewSessionV7632)
        {
            Interlocked.Increment(ref _sessionEpoch);
        }
        NoteGuestBinkGpuActivityV7632("movie-open");

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.2][SESSION] begin " +
            $"n={n} fd={fd} file='{Path.GetFileName(path)}' " +
            $"active_fds={OpenGuestMovieFds.Count} " +
            $"strict_gpu={(StrictGuestGpuEnabled ? 1 : 0)} " +
            "decode_owner=guest");

        return true;
    }

    internal static void GuestMovieClosed(int fd, string? hostPath)
    {
        if (!Enabled || fd < 0)
        {
            return;
        }

        OpenGuestMovieFds.TryRemove(fd, out _);
        Interlocked.Increment(ref _closeSerial);
        if (OpenGuestMovieFds.IsEmpty)
        {
            Volatile.Write(ref _lastActiveMoviePath, null);
        }
    }

    internal static void NoteGuestBinkGpuActivityV7632(string source)
    {
        if (!StrictGuestGpuEnabled)
        {
            return;
        }

        Volatile.Write(ref _lastStrictGpuActivityTick, Environment.TickCount64);
        var serial = Interlocked.Increment(ref _strictGpuActivitySerial);
        var previousState = Interlocked.Exchange(ref _strictGpuActivityState, 1);
        if (previousState == 0)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.3.2][STRICT-ACTIVITY] " +
                $"action=begin serial={serial} source={source} " +
                $"lease_ms={StrictGpuIdleLeaseMsV7632} " +
                $"file='{Path.GetFileName(ActiveGuestMoviePath)}'");
        }
    }

    private static bool IsStrictGpuActivityLeaseActiveV7632(bool logExpiry = true)
    {
        var last = Volatile.Read(ref _lastStrictGpuActivityTick);
        if (last <= 0)
        {
            return false;
        }

        var idleMs = Environment.TickCount64 - last;
        if (idleMs <= StrictGpuIdleLeaseMsV7632)
        {
            return true;
        }

        if (Interlocked.Exchange(ref _strictGpuActivityState, 0) != 0 && logExpiry)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.3.2][STRICT-ACTIVITY] " +
                $"action=expire idle_ms={idleMs} lease_ms={StrictGpuIdleLeaseMsV7632} " +
                $"active_fds={OpenGuestMovieFds.Count} " +
                "effect=restore-normal-graphics-compute-parallelism");
        }

        return false;
    }

    private static int ReadIntEnvironment(
        string name,
        int defaultValue,
        int minimum,
        int maximum)
    {
        var raw = Environment.GetEnvironmentVariable(name);
        return int.TryParse(raw, out var value)
            ? Math.Clamp(value, minimum, maximum)
            : defaultValue;
    }

    internal static bool IsBinkPath(string? hostPath)
    {
        if (string.IsNullOrEmpty(hostPath))
        {
            return false;
        }

        var ext = Path.GetExtension(hostPath);
        return ext.Equals(".bk2", StringComparison.OrdinalIgnoreCase) ||
               ext.Equals(".bik", StringComparison.OrdinalIgnoreCase) ||
               ext.Equals(".bik2", StringComparison.OrdinalIgnoreCase);
    }

    private static void Set(string name, string? value) =>
        Environment.SetEnvironmentVariable(
            name,
            value,
            EnvironmentVariableTarget.Process);
}
