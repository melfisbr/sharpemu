// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.InteropServices;
using System.Buffers.Binary;
using SharpEmu.Libs.VideoOut;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-side movie bridge for games that decode video inside their own
/// executable instead of going through an HLE decoder.
///
/// Such a game never imports libSceVideodec or sceAvPlayer, so no HLE export
/// can see its movie frames. Kernel file opens identify the active movie and
/// the presenter requests BGRA frames from <see cref="FfmpegVideoDecoder"/> —
/// the same decoder sceAvPlayer uses, so every format is handled in one place.
/// </summary>
internal static class HostMovieBridge
{
    private const uint MaxDimension = 16384;
    private const uint MaxHostVideoWidth = 1920;
    private const uint MaxHostVideoHeight = 1080;

    private static readonly string[] SelfDecodedMovieExtensions = [".bk2"];

    private static readonly object V34MovieProbeGate = new();
    private static readonly Dictionary<string, bool> V34MovieProbeCache =
        new(StringComparer.OrdinalIgnoreCase);
    private const int V34MovieProbeCacheLimit = 4096;

    private static bool V34IsSelfDecodedMovieByContent(string hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath))
        {
            return false;
        }

        lock (V34MovieProbeGate)
        {
            if (V34MovieProbeCache.TryGetValue(hostPath, out var cached))
            {
                return cached;
            }
        }

        // TryReadBinkInfo already validates the KB2 magic and the core
        // Bink2 header fields used by this bridge.
        var isBink2 = TryReadBinkInfo(hostPath, out _);

        lock (V34MovieProbeGate)
        {
            if (V34MovieProbeCache.Count >= V34MovieProbeCacheLimit)
            {
                V34MovieProbeCache.Clear();
            }

            V34MovieProbeCache[hostPath] = isBink2;
        }

        if (isBink2 &&
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_TRACE_MOVIE_IO"),
                "1",
                StringComparison.Ordinal))
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] movie_candidate signature=KB2 path='" +
                hostPath + "'");
        }

        return isBink2;
    }

    private static bool IsSelfDecodedMovie(string hostPath)
    {
        foreach (var extension in SelfDecodedMovieExtensions)
        {
            if (hostPath.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        // SHARPEMU_V34_0_2_BINK_SIGNATURE
        // Some titles open Bink2 containers through opaque/non-.bk2 paths.
        // Reuse SharpEmu's existing validated KB2 parser instead of guessing by filename.
        if (V34IsSelfDecodedMovieByContent(hostPath))
        {
            return true;
        }

        return false;
    }

    private static readonly object Gate = new();
    private static string? _activePath;
    private static Bink2MovieInfo _activeInfo;
    private static byte[]? _frameBuffer;
    private static bool _frameBufferPresented;
    private static MediaFramePlayback? _playback;
    private static long _frameSerial;
    private static uint _presentationWidth = MaxHostVideoWidth;
    private static uint _presentationHeight = MaxHostVideoHeight;

    internal static bool IsHostPlaybackActive
    {
        get
        {
            lock (Gate)
            {
                return _playback is not null ||
                       _frameBuffer is not null ||
                       _radPlayback is not null;
            }
        }
    }

    internal static void SetPresentationSize(uint width, uint height)
    {
        if (width == 0 || height == 0)
        {
            return;
        }

        lock (Gate)
        {
            _presentationWidth = Math.Min(width, MaxHostVideoWidth);
            _presentationHeight = Math.Min(height, MaxHostVideoHeight);
        }

        TryStartConfiguredBootSequence();
    }

    /// <summary>
    /// Returns true only when movie skipping was explicitly requested. Without
    /// a host adapter the guest must be allowed to run the Bink implementation
    /// statically linked into its executable.
    /// </summary>
    internal static bool ShouldSkipGuestMovie(string hostPath) =>
        IsSelfDecodedMovie(hostPath) &&
        ResolveMode() == MovieMode.Skip;

    /// <summary>
    /// Starts or queues host decoding. Decoded frames are only exposed as a
    /// sampled guest texture; presentation and UI composition remain guest-owned.
    /// </summary>
    // V61.13.4_BINK2_NATURAL_FALLBACK
    private static int _naturalGuestMovieObservations;

    // V31.7.9_GUEST_REPLAY_DEDUPE
    // The host may show the canonical startup logos before the guest reaches its
    // native Bink state machine. When that state machine later asks for the same
    // startup asset, acknowledge the already-presented movie instead of launching
    // a second RAD process. The reconciliation window closes on the first natural
    // non-bootstrap movie so legitimate later replays are not globally suppressed.
    private static readonly System.Collections.Generic.HashSet<string> V3179HostBootPresented =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly System.Collections.Generic.HashSet<string> V3179GuestBootReplaySuppressed =
        new(StringComparer.OrdinalIgnoreCase);
    private static bool V3179GuestBootReconciliationOpen = true;

    // V31.7.11_GUEST_CLOCK_SESSION_PROBE
    // Mirrors only sparse guest-media state transitions into the existing Bink
    // session file so the diagnostic runner can wait for the real EBOOT state
    // machine without enabling broad/high-volume tracing.
    private static void WriteV31711GuestClockSessionMarker(
        string kind,
        string fileName,
        string detail = "")
    {
        var sessionPath = Environment.GetEnvironmentVariable("SHARPEMU_GUEST_CLOCK_LOG");
        if (string.IsNullOrWhiteSpace(sessionPath))
        {
            return;
        }

        try
        {
            var line =
                $"{DateTime.UtcNow:O} pid={Environment.ProcessId} " +
                $"tid={Environment.CurrentManagedThreadId} [{kind}] " +
                $"file='{fileName}'{detail}{Environment.NewLine}";
            File.AppendAllText(
                sessionPath,
                line,
                new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch
        {
            // Diagnostic-only marker: never perturb guest execution.
        }
    }

    private static bool IsV3179CanonicalBootstrapMovie(string fileName) =>
        fileName.Equals("ps_studios_logo.bk2", StringComparison.OrdinalIgnoreCase) ||
        fileName.Equals("logo_intro.bk2", StringComparison.OrdinalIgnoreCase) ||
        fileName.Equals("logo_intro_loop.bk2", StringComparison.OrdinalIgnoreCase);

    private static bool TrySuppressV3179GuestBootReplay(
        string fileName,
        out bool firstSuppression)
    {
        firstSuppression = false;
        if (!string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY"),
                "1",
                StringComparison.Ordinal))
        {
            return false;
        }

        lock (Gate)
        {
            if (!V3179GuestBootReconciliationOpen ||
                _directPresentationActive ||
                Volatile.Read(ref _configuredBootSequenceStarted) == 0)
            {
                return false;
            }

            if (!IsV3179CanonicalBootstrapMovie(fileName))
            {
                V3179GuestBootReconciliationOpen = false;
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.guest_boot_reconciliation_completed " +
                    $"next='{fileName}' deduped={V3179GuestBootReplaySuppressed.Count}");
                WriteV31711GuestClockSessionMarker(
                    "GUEST_BOOT_RECONCILIATION_COMPLETED",
                    fileName,
                    $" deduped={V3179GuestBootReplaySuppressed.Count}");
                return false;
            }

            if (!V3179HostBootPresented.Contains(fileName))
            {
                return false;
            }

            firstSuppression = V3179GuestBootReplaySuppressed.Add(fileName);
            return true;
        }
    }

    // V31.7.14_GUEST_FRAME_ATTRACT_HANDOFF

    // V31.7.14.2_STRUCTURAL_BOOT_REWRITE keeps this handoff independent of

    // exact source formatting in TryStartConfiguredBootSequence().

    private static int V31714AttractHandoffQueued;

    private static int V31714AttractHandoffStarted;



    internal static void NotifyV31714GuestFirstFrameAttractHandoff()

    {

        if (!string.Equals(

                Environment.GetEnvironmentVariable("SHARPEMU_DEMONS_ATTRACT_GUEST_FRAME_HANDOFF"),

                "1",

                StringComparison.Ordinal))

        {

            return;

        }



        if (Volatile.Read(ref _configuredBootSequenceStarted) == 0)

        {

            return;

        }



        if (Interlocked.CompareExchange(ref V31714AttractHandoffQueued, 1, 0) != 0)

        {

            return;

        }



        Console.Error.WriteLine(

            "[LOADER][INFO] bink2.v31714_guest_frame_attract_handoff_queued " +

            "trigger=first-guest-frame");

        WriteV31711GuestClockSessionMarker(

            "GUEST_FRAME_ATTRACT_HANDOFF_QUEUED",

            "attract_movie.bk2",

            " trigger=first-guest-frame");

        System.Threading.ThreadPool.QueueUserWorkItem(

            static _ => TryStartV31714AttractFromGuestBoundary());

    }



    private static void TryStartV31714AttractFromGuestBoundary()

    {

        var app0 = Environment.GetEnvironmentVariable("SHARPEMU_APP0_DIR");

        if (string.IsNullOrWhiteSpace(app0) || !Directory.Exists(app0))

        {

            Console.Error.WriteLine(

                "[LOADER][WARN] bink2.v31714_guest_frame_attract_handoff_failed reason=app0-missing");

            return;

        }



        var attractPath = Path.Combine(app0, "movies", "attract_movie.bk2");

        if (!File.Exists(attractPath) || !TryReadBinkInfo(attractPath, out _))

        {

            Console.Error.WriteLine(

                "[LOADER][WARN] bink2.v31714_guest_frame_attract_handoff_failed " +

                "reason=attract-missing-or-invalid");

            return;

        }



        // FIRST_GUEST_FRAME is normally after direct_boot_completed. Keep this

        // state-based wait only as a race guard; it is not a presentation delay.

        var deadline = Environment.TickCount64 + 10_000;

        while (true)

        {

            var hostBusy = false;

            lock (Gate)

            {

                hostBusy = _directPresentationActive ||

                           _playback is not null ||

                           _frameBuffer is not null ||

                           _radPlayback is not null ||

                           PendingMoviePaths.Count != 0;

            }



            if (!hostBusy)

            {

                break;

            }



            if (Environment.TickCount64 >= deadline)

            {

                Console.Error.WriteLine(

                    "[LOADER][WARN] bink2.v31714_guest_frame_attract_handoff_failed " +

                    "reason=host-still-busy-after-guest-frame");

                return;

            }



            Thread.Sleep(10);

        }



        if (Interlocked.CompareExchange(ref V31714AttractHandoffStarted, 1, 0) != 0)

        {

            return;

        }



        lock (Gate)

        {

            if (V3179GuestBootReconciliationOpen)

            {

                V3179GuestBootReconciliationOpen = false;

                Console.Error.WriteLine(

                    $"[LOADER][INFO] bink2.guest_boot_reconciliation_completed " +

                    $"next='attract_movie.bk2' deduped={V3179GuestBootReplaySuppressed.Count} " +

                    "source=guest-first-frame-handoff");

            }

        }



        Console.Error.WriteLine(

            "[LOADER][INFO] bink2.v31714_guest_frame_attract_handoff_started " +

            "file='attract_movie.bk2' trigger=first-guest-frame natural_guest_request=False");

        WriteV31711GuestClockSessionMarker(

            "GUEST_FRAME_ATTRACT_HANDOFF_STARTED",

            "attract_movie.bk2",

            " trigger=first-guest-frame natural_guest_request=False");



        var attached = ObserveMovie(attractPath, naturalGuestRequest: false);
        // V31.7.15_POST_ATTRACT_LOGO_LOOP
        // At this point attract_movie is already the active host movie.
        // ObserveMovie therefore places logo_intro_loop in the existing FIFO.
        // AttachNextQueuedMovieLocked starts it only after attract completes.
        if (attached)
        {
            var postAttractLoopPath =
                Path.Combine(app0, "movies", "logo_intro_loop.bk2");

            if (File.Exists(postAttractLoopPath) &&
                TryReadBinkInfo(postAttractLoopPath, out _))
            {
                var loopQueued =
                    ObserveMovie(
                        postAttractLoopPath,
                        naturalGuestRequest: false);

                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.v31715_post_attract_loop_queued " +
                    $"file='logo_intro_loop.bk2' after='attract_movie.bk2' " +
                    $"queued={loopQueued} source=existing-host-movie-fifo");
                WriteV31711GuestClockSessionMarker(
                    "POST_ATTRACT_LOGO_LOOP_QUEUED",
                    "logo_intro_loop.bk2",
                    $" after=attract_movie.bk2 queued={loopQueued}");
            }
            else
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.v31715_post_attract_loop_missing " +
                    "file='logo_intro_loop.bk2'");
            }
        }

        Console.Error.WriteLine(

            $"[LOADER][INFO] bink2.v31714_guest_frame_attract_handoff_result " +

            $"file='attract_movie.bk2' attached={attached}");

        if (!attached)

        {

            WriteV31711GuestClockSessionMarker(

                "GUEST_FRAME_ATTRACT_HANDOFF_FAILED",

                "attract_movie.bk2",

                " reason=observe-movie-returned-false");

        }

    }

    internal static bool ObserveGuestMovie(string hostPath) =>
        ObserveMovie(hostPath, naturalGuestRequest: true);

    private static bool ObserveMovie(string hostPath, bool naturalGuestRequest)
    {
        if (!IsSelfDecodedMovie(hostPath) || !File.Exists(hostPath))
        {
            return false;
        }

        var v3179FileName = Path.GetFileName(hostPath);
        if (!naturalGuestRequest && IsV3179CanonicalBootstrapMovie(v3179FileName))
        {
            lock (Gate)
            {
                if (_directPresentationActive)
                {
                    V3179HostBootPresented.Add(v3179FileName);
                }
            }
        }

        if (naturalGuestRequest)
        {
            if (TrySuppressV3179GuestBootReplay(v3179FileName, out var firstSuppression))
            {
                var dedupeObserved = Interlocked.Increment(ref _naturalGuestMovieObservations);
                if (dedupeObserved <= 8)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][INFO] bink2.natural_guest_movie_observed n={dedupeObserved} " +
                        $"file='{v3179FileName}'");
                }
                WriteV31711GuestClockSessionMarker(
                    "NATURAL_GUEST_MOVIE_OBSERVED",
                    v3179FileName,
                    $" n={dedupeObserved}");
                if (firstSuppression)
                {
                    Console.Error.WriteLine(
                        $"[LOADER][INFO] bink2.guest_replay_deduped file='{v3179FileName}' " +
                        "reason=already-shown-by-host-direct-boot completion=existing-startup-completion-shim");
                    WriteV31711GuestClockSessionMarker(
                        "GUEST_REPLAY_DEDUPED",
                        v3179FileName,
                        " reason=already-shown-by-host-direct-boot");
                }
                return true;
            }

            var observed = Interlocked.Increment(ref _naturalGuestMovieObservations);
            if (observed <= 4)
            {
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.natural_guest_movie_observed n={observed} " +
                    $"file='{Path.GetFileName(hostPath)}'");
            }
            WriteV31711GuestClockSessionMarker(
                "NATURAL_GUEST_MOVIE_OBSERVED",
                v3179FileName,
                $" n={observed}");
        }

        lock (Gate)
        {
            if (string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                return _playback is not null ||
                       _frameBuffer is not null ||
                       _radPlayback is not null;
            }

            var mode = ResolveMode();
            if (mode is MovieMode.Guest or MovieMode.Skip)
            {
                return false;
            }

            if (_playback is not null ||
                _frameBuffer is not null ||
                _radPlayback is not null)
            {
                if (PendingMoviePathSet.Add(hostPath))
                {
                    PendingMoviePaths.Enqueue(hostPath);
                    Console.Error.WriteLine(
                        "[LOADER][INFO] Bink2 bridge queued: " +
                        Path.GetFileName(hostPath));
                }
                return PendingMoviePathSet.Contains(hostPath);
            }

            AttachMovieLocked(hostPath, mode);
            return string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) &&
                   (_playback is not null ||
                    _frameBuffer is not null ||
                    _radPlayback is not null);
        }
    }

    internal static bool TryDecodeNextFrame(
        bool advanceClock,
        out byte[] pixels,
        out uint width,
        out uint height,
        out bool advanced,
        out long frameSerial,
        out string hostPath)
    {
        lock (Gate)
        {
            pixels = [];
            width = 0;
            height = 0;
            advanced = false;
            frameSerial = _frameSerial;
            hostPath = _activePath ?? string.Empty;

            if (_radPlayback is not null)
            {
                if (!_radPlayback.IsFinished)
                {
                    return false;
                }

                var completedPath = _activePath;
                var elapsedSeconds = _radPlayback.ElapsedSeconds;
                var exitCode = _radPlayback.ExitCode;

                CloseActiveLocked();

                Console.Error.WriteLine(
                    "[LOADER][INFO] Bink RAD bridge completed: " +
                    $"{Path.GetFileName(completedPath)} after " +
                    $"{elapsedSeconds:F2}s exit={exitCode?.ToString() ?? "unknown"}");

                AttachNextQueuedMovieLocked();
                return false;
            }

            if (_playback is not null)
            {
                if (!_playback.TryGetFrame(advanceClock, out pixels, out advanced))
                {
                    if (_playback.IsFinished)
                    {
                        var completedPath = _activePath;
                        var progress = _playback.PlaybackProgress;
                        CloseActiveLocked();
                        Console.Error.WriteLine(
                            "[LOADER][INFO] Bink2 bridge completed: " +
                            $"{Path.GetFileName(completedPath)} after " +
                            $"{progress.Seconds:F2}s at frame {progress.FrameIndex}");
                        AttachNextQueuedMovieLocked();
                    }
                    return false;
                }

                width = _activeInfo.Width;
                height = _activeInfo.Height;
                if (advanced)
                {
                    frameSerial = ++_frameSerial;
                }
                return true;
            }

            if (_frameBuffer is null)
            {
                return false;
            }

            pixels = _frameBuffer;
            width = _activeInfo.Width;
            height = _activeInfo.Height;
            advanced = !_frameBufferPresented;
            _frameBufferPresented = true;
            if (advanced)
            {
                frameSerial = ++_frameSerial;
            }
            return true;
        }
    }

    private static bool IsValid(Bink2MovieInfo info) =>
        info.Width > 0 && info.Height > 0 &&
        info.Width <= MaxDimension && info.Height <= MaxDimension &&
        (ulong)info.Width * info.Height * 4 <= int.MaxValue;

    private static int GetFrameBufferLength(Bink2MovieInfo info) =>
        checked((int)((ulong)info.Width * info.Height * 4));

    private static void AttachMovieLocked(string hostPath, MovieMode mode)
    {
        if (mode != MovieMode.Rad)
        {
            BinkHostAudioBridgeV7241.TryStart(hostPath);
        }

        switch (mode)
        {
            case MovieMode.Dummy:
                AttachDummyMovieLocked(hostPath);
                return;
            case MovieMode.Nihav:
                AttachNihavMovieLocked(hostPath);
                return;
            case MovieMode.Ffmpeg:
                AttachFfmpegMovieLocked(hostPath);
                return;
            case MovieMode.Rad:
                // V72.4.3.2.31.4 RAD_REQUIRED_NO_FALLBACK
                // Never hide RAD discovery/start failures by silently switching
                // back to NIHAV; that would reproduce the corrupted-color path.
                if (!AttachRadMovieLocked(hostPath))
                {
                    Console.Error.WriteLine(
                        "[LOADER][ERROR] bink2.rad_required_attach_failed " +
                        $"file='{Path.GetFileName(hostPath)}'");
                }
                return;

            case MovieMode.Native:
                // Stock FFmpeg recognises the KB2 container but does not decode
                // Bink2 video. Prefer the optional NihAV backend for KB2 and
                // retain FFmpeg as the generic fallback for other host movies.
                if (AttachNihavMovieLocked(hostPath))
                {
                    return;
                }
                AttachFfmpegMovieLocked(hostPath);
                return;
        }
    }

    private static bool AttachRadMovieLocked(string hostPath)
    {
        if (!TryReadBinkInfo(hostPath, out var info) ||
            !IsValid(info))
        {
            return false;
        }

        if (!RadBinkExternalPlaybackV7243231.TryStart(
                hostPath,
                out var source) ||
            source is null)
        {
            return false;
        }

        CloseActiveLocked();

        _activePath = hostPath;
        _activeInfo = info;
        _radPlayback = source;

        // RAD owns the embedded Bink audio stream and the playback clock.
        // Do not start SharpEmu's generated WAV/tempo sidecar in this mode.

        Console.Error.WriteLine(
            "[LOADER][INFO] Bink RAD bridge attached: " +
            $"{Path.GetFileName(hostPath)} " +
            $"{info.Width}x{info.Height} @ " +
            $"{info.FramesPerSecondNumerator}/" +
            $"{info.FramesPerSecondDenominator} fps " +
            $"tool='{source.ToolPath}'");
        return true;
    }

    private static bool AttachNihavMovieLocked(string hostPath)
    {
        if (!NihavBink2Decoder.TryOpen(
                hostPath, _presentationWidth, _presentationHeight, out var source) ||
            source is null)
        {
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);
        if (!IsValid(info))
        {
            source.Dispose();
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 NIHAV bridge rejected invalid movie dimensions for '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        AttachPlaybackLocked(hostPath, info, source);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink2 NIHAV bridge attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + " @ " +
            info.FramesPerSecondNumerator + "/" + info.FramesPerSecondDenominator + " fps.");
        return true;
    }

    private static bool AttachFfmpegMovieLocked(string hostPath)
    {
        if (!FfmpegVideoDecoder.TryOpen(
                hostPath, _presentationWidth, _presentationHeight, out var source) ||
            source is null)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 bridge could not open movie '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);
        if (!IsValid(info))
        {
            source.Dispose();
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink2 bridge rejected invalid movie dimensions for '" +
                Path.GetFileName(hostPath) + "'.");
            return false;
        }

        AttachPlaybackLocked(hostPath, info, source);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink2 FFmpeg bridge attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + " @ " +
            info.FramesPerSecondNumerator + "/" + info.FramesPerSecondDenominator + " fps.");
        return true;
    }

    private static MovieMode ResolveMode()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_MODE");

        if (string.Equals(configured, "rad", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "binkplay", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "radvideo", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Rad;
        }
        if (string.Equals(configured, "dummy", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Dummy;
        }

        if (string.Equals(configured, "native", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "auto", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Native;
        }

        if (string.Equals(configured, "nihav", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(configured, "bink2", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Nihav;
        }

        if (string.Equals(configured, "skip", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Skip;
        }

        if (string.Equals(configured, "guest", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Guest;
        }

        if (string.Equals(configured, "ffmpeg", StringComparison.OrdinalIgnoreCase))
        {
            return MovieMode.Ffmpeg;
        }

        // Native is the default. KB2 first tries the optional NihAV backend and
        // then the existing FFmpeg path. If neither host decoder is available,
        // the guest's statically linked movie code remains untouched.
        return MovieMode.Native;
    }

    private static void AttachDummyMovieLocked(string hostPath)
    {
        if (!TryReadBinkInfo(hostPath, out var info) || !IsValid(info))
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] Bink dummy could not read movie header '" +
                Path.GetFileName(hostPath) + "'.");
            return;
        }

        CloseActiveLocked();
        _activePath = hostPath;
        _activeInfo = info;
        _frameBuffer = GC.AllocateUninitializedArray<byte>(GetFrameBufferLength(info));
        _frameBufferPresented = false;
        FillDummyFrame(_frameBuffer, info.Width, info.Height);
        Console.Error.WriteLine(
            "[LOADER][INFO] Bink dummy attached: " + Path.GetFileName(hostPath) + " " +
            info.Width + "x" + info.Height + ".");
    }

    private static void AttachPlaybackLocked(
        string hostPath,
        Bink2MovieInfo info,
        IMediaFrameDecoder decoder)
    {
        CloseActiveLocked();
        _activePath = hostPath;
        _activeInfo = info;
        _playback = new MediaFramePlayback(decoder);
    }

    internal static bool TryReadBinkInfo(string path, out Bink2MovieInfo info)
    {
        info = default;
        Span<byte> header = stackalloc byte[36];
        try
        {
            using var stream = File.OpenRead(path);
            stream.ReadExactly(header);
            if (!header[..3].SequenceEqual("KB2"u8))
            {
                return false;
            }

            info = new Bink2MovieInfo(
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x14, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x18, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x1C, 4)),
                BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(0x20, 4)));
            return info.FramesPerSecondNumerator != 0 &&
                   info.FramesPerSecondDenominator != 0;
        }
        catch (Exception exception) when (exception is IOException or EndOfStreamException)
        {
            return false;
        }
    }

    private static void FillDummyFrame(byte[] pixels, uint width, uint height)
    {
        for (var y = 0u; y < height; y++)
        {
            for (var x = 0u; x < width; x++)
            {
                var offset = checked((int)(((ulong)y * width + x) * 4));
                var band = ((x / 96) + (y / 96)) & 1;
                pixels[offset] = band == 0 ? (byte)0x28 : (byte)0x18;
                pixels[offset + 1] = band == 0 ? (byte)0x18 : (byte)0x28;
                pixels[offset + 2] = 0x10;
                pixels[offset + 3] = 0xFF;
            }
        }
    }


    // V61.13_BINK2_NIHAV_DIRECT_BOOT
    // A title may initialise its statically linked Bink runtime long before it
    // opens the first movie. SHARPEMU_BINK_BOOT_SEQUENCE provides an opt-in
    // compatibility path that plays known boot movies directly through the
    // host presenter, then releases presentation back to the guest.
    private static int _configuredBootSequenceStarted;
    private static int _autoBootFallbackScheduled;
    private static bool _directPresentationActive;
    private static byte[]? _directPresentationFrame;
    private static uint _directPresentationFrameWidth;
    private static uint _directPresentationFrameHeight;
    private static long _directPresentationFrameSerial;
    private static Thread? _directPresentationThread;

    // V72.4.3.2.31.4 RAD_EXTERNAL_BACKEND
    private static RadBinkExternalPlaybackV7243231? _radPlayback;

    internal static bool IsDirectPresentationActive
    {
        get
        {
            lock (Gate)
            {
                return _directPresentationActive;
            }
        }
    }

    internal static bool TryGetDirectPresentation(
        out byte[] pixels,
        out uint width,
        out uint height,
        out long frameSerial)
    {
        lock (Gate)
        {
            pixels = [];
            width = 0;
            height = 0;
            frameSerial = _directPresentationFrameSerial;
            if (!_directPresentationActive || _directPresentationFrame is null)
            {
                return false;
            }

            pixels = _directPresentationFrame;
            width = _directPresentationFrameWidth;
            height = _directPresentationFrameHeight;
            return true;
        }
    }

    private static void TryStartConfiguredBootSequence()
    {
        var configured = Environment.GetEnvironmentVariable("SHARPEMU_BINK_BOOT_SEQUENCE");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var explicitPaths = configured
                .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(Environment.ExpandEnvironmentVariables)
                .Where(static path => !string.IsNullOrWhiteSpace(path))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            TryStartBootSequenceThread(explicitPaths, "explicit", delayMilliseconds: 0);
            return;
        }

        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUTO_BOOT"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        // V61.13.16.8_BINK_BOOT_SEQUENCE_ORDER
        // The host runtime already exports the /app0 root through this variable.
        // Do not hard-limit auto boot to exactly two movies. Demon's Souls uses
        // a deterministic title-startup chain:
        //
        //   ps_studios_logo.bk2 -> logo_intro.bk2 -> logo_intro_loop.bk2
        //
        // logo_intro_loop is the title/Press-Start loop asset. main_menu,
        // main_menu_ngp, attract_movie, story movies and credits are guest-driven
        // and must not be force-played as part of host auto boot.
        var app0 = Environment.GetEnvironmentVariable("SHARPEMU_APP0_DIR");
        if (string.IsNullOrWhiteSpace(app0) || !Directory.Exists(app0))
        {
            return;
        }

        var movieRoot = Path.Combine(app0, "movies");
        // V31.7.14.2_STRUCTURAL_BOOT_REWRITE
        // Host auto boot owns only the two one-shot logos; attract_movie is
        // scheduled from the first real guest-frame compatibility boundary.
        var orderedBootMovieNames = new[]
        {
            "ps_studios_logo.bk2",
            "logo_intro.bk2",
};

        var autoPaths = orderedBootMovieNames
            .Select(name => Path.Combine(movieRoot, name))
            .Where(File.Exists)
            .Where(static path => TryReadBinkInfo(path, out _))
            .ToArray();

        // Automatic fallback still requires the two one-shot startup movies,
        // but it may now continue with any ordered startup assets that exist.
        if (autoPaths.Length < 2 ||
            !string.Equals(
                Path.GetFileName(autoPaths[0]),
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(
                Path.GetFileName(autoPaths[1]),
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.auto_boot_order movies={autoPaths.Length} sequence='" +
            string.Join(" -> ", autoPaths.Select(Path.GetFileName)) + "'");

        if (Interlocked.CompareExchange(ref _autoBootFallbackScheduled, 1, 0) != 0)
        {
            return;
        }

        var graceMilliseconds = 1500;
        if (int.TryParse(
                Environment.GetEnvironmentVariable("SHARPEMU_BINK_AUTO_BOOT_GRACE_MS"),
                out var configuredGrace))
        {
            graceMilliseconds = Math.Clamp(configuredGrace, 0, 10_000);
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.auto_boot_discovered app0='{app0}' " +
            $"movies={autoPaths.Length} grace_ms={graceMilliseconds}");
        TryStartBootSequenceThread(autoPaths, "auto-app0", graceMilliseconds);
    }

    private static void TryStartBootSequenceThread(
        string[] paths,
        string source,
        int delayMilliseconds)
    {
        if (paths.Length == 0 ||
            Volatile.Read(ref _configuredBootSequenceStarted) != 0)
        {
            return;
        }

        _directPresentationThread = new Thread(() =>
        {
            if (delayMilliseconds > 0)
            {
                Thread.Sleep(delayMilliseconds);
            }

            if (source.StartsWith("auto", StringComparison.Ordinal) &&
                Volatile.Read(ref _naturalGuestMovieObservations) != 0)
            {
                Console.Error.WriteLine(
                    $"[LOADER][INFO] bink2.auto_boot_cancelled reason=natural-guest-open " +
                    $"observations={Volatile.Read(ref _naturalGuestMovieObservations)}");
                return;
            }

            if (Interlocked.CompareExchange(ref _configuredBootSequenceStarted, 1, 0) != 0)
            {
                return;
            }

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.boot_sequence_selected source={source} movies={paths.Length}");
            RunConfiguredBootSequence(paths);
        })
        {
            IsBackground = true,
            Name = "SharpEmu Bink2 boot presentation",
        };
        _directPresentationThread.Start();
    }

    private static void RunConfiguredBootSequence(string[] paths)
    {
        var attached = 0;
        lock (Gate)
        {
            _directPresentationActive = true;
            _directPresentationFrame = null;
            _directPresentationFrameWidth = 0;
            _directPresentationFrameHeight = 0;
            _directPresentationFrameSerial = 0;
        }

        Console.Error.WriteLine(
            $"[LOADER][INFO] bink2.direct_boot_started movies={paths.Length} " +
            $"mode={ResolveMode()}");

        foreach (var path in paths)
        {
            if (!File.Exists(path))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.direct_boot_missing path='" + path + "'");
                continue;
            }

            if (!TryReadBinkInfo(path, out _))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.direct_boot_not_bink2 path='" + path + "'");
                continue;
            }

            if (ObserveMovie(path, naturalGuestRequest: false))
            {
                attached++;
            }
        }

        if (attached == 0)
        {
            lock (Gate)
            {
                _directPresentationActive = false;
                _directPresentationFrame = null;
            }
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.direct_boot_no_decoder movies=0");
            return;
        }

        long presentedFrames = 0;
        string? audioPresentationPath = null;
        try
        {
            while (true)
            {
                // V61.13.26.2: while the host owns the boot movie, the guest cannot
                // consume its normal Options event. Convert the configured TAB edge
                // into termination of host-owned direct boot, then restore guest video.
                if (HostOptionsSkipBridgeV6113262.ConsumeRequest())
                {
                    lock (Gate)
                    {
                        PendingMoviePaths.Clear();
                        CloseActiveLocked();
                    }
                    Console.Error.WriteLine(
                        "[LOADER][INFO] options_direct_boot_skip source=TAB action=restore_guest");
                    break;
                }
                if (TryDecodeNextFrame(
                        advanceClock: true,
                        out var pixels,
                        out var width,
                        out var height,
                        out var advanced,
                        out var frameSerial,
                        out var hostPath))
                {
                    if (advanced)
                    {
                        if (!string.Equals(
                                audioPresentationPath,
                                hostPath,
                                StringComparison.OrdinalIgnoreCase))
                        {
                            audioPresentationPath = hostPath;
                            BinkHostAudioBridgeV7241.NotifyPresentationStarted(hostPath);
                            Console.Error.WriteLine(
                                $"[LOADER][INFO] bink2.audio_presentation_sync " +
                                $"file='{Path.GetFileName(hostPath)}' serial={frameSerial}");
                        }

                        var stableFrame = GC.AllocateUninitializedArray<byte>(pixels.Length);
                        Buffer.BlockCopy(pixels, 0, stableFrame, 0, pixels.Length);
                        lock (Gate)
                        {
                            _directPresentationFrame = stableFrame;
                            _directPresentationFrameWidth = width;
                            _directPresentationFrameHeight = height;
                            _directPresentationFrameSerial = frameSerial;
                        }

                        // V61.13.1: use the stable public host-frame submission seam
                        // instead of patching VulkanVideoPresenter internals. This keeps
                        // the Bink2 implementation compatible with newer presenter
                        // revisions while preserving all intervening GPU changes.
                        VulkanVideoPresenter.Submit(stableFrame, width, height);

                        presentedFrames++;
                        if (presentedFrames <= 3 || presentedFrames % 120 == 0)
                        {
                            Console.Error.WriteLine(
                                $"[LOADER][INFO] bink2.direct_frame n={presentedFrames} " +
                                $"serial={frameSerial} file='{Path.GetFileName(hostPath)}' " +
                                $"size={width}x{height}");
                        }
                    }

                    Thread.Sleep(1);
                    continue;
                }

                lock (Gate)
                {
                    if (_playback is null &&
                        _frameBuffer is null &&
                        _radPlayback is null &&
                        PendingMoviePaths.Count == 0)
                    {
                        break;
                    }
                }

                Thread.Sleep(2);
            }
        }
        catch (Exception exception) when (
            exception is IOException or InvalidOperationException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.direct_boot_failed: " + exception.Message);
        }
        finally
        {
            lock (Gate)
            {
                _directPresentationActive = false;
                _directPresentationFrame = null;
                _directPresentationFrameWidth = 0;
                _directPresentationFrameHeight = 0;
                Monitor.PulseAll(Gate);
            }

            Console.Error.WriteLine(
                $"[LOADER][INFO] bink2.direct_boot_completed frames={presentedFrames}; " +
                "guest presentation restored.");
        }
    }


    private static void CloseActiveLocked()
    {
        _playback?.Dispose();
        _playback = null;

        _radPlayback?.Dispose();
        _radPlayback = null;

        _activePath = null;
        _activeInfo = default;
        _frameBuffer = null;
        _frameBufferPresented = false;

        // Wake any guest _read() blocked in WaitForHostPlaybackToFinish: its
        // movie either just finished or is being pre-empted by a new attach.
        Monitor.PulseAll(Gate);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct Bink2MovieInfo
    {
        public readonly uint Width;
        public readonly uint Height;
        public readonly uint FramesPerSecondNumerator;
        public readonly uint FramesPerSecondDenominator;

        internal Bink2MovieInfo(
            uint width,
            uint height,
            uint framesPerSecondNumerator,
            uint framesPerSecondDenominator)
        {
            Width = width;
            Height = height;
            FramesPerSecondNumerator = framesPerSecondNumerator;
            FramesPerSecondDenominator = framesPerSecondDenominator;
        }
    }

    private enum MovieMode
    {
        Guest,
        Skip,
        Dummy,
        Native,
        Rad,
        Nihav,
        Ffmpeg,
    }

    private static readonly Queue<string> PendingMoviePaths = new();
    private static readonly HashSet<string> PendingMoviePathSet =
        new(StringComparer.OrdinalIgnoreCase);
    private static void AttachNextQueuedMovieLocked()
    {
        while (PendingMoviePaths.Count > 0)
        {
            var path = PendingMoviePaths.Dequeue();
            PendingMoviePathSet.Remove(path);
            if (!File.Exists(path))
            {
                continue;
            }

            AttachMovieLocked(path, ResolveMode());
            if (_playback is not null ||
                _frameBuffer is not null ||
                _radPlayback is not null)
            {
                return;
            }
        }
    }
    // Longest a guest _read() will block waiting for real host playback to
    // finish. A safety net, not a target: real movies finish well under
    // this. Bounds the damage if a movie fails to attach/decode after being
    // queued, so the guest thread doesn't hang forever.
    private const long MaxCompletionWaitMilliseconds = 5 * 60 * 1000;
    /// <summary>
    /// Blocks the calling (guest I/O) thread until the host has actually
    /// finished presenting <paramref name="hostPath"/> — either because it
    /// played through, or because something else took over the timeline.
    ///
    /// The completion shim tells the guest's own Bink header parse "this
    /// movie is one frame and already done" so its native decoder never
    /// blocks the guest on real per-frame work. Without this wait, that lie
    /// lands the instant the guest reads the header, so guest-side game
    /// logic races far ahead of whatever the host is still showing on
    /// screen: pressing a button lands on the (already-advanced) guest
    /// state, but the video visibly keeps playing, and any real-time-gated
    /// trigger later in the guest's own flow can fire against a clock that
    /// no longer matches wall time. Gating the "done" read on real host
    /// completion keeps guest pacing and on-screen playback in lockstep.
    /// </summary>
    internal static void WaitForHostPlaybackToFinish(string hostPath)
    {
        var deadline = Environment.TickCount64 + MaxCompletionWaitMilliseconds;
        lock (Gate)
        {
            while (IsTrackedLocked(hostPath))
            {
                var remaining = deadline - Environment.TickCount64;
                if (remaining <= 0)
                {
                    Console.Error.WriteLine(
                        "[LOADER][WARN] Bink2 bridge completion wait timed out for '" +
                        Path.GetFileName(hostPath) + "'.");
                    return;
                }

                Monitor.Wait(Gate, (int)Math.Min(remaining, 200));
            }
        }
    }

    private static bool IsTrackedLocked(string hostPath) =>
        string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase) ||
        PendingMoviePathSet.Contains(hostPath);

    // SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF

    // V74.0.12 required the precise Bink frame-index parser before it could

    // expose the one-frame completion header. The measured V74.0.12 run showed

    // handoff=0 even though the first startup movie was visibly presented.

    // Keep the precise path first, then fall back to the validated 16-byte KB2

    // core header. The fallback changes only NumFrames=1 and preserves the

    // movie's original file-size and largest-frame fields, so it cannot invent

    // a frame offset. It is limited to the two one-shot Demon's Souls startup

    // movies and remains opt-out through SHARPEMU_BINK_STARTUP_COMPLETION_SHIM=0.

    private static bool IsOneShotStartupBinkV74013(string hostPath)

    {

        if (string.Equals(

                Environment.GetEnvironmentVariable(

                    "SHARPEMU_BINK_STARTUP_COMPLETION_SHIM"),

                "0",

                StringComparison.Ordinal))

        {

            return false;

        }



        var name = Path.GetFileName(hostPath);

        return

            string.Equals(name, "ps_studios_logo.bk2", StringComparison.OrdinalIgnoreCase) ||

            string.Equals(name, "logo_intro.bk2", StringComparison.OrdinalIgnoreCase);

    }



    private static bool TryReadGuestCompletionShimHeaderFallbackV74013(

        string hostPath,

        out BinkGuestCompletionShim completionShim)

    {

        completionShim = default;

        Span<byte> header = stackalloc byte[16];

        try

        {

            using var stream = new FileStream(

                hostPath,

                FileMode.Open,

                FileAccess.Read,

                FileShare.ReadWrite | FileShare.Delete);

            stream.ReadExactly(header);

            if (!header[..3].SequenceEqual("KB2"u8))

            {

                return false;

            }



            var fileSizeMinusHeader =

                BinaryPrimitives.ReadUInt32LittleEndian(header[4..8]);

            var frameCount =

                BinaryPrimitives.ReadUInt32LittleEndian(header[8..12]);

            var largestFrameSize =

                BinaryPrimitives.ReadUInt32LittleEndian(header[12..16]);

            if (frameCount < 2 ||

                fileSizeMinusHeader == 0 ||

                largestFrameSize == 0)

            {

                return false;

            }



            completionShim = new BinkGuestCompletionShim(

                fileSizeMinusHeader,

                largestFrameSize);

            return true;

        }

        catch (Exception exception) when (

            exception is IOException or EndOfStreamException or UnauthorizedAccessException)

        {

            return false;

        }

    }



    internal static bool TryTakeOverGuestMovie(

        string hostPath,

        out BinkGuestCompletionShim completionShim,

        out bool observed)

    {

        completionShim = default;

        observed = ObserveGuestMovie(hostPath);



        if (!observed || !IsOneShotStartupBinkV74013(hostPath))

        {

            return false;

        }



        var precise = TryReadGuestCompletionShim(hostPath, out completionShim);

        var headerFallback = false;

        if (!precise)

        {

            headerFallback = TryReadGuestCompletionShimHeaderFallbackV74013(

                hostPath,

                out completionShim);

            if (!headerFallback)

            {

                completionShim = default;

                Console.Error.WriteLine(

                    "[V74.0.13.2][BINK] startup_completion_shim_unavailable file='" +

                    Path.GetFileName(hostPath) + "'");

                return false;

            }

        }



        Console.Error.WriteLine(

            precise

                ? "[V74.0.13.2][BINK] bink2.startup_completion_shim mode=precise file='" +

                    Path.GetFileName(hostPath) + "'"

                : "[V74.0.13.2][BINK] bink2.startup_completion_shim_header_fallback file='" +

                    Path.GetFileName(hostPath) + "'");

        return true;

    }

    internal static void NotifyGuestMovieClosed(string hostPath)
    {
        lock (Gate)
        {
            if (PendingMoviePathSet.Remove(hostPath))
            {
                var retained = PendingMoviePaths
                    .Where(path => !string.Equals(
                        path,
                        hostPath,
                        StringComparison.OrdinalIgnoreCase))
                    .ToArray();
                PendingMoviePaths.Clear();
                foreach (var path in retained)
                {
                    PendingMoviePaths.Enqueue(path);
                }
            }

            if (!string.Equals(_activePath, hostPath, StringComparison.OrdinalIgnoreCase))
            {
                Monitor.PulseAll(Gate);
                return;
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] Bink2 bridge stopped by guest close: " +
                Path.GetFileName(hostPath));
            CloseActiveLocked();
            AttachNextQueuedMovieLocked();
        }
    }

    internal static bool TryReadGuestCompletionShim(
        string hostPath,
        out BinkGuestCompletionShim completionShim)
    {
        completionShim = default;
        Span<byte> header = stackalloc byte[48];
        try
        {
            using var stream = File.OpenRead(hostPath);
            stream.ReadExactly(header);
            if (!header[..3].SequenceEqual("KB2"u8))
            {
                return false;
            }

            var frameCount = BinaryPrimitives.ReadUInt32LittleEndian(header[8..12]);
            var audioTrackCount = BinaryPrimitives.ReadUInt32LittleEndian(header[40..44]);
            if (frameCount < 2 || audioTrackCount > 256)
            {
                return false;
            }

            var revision = header[3];
            var frameIndexOffset = 44L + checked(12L * audioTrackCount);
            if (revision == (byte)'m')
            {
                frameIndexOffset += 16;
            }
            else if (revision is (byte)'i' or (byte)'j' or (byte)'k' or (byte)'n')
            {
                frameIndexOffset += 4;
            }

            Span<byte> frameOffsets = stackalloc byte[8];
            stream.Position = frameIndexOffset;
            stream.ReadExactly(frameOffsets);
            var firstFrameOffset = BinaryPrimitives.ReadUInt32LittleEndian(frameOffsets[..4]) & ~1u;
            var secondFrameOffset = BinaryPrimitives.ReadUInt32LittleEndian(frameOffsets[4..]) & ~1u;
            if (firstFrameOffset < frameIndexOffset + 8 ||
                secondFrameOffset <= firstFrameOffset ||
                secondFrameOffset > stream.Length)
            {
                return false;
            }

            completionShim = new BinkGuestCompletionShim(
                secondFrameOffset - 8,
                secondFrameOffset - firstFrameOffset);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or EndOfStreamException or OverflowException)
        {
            return false;
        }
    }

    internal readonly struct BinkGuestCompletionShim
    {
        private readonly uint _fileSizeMinusHeader;
        private readonly uint _largestFrameSize;

        internal BinkGuestCompletionShim(uint fileSizeMinusHeader, uint largestFrameSize)
        {
            _fileSizeMinusHeader = fileSizeMinusHeader;
            _largestFrameSize = largestFrameSize;
        }

        /// <summary>
        /// Rewrites the frame-count/size fields the guest's own Bink header
        /// parse reads, if this read covers them. Returns true when the
        /// NumFrames field (the field that tells the guest "this movie is
        /// done") was in range, so the caller can gate that specific read on
        /// the host's real playback actually finishing first.
        /// </summary>
        internal bool Patch(long fileOffset, Span<byte> bytes)
        {
            PatchUInt32(fileOffset, bytes, 4, _fileSizeMinusHeader);
            var touchedCompletionField = PatchUInt32(fileOffset, bytes, 8, 1);
            PatchUInt32(fileOffset, bytes, 12, _largestFrameSize);
            return touchedCompletionField;
        }

        private static bool PatchUInt32(
            long fileOffset,
            Span<byte> bytes,
            long fieldOffset,
            uint value)
        {
            var relativeOffset = fieldOffset - fileOffset;
            if (relativeOffset < 0 || relativeOffset + sizeof(uint) > bytes.Length)
            {
                return false;
            }

            BinaryPrimitives.WriteUInt32LittleEndian(
                bytes.Slice((int)relativeOffset, sizeof(uint)),
                value);
            return true;
        }
    }
}
