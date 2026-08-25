// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Collections.Concurrent;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V76 guest-owned Bink2 policy.
///
/// V76.0.0 removed host ownership of title-provided Bink2. V76.0.1 added a
/// guest-only playback lifetime signal used solely to make the generic GPU path
/// conservative while the title's real Bink decoder is active. V76.0.2 fixes
/// sampled/storage ownership for final guest Y/UV planes: only initialized GPU
/// producers may feed those descriptors. No host decoder, frame injection,
/// header patch or Bink HLE is introduced.
/// </summary>
internal static class BinkGuestOwnedRuntimeV7600
{
    internal const string Marker = "V76.0.2_GUEST_BINK2_EXACT_YUV_PRODUCER";

    private static readonly ConcurrentDictionary<string, byte> ObservedMovies =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<int, string> OpenGuestMovieFds =
        new();
    private static string? _lastActiveMoviePath;
    private static long _openSerial;
    private static long _closeSerial;

    /// <summary>
    /// True for normal SharpEmu execution. An explicit opt-in is still required
    /// to reach any legacy host-decoder path.
    /// </summary>
    internal static bool Enabled =>
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_ALLOW_HOST_DECODER"),
            "1",
            StringComparison.Ordinal);

    /// <summary>
    /// Conservative GPU scheduling is the V76.0.1 default while a real guest
    /// .bk2 file is open. It can be disabled only for A/B diagnostics.
    /// </summary>
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
        StrictGuestGpuEnabled && IsGuestMovieActive;

    internal static bool SuppressHostUpscaler =>
        StrictGuestGpuEnabled && IsGuestMovieActive;

    /// <summary>
    /// V76.0.2 exact producer binding is on by default and may be disabled only
    /// for guest-only A/B diagnostics. Disabling it does not enable host decode.
    /// </summary>
    internal static bool ExactYuvProducerEnabled =>
        Enabled &&
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_EXACT_YUV_PRODUCER"),
            "0",
            StringComparison.Ordinal);

    internal static int ActiveGuestMovieCount => OpenGuestMovieFds.Count;

    internal static string? ActiveGuestMoviePath =>
        Volatile.Read(ref _lastActiveMoviePath);

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (!Enabled)
        {
            Console.Error.WriteLine(
                "[BINK-GUEST][V76.0.2] legacy_host_decoder_opt_in=True " +
                "guest_owned_default=False");
            return;
        }

        // Keep one owner: the guest. Older initializers must never auto-select
        // RAD/NIHAV/FFmpeg based on host tools or DLLs.
        Set("SHARPEMU_BINK_MODE", "guest");
        Set("SHARPEMU_BINK_AUTO_BOOT", "0");
        Set("SHARPEMU_BINK_BOOT_SEQUENCE", null);
        Set("SHARPEMU_BINK_NATIVE_PREFER", "0");
        Set("SHARPEMU_BINK_NATIVE_EXCLUSIVE", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_CPU", "0");
        Set("SHARPEMU_BINK_THROTTLE_GUEST_GPU", "0");
        Set("SHARPEMU_BINK_HOST_AUDIO", "0");
        Set("SHARPEMU_DS_INTRO_EXTERNAL_AUDIO", "0");
        Set("SHARPEMU_DS_INTRO_WAVEOUT_CLOCK", "0");
        Set("SHARPEMU_DS_ATTRACT_EMBED_AUDIO", "0");
        Set("SHARPEMU_RAD_POST_ATTRACT_LOOP_INTERNAL", "0");
        Set("SHARPEMU_DEMONS_ATTRACT_GUEST_FRAME_HANDOFF", "0");
        Set("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY", "0");
        Set("SHARPEMU_BINK_STARTUP_COMPLETION_SHIM", "0");
        Set("SHARPEMU_BINK_DIRECT_PRESENT_ONLY", "0");

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.2] guest_owned=True host_decoder=False " +
            "ffmpeg_bink=False nihav_bink=False rad_host=False " +
            "header_shim=False frame_injection=False host_audio=False " +
            "strict_guest_gpu_default=True upscaler_during_bink=False " +
            "exact_yuv_gpu_producer=True stale_yuv_cpu_cache=False");
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

        // False means HostMovieBridge did not take ownership. The caller must
        // continue opening/reading the original guest asset.
        return false;
    }

    internal static void GuestMovieOpened(int fd, string? hostPath)
    {
        if (!Enabled || fd < 0 || !IsBinkPath(hostPath))
        {
            return;
        }

        var path = hostPath!;
        if (!OpenGuestMovieFds.TryAdd(fd, path))
        {
            return;
        }

        Volatile.Write(ref _lastActiveMoviePath, path);
        var serial = Interlocked.Increment(ref _openSerial);
        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.2][SESSION] begin " +
            $"n={serial} fd={fd} file='{Path.GetFileName(path)}' " +
            $"active_fds={OpenGuestMovieFds.Count} " +
            $"strict_gpu={(StrictGuestGpuEnabled ? 1 : 0)} " +
            "decode_owner=guest");
    }

    internal static void GuestMovieClosed(int fd, string? hostPath)
    {
        if (!Enabled || fd < 0)
        {
            return;
        }

        if (!OpenGuestMovieFds.TryRemove(fd, out var openedPath))
        {
            return;
        }

        var path = string.IsNullOrWhiteSpace(hostPath) ? openedPath : hostPath!;
        var serial = Interlocked.Increment(ref _closeSerial);
        var remaining = OpenGuestMovieFds.Count;
        if (remaining == 0)
        {
            Volatile.Write(ref _lastActiveMoviePath, null);
        }
        else if (string.Equals(
                     Volatile.Read(ref _lastActiveMoviePath),
                     openedPath,
                     StringComparison.OrdinalIgnoreCase))
        {
            Volatile.Write(
                ref _lastActiveMoviePath,
                OpenGuestMovieFds.Values.FirstOrDefault());
        }

        Console.Error.WriteLine(
            "[BINK-GUEST][V76.0.2][SESSION] end " +
            $"n={serial} fd={fd} file='{Path.GetFileName(path)}' " +
            $"active_fds={remaining} decode_owner=guest");
    }

    internal static bool IsBinkPath(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        path.EndsWith(".bk2", StringComparison.OrdinalIgnoreCase);

    private static void Set(string name, string? value) =>
        Environment.SetEnvironmentVariable(
            name,
            value,
            EnvironmentVariableTarget.Process);
}
