// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V75.0.0 stable SharpEmu-owned ABI for an in-process Bink SDK adapter.
///
/// This class does not bind SharpEmu to a particular Bink SDK header/layout.
/// The companion SharpEmu.BinkNative.dll owns that version-sensitive boundary.
/// </summary>
internal static class BinkNativeSdkAbiV7500
{
    internal const uint ExpectedAbiVersion = 0x0001_0000;

    internal const uint CapabilityVideo = 1u << 0;
    internal const uint CapabilityEmbeddedAudio = 1u << 1;
    internal const uint CapabilityClock = 1u << 2;
    internal const uint CapabilityBgra = 1u << 3;
    internal const uint CapabilityGpuTexture = 1u << 4;

    internal const uint InfoFlagEmbeddedAudioActive = 1u << 0;

    private static readonly Lazy<Api?> CachedApi = new(LoadApi);

    internal static bool IsAvailable => CachedApi.Value is not null;

    internal static string? LibraryPath => CachedApi.Value?.Path;

    internal static uint BuildCapabilities => CachedApi.Value?.BuildCapabilities ?? 0;

    internal static bool TryOpen(
        string moviePath,
        out nint movie,
        out NativeMovieInfo info,
        out string error)
    {
        movie = 0;
        info = default;
        error = string.Empty;

        var api = CachedApi.Value;
        if (api is null)
        {
            error = "native-adapter-unavailable";
            return false;
        }

        var utf8 = Marshal.StringToCoTaskMemUTF8(moviePath);
        try
        {
            movie = api.OpenUtf8(utf8, 0, out info);
        }
        finally
        {
            Marshal.FreeCoTaskMem(utf8);
        }

        if (movie != 0)
        {
            return true;
        }

        error = ReadLastError(api);
        return false;
    }

    internal static unsafe int DecodeBgra(
        nint movie,
        Span<byte> destination,
        int pitch)
    {
        var api = CachedApi.Value
            ?? throw new InvalidOperationException(
                "SharpEmu.BinkNative.dll is not available.");

        fixed (byte* destinationPointer = destination)
        {
            return api.DecodeBgra(
                movie,
                (nint)destinationPointer,
                checked((nuint)destination.Length),
                pitch);
        }
    }

    internal static void NotifyPresented(nint movie)
    {
        var api = CachedApi.Value;
        if (api is not null && movie != 0)
        {
            api.NotifyPresented?.Invoke(movie);
        }
    }

    internal static bool TryGetClockSeconds(
        nint movie,
        out double seconds)
    {
        seconds = 0;
        var api = CachedApi.Value;
        if (api is null ||
            api.GetClockMicroseconds(movie, out var microseconds) == 0 ||
            microseconds < 0)
        {
            return false;
        }

        seconds = microseconds / 1_000_000.0;
        return double.IsFinite(seconds);
    }

    internal static void RequestSkip(nint movie)
    {
        var api = CachedApi.Value;
        if (api is not null && movie != 0)
        {
            api.RequestSkip(movie);
        }
    }

    internal static void Close(nint movie)
    {
        var api = CachedApi.Value;
        if (api is not null && movie != 0)
        {
            api.Close(movie);
        }
    }

    internal static string LastError
    {
        get
        {
            var api = CachedApi.Value;
            return api is null
                ? "native-adapter-unavailable"
                : ReadLastError(api);
        }
    }

    private static Api? LoadApi()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        foreach (var candidate in EnumerateCandidates())
        {
            if (!NativeLibrary.TryLoad(candidate, out var library))
            {
                continue;
            }

            try
            {
                var abiVersion = LoadDelegate<AbiVersionDelegate>(
                    library,
                    "se_bink_abi_version");

                var version = abiVersion();
                if (version != ExpectedAbiVersion)
                {
                    Console.Error.WriteLine(
                        "[BINK-NATIVE][V75.0.0] adapter_rejected " +
                        $"path='{candidate}' abi=0x{version:X8} " +
                        $"expected=0x{ExpectedAbiVersion:X8}");
                    NativeLibrary.Free(library);
                    continue;
                }

                var api = new Api(
                    library,
                    candidate,
                    abiVersion,
                    LoadDelegate<BuildCapabilitiesDelegate>(
                        library,
                        "se_bink_build_capabilities"),
                    LoadDelegate<OpenUtf8Delegate>(
                        library,
                        "se_bink_open_utf8"),
                    LoadDelegate<DecodeBgraDelegate>(
                        library,
                        "se_bink_decode_bgra"),
                    LoadDelegate<GetClockMicrosecondsDelegate>(
                        library,
                        "se_bink_get_clock_us"),
                    LoadDelegate<RequestSkipDelegate>(
                        library,
                        "se_bink_request_skip"),
                    LoadDelegate<CloseDelegate>(
                        library,
                        "se_bink_close"),
                    TryLoadDelegate<NotifyPresentedDelegate>(
                        library,
                        "se_bink_notify_presented"),
                    LoadDelegate<LastErrorUtf8Delegate>(
                        library,
                        "se_bink_last_error_utf8"));

                Console.Error.WriteLine(
                    "[BINK-NATIVE][V75.0.0] adapter_loaded " +
                    $"path='{candidate}' abi=0x{version:X8} " +
                    $"caps=0x{api.BuildCapabilities:X8}");
                return api;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(
                    "[BINK-NATIVE][V75.0.0] adapter_load_failed " +
                    $"path='{candidate}' type={exception.GetType().Name} " +
                    $"message='{Sanitize(exception.Message)}'");
                NativeLibrary.Free(library);
            }
        }

        return null;
    }

    private static IEnumerable<string> EnumerateCandidates()
    {
        var explicitPath =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_NATIVE_DLL");

        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            yield return Path.GetFullPath(
                explicitPath.Trim().Trim('"'));
        }

        yield return Path.Combine(
            AppContext.BaseDirectory,
            "plugins",
            "bink2",
            "SharpEmu.BinkNative.dll");

        yield return Path.Combine(
            AppContext.BaseDirectory,
            "SharpEmu.BinkNative.dll");
    }

    private static T LoadDelegate<T>(
        nint library,
        string export)
        where T : Delegate
    {
        var pointer = NativeLibrary.GetExport(
            library,
            export);
        return Marshal.GetDelegateForFunctionPointer<T>(
            pointer);
    }

    private static T? TryLoadDelegate<T>(
        nint library,
        string export)
        where T : Delegate
    {
        return NativeLibrary.TryGetExport(library, export, out var pointer)
            ? Marshal.GetDelegateForFunctionPointer<T>(pointer)
            : null;
    }

    private static string ReadLastError(Api api)
    {
        var pointer = api.LastErrorUtf8();
        return pointer == 0
            ? "unknown-native-error"
            : Marshal.PtrToStringUTF8(pointer)
              ?? "unknown-native-error";
    }

    private static string Sanitize(string value) =>
        value.Replace('\r', ' ').Replace('\n', ' ');

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeMovieInfo
    {
        internal uint Width;
        internal uint Height;
        internal uint FramesPerSecondNumerator;
        internal uint FramesPerSecondDenominator;
        internal uint FrameCount;
        internal uint AudioTrackCount;
        internal uint Flags;
        internal uint Reserved;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint AbiVersionDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint BuildCapabilitiesDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate nint OpenUtf8Delegate(
        nint utf8Path,
        uint flags,
        out NativeMovieInfo info);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int DecodeBgraDelegate(
        nint movie,
        nint destination,
        nuint destinationBytes,
        int pitch);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetClockMicrosecondsDelegate(
        nint movie,
        out long microseconds);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void RequestSkipDelegate(nint movie);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CloseDelegate(nint movie);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void NotifyPresentedDelegate(nint movie);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate nint LastErrorUtf8Delegate();

    private sealed class Api
    {
        internal Api(
            nint library,
            string path,
            AbiVersionDelegate abiVersion,
            BuildCapabilitiesDelegate buildCapabilities,
            OpenUtf8Delegate openUtf8,
            DecodeBgraDelegate decodeBgra,
            GetClockMicrosecondsDelegate getClockMicroseconds,
            RequestSkipDelegate requestSkip,
            CloseDelegate close,
            NotifyPresentedDelegate? notifyPresented,
            LastErrorUtf8Delegate lastErrorUtf8)
        {
            Library = library;
            Path = path;
            AbiVersion = abiVersion;
            BuildCapabilitiesCall = buildCapabilities;
            OpenUtf8 = openUtf8;
            DecodeBgra = decodeBgra;
            GetClockMicroseconds = getClockMicroseconds;
            RequestSkip = requestSkip;
            Close = close;
            NotifyPresented = notifyPresented;
            LastErrorUtf8 = lastErrorUtf8;
            BuildCapabilities = BuildCapabilitiesCall();
        }

        internal nint Library { get; }
        internal string Path { get; }
        internal uint BuildCapabilities { get; }
        internal AbiVersionDelegate AbiVersion { get; }
        internal BuildCapabilitiesDelegate BuildCapabilitiesCall { get; }
        internal OpenUtf8Delegate OpenUtf8 { get; }
        internal DecodeBgraDelegate DecodeBgra { get; }
        internal GetClockMicrosecondsDelegate GetClockMicroseconds { get; }
        internal RequestSkipDelegate RequestSkip { get; }
        internal CloseDelegate Close { get; }
        internal NotifyPresentedDelegate? NotifyPresented { get; }
        internal LastErrorUtf8Delegate LastErrorUtf8 { get; }
    }
}
