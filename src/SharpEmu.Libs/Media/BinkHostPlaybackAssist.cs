// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V61.13.14 lightweight direct-movie audio/telemetry helper.
///
/// Decoder continuity is fixed in NihavBink2Decoder itself, so the presenter
/// no longer needs V61.13.11 per-frame hashes or CPU R/B rewrites.
/// </summary>
internal static partial class BinkHostPlaybackAssist
{
    private static readonly object Gate = new();
    private static readonly object LogGate = new();
    // [V72.4.3.2.15][GUEST_CPU_EVENT_PARK]
    // V72.4.3.2.14 used a 1 ms sleep loop in native guest workers. The
    // measured run still consumed roughly a full 12-core CPU. Park workers on
    // a kernel-backed event instead and release them when the final host movie
    // decoder leaves. spinCount=0 prevents ManualResetEventSlim from burning
    // CPU before it falls back to the wait handle.
    private static readonly ManualResetEventSlim GuestCpuPermit =
        new(initialState: true, spinCount: 0);
    private static long _guestCpuEventParkCount;
    private static long _frameCount;
    private static long _movieThrottleStartTick;
    private static long _lastDirectFrameTick;
    private static long _movieCompleteTick;
    private static long _lastCapturePermitTick;
    private static long _capturePermitCount;
    private static long _guestFramePresentedTick;
    private static long _lastProgressPermitTick;
    private static int _activeHostMovieDecoders;
    private static long _hostMovieDecoderGeneration;
    private static int _postMovieCleanupScheduled;
    private static bool _audioStarted;
    private static string? _activeHostMoviePath; // V61.19.0_HOST_AUDIO_LIFECYCLE
    private static long _audioStartedGeneration;

    // [V61.13.24][DECODER_LIFECYCLE_BOOT_BOUNDARY]
    // The direct boot helper can intentionally skip stale decoded frames to
    // maintain real-time playback, so a hard "613 presented frames" boundary
    // is no longer valid. Completion is based on decoder lifecycle instead:
    // when the last host decoder stops, wait 500ms. If no next boot decoder
    // has started in that interval, the boot movie sequence is complete.
    private const int BootDecoderIdleCompletionMs = 500;

    private static bool IsBootMovieComplete() =>
        Interlocked.Read(ref _movieCompleteTick) > 0;

    private static void ScheduleDecoderIdleCompletion(long generation)
    {
        ThreadPool.QueueUserWorkItem(
            static state =>
            {
                var expectedGeneration = (long)state!;
                Thread.Sleep(BootDecoderIdleCompletionMs);

                if (Volatile.Read(ref _activeHostMovieDecoders) != 0 ||
                    Interlocked.Read(ref _hostMovieDecoderGeneration) !=
                        expectedGeneration ||
                    Interlocked.Read(ref _guestFramePresentedTick) > 0)
                {
                    return;
                }

                var now = Environment.TickCount64;
                if (Interlocked.CompareExchange(
                        ref _movieCompleteTick,
                        now,
                        0) != 0)
                {
                    return;
                }

                Log(
                    "BOOT_MOVIE_FRAME_BOUNDARY",
                    "frame=" +
                    Interlocked.Read(ref _frameCount)
                        .ToString(CultureInfo.InvariantCulture) +
                    " reason=decoder-idle" +
                    " generation=" +
                    expectedGeneration.ToString(CultureInfo.InvariantCulture) +
                    " staged_gpu_release=1");

                SchedulePostMovieCleanup();
            },
            generation);
    }

    // SHARPEMU_V74_0_77_DEMONS_TITLE_TIMELINE
    // Demon's Souls attract/title-loop movies are visual presentation owned by
    // the host bridge, but the title's guest state machine must keep executing
    // underneath them. In particular StartIntro/MusicSkipIntro, input and UI
    // progression must be able to reach the PRESS ANY BUTTON/title-menu state.
    //
    // Keep one-shot startup logos on the historical hard gate. Only the
    // guest-driven attract and title/press-start loop are pass-through.
    private static readonly bool _demonsTitleTimelinePassthroughV74077 =
        !string.Equals(
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_TITLE_TIMELINE_PASSTHROUGH"),
            "0",
            StringComparison.Ordinal);

    internal static bool IsTitleTimelinePassthroughMovieV74077(
        string? hostPath)
    {
        if (!_demonsTitleTimelinePassthroughV74077 ||
            string.IsNullOrWhiteSpace(hostPath))
        {
            return false;
        }

        var fileName = Path.GetFileName(hostPath);
        return
            string.Equals(
                fileName,
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            // SHARPEMU_V74_0_83_LOGO_INTRO_TITLE_PASSTHROUGH
            string.Equals(
                fileName,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            // SHARPEMU_V74_0_84_1_UI_BINK_GUEST_LIVE_PASSTHROUGH
            // main_menu*.bk2 is a texture source behind live guest UI. It must
            // never take the boot/fullscreen decoder execution gate.
            string.Equals(
                fileName,
                "main_menu.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                fileName,
                "main_menu_ngp.bk2",
                StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsActiveTitleTimelinePassthroughV74077() =>
        IsTitleTimelinePassthroughMovieV74077(
            Volatile.Read(ref _activeHostMoviePath));

    // [V61.13.23.3][DECODER_ACTIVE_GUARD]
    // Throttle guest snapshot production as soon as the host boot decoder is
    // attached, not only after its first frame arrives. This prevents a decoder
    // startup/failure from leaving frame_count=0 while the whole guest GPU
    // pipeline runs unrestricted.
    internal static void NotifyHostMovieDecoderStarted(string? hostPath)
    {
        Interlocked.Increment(ref _hostMovieDecoderGeneration);

        var titleTimelinePassthroughV74077 =
            IsTitleTimelinePassthroughMovieV74077(hostPath);

        // V72.4.3.2.14 HOST_MOVIE_CPU_GATE_BEGIN
        // V74.0.77: never freeze the Demon's Souls attract/title guest state.
        if (!titleTimelinePassthroughV74077)
        {
            SharpEmu.HLE.HostMovieExecutionGateV7243214.Begin();
        }

        var count = Interlocked.Increment(ref _activeHostMovieDecoders);
        if (count == 1 &&
            !titleTimelinePassthroughV74077 &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_THROTTLE_GUEST_CPU") == "1")
        {
            GuestCpuPermit.Reset();
        }

        if (count == 1)
        {
            lock (Gate)
            {
                StopHostAudioLocked();
                _activeHostMoviePath = hostPath;
            }
        }

        if (titleTimelinePassthroughV74077)
        {
            // Make absolutely sure a permit left reset by an immediately
            // preceding one-shot movie cannot park the title state machine.
            GuestCpuPermit.Set();

            Console.Error.WriteLine(
                "[V74.0.77][TITLE_TIMELINE_PASSTHROUGH] " +
                $"action=start file='{Path.GetFileName(hostPath)}' " +
                "hle_gate=False cpu_park=False gpu_throttle=False " +
                "guest_input=True");
        }
        Log(
            "HOST_MOVIE_DECODER_STARTED",
            "active=" + count.ToString(CultureInfo.InvariantCulture) +
            " file='" + (Path.GetFileName(hostPath) ?? string.Empty) + "'");
    }

    internal static void NotifyHostMovieDecoderStopped(string? hostPath)
    {
        var titleTimelinePassthroughV74077 =
            IsTitleTimelinePassthroughMovieV74077(hostPath);

        var count = Interlocked.Decrement(ref _activeHostMovieDecoders);

        // V72.4.3.2.14 HOST_MOVIE_CPU_GATE_END
        // Pair End only with movies that actually entered Begin.
        if (!titleTimelinePassthroughV74077)
        {
            SharpEmu.HLE.HostMovieExecutionGateV7243214.End();
        }
        else
        {
            Console.Error.WriteLine(
                "[V74.0.77][TITLE_TIMELINE_PASSTHROUGH] " +
                $"action=stop file='{Path.GetFileName(hostPath)}' " +
                "hle_gate=False guest_state_continued=True");
        }

        if (count < 0)
        {
            Interlocked.Exchange(ref _activeHostMovieDecoders, 0);
            count = 0;
        }

        Log(
            "HOST_MOVIE_DECODER_STOPPED",
            "active=" + count.ToString(CultureInfo.InvariantCulture) +
            " file='" + (Path.GetFileName(hostPath) ?? string.Empty) + "'");

        if (count == 0)
        {
            // [V72.4.3.2.15][GUEST_CPU_EVENT_PARK]
            // Always release parked workers, including error/dispose paths.
            GuestCpuPermit.Set();


            lock (Gate)
            {
                StopHostAudioLocked();
                _activeHostMoviePath = null;
            }

            if (Interlocked.Read(ref _guestFramePresentedTick) <= 0)
            {
                ScheduleDecoderIdleCompletion(
                    Interlocked.Read(ref _hostMovieDecoderGeneration));
            }
        }
    }

    // [V72.4.3.2.15][GUEST_CPU_EVENT_PARK]
    internal static void WaitForGuestCpuPermit()
    {
        if (IsActiveTitleTimelinePassthroughV74077() ||
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_THROTTLE_GUEST_CPU") != "1" ||
            GuestCpuPermit.IsSet)
        {
            return;
        }

        var parkCount = Interlocked.Increment(
            ref _guestCpuEventParkCount);
        if (parkCount <= 8 ||
            (parkCount & (parkCount - 1)) == 0)
        {
            Log(
                "GUEST_CPU_EVENT_PARK",
                "count=" + parkCount.ToString(CultureInfo.InvariantCulture) +
                " active=" +
                Volatile.Read(ref _activeHostMovieDecoders)
                    .ToString(CultureInfo.InvariantCulture) +
                " thread='" +
                (Thread.CurrentThread.Name ?? string.Empty) + "'");
        }

        // Long event wait instead of the previous 1 ms polling loop. The
        // timeout is only a safety valve for abnormal decoder teardown.
        while (Volatile.Read(ref _activeHostMovieDecoders) > 0)
        {
            if (GuestCpuPermit.Wait(1000))
            {
                break;
            }
        }

        if (Volatile.Read(ref _activeHostMovieDecoders) <= 0)
        {
            GuestCpuPermit.Set();
        }
    }

    // [V61.13.18][PRE_SNAPSHOT_GPU_THROTTLE]
    // V61.13.17 blocked payload work only after AGC had already evaluated the
    // shader and captured large guest-memory snapshots. The recovered runs
    // showed this was too late: blocked producers still retained 16+ MiB
    // snapshots each. V61.13.18 gates compute evaluation before those arrays
    // are captured, then releases work gradually after the real 613-frame boot
    // sequence completes.
    internal static bool ShouldThrottleGuestGpu
    {
        get
        {
            if (IsActiveTitleTimelinePassthroughV74077())
            {
                return false;
            }

            if (Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_THROTTLE_GUEST_GPU") != "1")
            {
                return false;
            }

            // V72.4.3.2.31.7.6: an explicitly active host decoder always owns
            // the screen, even if the boot-complete latch was set during the
            // gap between queued movies. V31.7.5 left attract_movie unthrottled
            // once that latch was set, which allowed 4K guest texture work to
            // compete with RAD and break A/V realtime.
            if (Volatile.Read(ref _activeHostMovieDecoders) > 0)
            {
                return true;
            }

            if (IsBootMovieComplete())
            {
                return false;
            }

            return Interlocked.Read(ref _frameCount) > 0;
        }
    }

    // [V61.13.25][EXTENDED_SYNC_PRIORITY]
    // V24 proves WAIT_REG_MEM/fence pressure continues after the first guest
    // frame. Keep cross-queue ordered sync/flip preference for a bounded
    // post-Bink interval rather than disabling it at FIRST_GUEST_FRAME.
    // [V72.4.3.2.16][BOOT_COMPUTE_VISIBILITY_WINDOW]
    // During host-movie boot/handoff, compute completion words must become CPU-visible
    // even when WAIT_REG_MEM registers after the dispatch was submitted.
    internal static bool ShouldForceBootComputeLabelVisibility
    {
        get
        {
            if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_COMPUTE_LABEL_VISIBILITY") == "0")
            {
                return false;
            }

            if (Volatile.Read(ref _activeHostMovieDecoders) > 0)
            {
                return true;
            }

            var complete = Interlocked.Read(ref _movieCompleteTick);
            if (complete <= 0 || Interlocked.Read(ref _guestFramePresentedTick) > 0)
            {
                return false;
            }

            return Environment.TickCount64 - complete <= 45_000;
        }
    }

    internal static bool ShouldPrioritizeGuestSyncWork
    {
        get
        {
            if (Environment.GetEnvironmentVariable(
                    "SHARPEMU_POST_BINK_SYNC_PRIORITY") != "1")
            {
                return false;
            }

            if (!IsBootMovieComplete())
            {
                return false;
            }

            var completeTick = Interlocked.Read(ref _movieCompleteTick);
            if (completeTick <= 0)
            {
                return false;
            }

            var configuredWindowMs = 90_000L;
            if (long.TryParse(
                    Environment.GetEnvironmentVariable(
                        "SHARPEMU_POST_BINK_SYNC_PRIORITY_MS"),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out var parsedWindowMs) &&
                parsedWindowMs >= 0)
            {
                configuredWindowMs = parsedWindowMs;
            }

            return Environment.TickCount64 - completeTick <=
                   configuredWindowMs;
        }
    }

    internal static bool WaitForGuestGpuCapturePermit()
    {
        if (IsActiveTitleTimelinePassthroughV74077() ||
            Environment.GetEnvironmentVariable(
                "SHARPEMU_BINK_THROTTLE_GUEST_GPU") != "1")
        {
            return true;
        }

        while (true)
        {
            if (IsActiveTitleTimelinePassthroughV74077())
            {
                return true;
            }

            var frames = Interlocked.Read(ref _frameCount);
            if (frames <= 0)
            {
                if (Volatile.Read(ref _activeHostMovieDecoders) > 0)
                {
                    Thread.Sleep(2);
                    continue;
                }

                return true;
            }

            var now = Environment.TickCount64;
            var started = Interlocked.Read(ref _movieThrottleStartTick);

            // Safety valve if a decoder aborts and never reports stop.
            if (started > 0 && now - started >= 120_000)
            {
                return true;
            }

            if (!IsBootMovieComplete())
            {
                Thread.Sleep(2);
                continue;
            }

            var complete = Interlocked.Read(ref _movieCompleteTick);

            var guestPresented =
                Interlocked.Read(ref _guestFramePresentedTick) > 0;

            var privateBytes = 0L;
            var workingSetBytes = 0L;
            try
            {
                using var process = Process.GetCurrentProcess();
                privateBytes = process.PrivateMemorySize64;
                workingSetBytes = process.WorkingSet64;
            }
            catch
            {
            }

            // [V61.13.19][ADAPTIVE_CAPTURE_BUDGET]
            // V61.13.18 proved the pre-snapshot gate works, but its time-only
            // schedule reopened capture too quickly: the recovered run still
            // climbed to ~13.1 GiB working set / ~18.7 GiB private memory.
            // Release based on the real memory pressure and on whether the
            // first guest frame has actually been presented.
            var privateMb = privateBytes / (1024L * 1024L);
            var workingSetMb = workingSetBytes / (1024L * 1024L);

            // [V61.13.20][PROGRESS_AWARE_CAPTURE_BUDGET]
            // V61.13.19 reduced peak WS substantially, but no guest frame was
            // ever presented. Its tiny 64 MiB guest-buffer cache evicted live
            // allocations and compute then failed with
            // "no Vulkan guest buffer allocation covers ...". Keep snapshot
            // capture conservative under high commit, but allow enough ordered
            // compute progress to reach the first real guest frame.
            // [V61.13.21][MEMORY_GOVERNED_PRODUCER_RAMP]
            // V20 reached the first guest frame but took ~62 seconds. During
            // most of that interval the post-movie cleanup had already reduced
            // WS to tens/hundreds of MiB and private commit was ~7-8 GiB, yet
            // capture stayed fixed at one permit / 72 ms. Accelerate only while
            // memory is genuinely low; immediately back off as commit/WS rises.
            long intervalMs;
            if (privateMb >= 15_000 || workingSetMb >= 10_000)
            {
                intervalMs = 500;
            }
            else if (privateMb >= 13_000 || workingSetMb >= 8_500)
            {
                intervalMs = 280;
            }
            else if (privateMb >= 11_000 || workingSetMb >= 7_000)
            {
                intervalMs = 128;
            }
            else if (privateMb >= 9_500 || workingSetMb >= 5_500)
            {
                intervalMs = 64;
            }
            else if (!guestPresented)
            {
                // [V61.13.25][LOW_PRESSURE_CAPTURE_ACCELERATION]
                // V24 remained at low WS/private commit for several seconds
                // after cleanup but took ~65s to reach the first guest frame.
                // Admit work twice as quickly only in the lowest pressure band;
                // the existing 64/128/280/500ms tiers still engage as memory rises.
                // [V72.4.3.2.16][POST_MOVIE_32MS_RAMP]
                // One low-pressure capture permit per ~display frame; 8 ms multiplied
                // large snapshots while the guest had not produced a presentable frame.
                intervalMs = 32;
            }
            else
            {
                intervalMs = 12;
            }

            lock (Gate)
            {
                now = Environment.TickCount64;
                if (now - _lastCapturePermitTick >= intervalMs)
                {
                    _lastCapturePermitTick = now;
                    var permit = ++_capturePermitCount;
                    if (permit <= 8 || (permit & (permit - 1)) == 0)
                    {
                        Log(
                            "POST_MOVIE_CAPTURE_PERMIT",
                            "n=" + permit.ToString(CultureInfo.InvariantCulture) +
                            " interval_ms=" +
                            intervalMs.ToString(CultureInfo.InvariantCulture) +
                            " guest_frame=" + guestPresented +
                            " since_boundary_ms=" +
                            (now - complete).ToString(CultureInfo.InvariantCulture) +
                            " private_mb=" +
                            privateMb.ToString(CultureInfo.InvariantCulture) +
                            " ws_mb=" +
                            workingSetMb.ToString(CultureInfo.InvariantCulture));
                    }
                    return true;
                }
            }

            Thread.Sleep(2);
        }
    }

    // [V61.13.19][GUEST_FRAME_MILESTONE]
    internal static void NotifyGuestFramePresented()
    {
        var now = Environment.TickCount64;
        if (Interlocked.CompareExchange(
                ref _guestFramePresentedTick,
                now,
                0) == 0)
        {
            Log(
                "FIRST_GUEST_FRAME_PRESENTED",
                "frame_count=" +
                Interlocked.Read(ref _frameCount)
                    .ToString(CultureInfo.InvariantCulture));
        }
    

        // V31.7.14_GUEST_FRAME_ATTRACT_HANDOFF

        HostMovieBridge.NotifyV31714GuestFirstFrameAttractHandoff();}

    private static void SchedulePostMovieCleanup()
    {
        if (Interlocked.CompareExchange(
                ref _postMovieCleanupScheduled,
                1,
                0) != 0)
        {
            return;
        }

        ThreadPool.QueueUserWorkItem(
            static _ =>
            {
                try
                {
                    Thread.Sleep(500);

                    // [V61.13.19][POST_MOVIE_LOH_CLEANUP]
                    // Large shader/global snapshots from the boot overlap can
                    // leave LOH segments resident after references are released.
                    // Compact once at the cinematic boundary, not every frame.
                    GCSettings.LargeObjectHeapCompactionMode =
                        GCLargeObjectHeapCompactionMode.CompactOnce;
                    GC.Collect(
                        GC.MaxGeneration,
                        GCCollectionMode.Aggressive,
                        blocking: true,
                        compacting: true);

                    TryTrimWorkingSet();

                    Log(
                        "POST_MOVIE_MEMORY_CLEANUP",
                        "gc=aggressive loh=compact working_set_trim=attempted");
                }
                catch (Exception ex)
                {
                    Log(
                        "POST_MOVIE_MEMORY_CLEANUP_FAIL",
                        "message='" +
                        ex.Message.Replace('\r', ' ').Replace('\n', ' ') +
                        "'");
                }
            });
    }

    private static void TryTrimWorkingSet()
    {
        if (!OperatingSystem.IsWindows() ||
            Environment.GetEnvironmentVariable(
                "SHARPEMU_POST_BINK_TRIM_WORKING_SET") != "1")
        {
            return;
        }

        try
        {
            using var process = Process.GetCurrentProcess();
            _ = EmptyWorkingSet(process.Handle);
        }
        catch
        {
        }
    }

    [LibraryImport("psapi.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool EmptyWorkingSet(nint hProcess);

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private const uint SndPurge = 0x0040;

    internal static bool TryNormalizeDirectPresentationFrame(
        byte[] pixels,
        uint width,
        uint height)
    {
        if (Environment.GetEnvironmentVariable("SHARPEMU_BINK_DIRECT_PRESENT_ONLY") != "1")
        {
            return true;
        }

        lock (Gate)
        {
            var n = ++_frameCount;
            _lastDirectFrameTick = Environment.TickCount64;
            if (n == 1)
            {
                _movieThrottleStartTick = _lastDirectFrameTick;
                Log(
                    "DIRECT_STREAM_BEGIN",
                    "size=" + width + "x" + height +
                    " guest_gpu_throttle=" +
                    (Environment.GetEnvironmentVariable(
                        "SHARPEMU_BINK_THROTTLE_GUEST_GPU") == "1"));
            }

            // Start host sidecar/explicit WAV once per decoder generation, not
            // once per entire boot sequence. The old n==1 check made audio work
            // only for the first movie in a multi-movie boot.
            var decoderGeneration = Interlocked.Read(ref _hostMovieDecoderGeneration);
            if (_audioStartedGeneration != decoderGeneration)
            {
                _audioStartedGeneration = decoderGeneration;
                TryStartAudioLocked();
            }

            // V61.13.24: completion is decoder-lifecycle based.

            if (n <= 3 || n % 30 == 0)
            {
                Log("DIRECT_FRAME", "n=" + n.ToString(CultureInfo.InvariantCulture));
            }
        }

        return true;
    }

    private static void TryStartAudioLocked()
    {
        if (_audioStarted ||
            !OperatingSystem.IsWindows() ||
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO") != "1")
        {
            return;
        }

        var wav = Environment.GetEnvironmentVariable("SHARPEMU_BINK_HOST_AUDIO_WAV");
        if (string.IsNullOrWhiteSpace(wav) && !string.IsNullOrWhiteSpace(_activeHostMoviePath))
        {
            var sidecar = Path.ChangeExtension(_activeHostMoviePath, ".wav");
            if (File.Exists(sidecar))
            {
                wav = sidecar;
            }
        }
        if (string.IsNullOrWhiteSpace(wav) || !File.Exists(wav))
        {
            return;
        }

        try
        {
            var ok = PlaySoundW(wav, 0, SndAsync | SndNodefault | SndFilename);
            _audioStarted = true;
            Log("AUDIO_START", "started=" + ok);
        }
        catch (Exception ex)
        {
            Log("AUDIO_START_FAIL", "message='" + ex.Message.Replace('\r',' ').Replace('\n',' ') + "'");
        }
    }

    private static void StopHostAudioLocked()
    {
        if (!_audioStarted || !OperatingSystem.IsWindows())
        {
            _audioStarted = false;
            return;
        }

        try
        {
            _ = PlaySoundW(null, 0, 0);
        }
        catch
        {
        }
        _audioStarted = false;
        Log("AUDIO_STOP", "reason=decoder-lifecycle");
    }

    internal static void OnDirectPresentationFrame(uint width, uint height) { }
    internal static int GetExpectedDurationMs(string? hostPath) =>
        string.IsNullOrWhiteSpace(hostPath)
            ? 0
            : Path.GetFileName(hostPath).Equals(
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase)
                ? 8_500
                : Path.GetFileName(hostPath).Equals(
                    "logo_intro.bk2",
                    StringComparison.OrdinalIgnoreCase)
                    ? 12_000
                    : 0;

    internal static void OnMovieFrame(string hostPath) { }
    internal static void EndMovieSession(string? hostPath) { }
    internal static void CompleteMovieSession(string? hostPath, string reason) { }
    internal static void LogExternal(string stage, string detail) => Log(stage, detail);

    private static void Log(string stage, string detail)
    {
        var path = Environment.GetEnvironmentVariable("SHARPEMU_BINK_SESSION_LOG");
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var line =
                DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) +
                " pid=" + Environment.ProcessId.ToString(CultureInfo.InvariantCulture) +
                " tid=" + Environment.CurrentManagedThreadId.ToString(CultureInfo.InvariantCulture) +
                " [" + stage + "] " + detail + Environment.NewLine;

            lock (LogGate)
            {
                File.AppendAllText(path, line, new UTF8Encoding(false));
            }
        }
        catch
        {
        }
    }

    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PlaySoundW(string? pszSound, nint hmod, uint fdwSound);
}
