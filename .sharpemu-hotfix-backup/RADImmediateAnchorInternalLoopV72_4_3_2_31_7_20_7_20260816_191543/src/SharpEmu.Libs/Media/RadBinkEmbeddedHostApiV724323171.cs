// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-facing API for RAD playback presentation.
///
/// V72.4.3.2.31.7.10 keeps the proven PID/HWND embedding, hard-gate-compatible transition and shared playback-anchor callback, and adds a host-side player interaction lock. The embedded RAD renderer is shown without activation, its HWND/input descendants are disabled, standard seek/control child HWNDs are hidden, and a small configurable bottom strip is clipped outside the SharpEmu client area so the RAD player cannot pause, seek, or alter movie sequencing from mouse/keyboard interaction.  The callback runs while the child HWND is still hidden and immediately before the first visible RAD frame.  This lets an external sidecar audio stream start from the same host media-clock anchor instead of being started after ShowWindow.  It is a bridge for host-injected boot movies; final guest-driven timing should be sourced from the title's own movie/audio calls. the RAD child remains hidden through initialization, is revealed at the playback anchor, is hidden shortly before the nominal BK2 boundary, and the renderer is killed exactly at the nominal boundary.  This prevents the BinkPlay post-roll logo from ever becoming a SharpEmu frame while preserving all but the last few fade frames.
///
/// The attach path still removes every GetWindowText/GetWindowTextLength call from
/// the attach path.  The V31.7.3 result stopped immediately after
/// rad_required_started.  On Windows, querying text for a window owned by the
/// current process can synchronously send WM_GETTEXT/WM_GETTEXTLENGTH to that
/// window's thread; the SDL/Vulkan presenter may not be pumping those messages
/// while the movie thread is waiting.  Window discovery therefore uses only
/// PID, class/area and Process.MainWindowHandle.
///
/// The official RAD decoder still lives in a RAD process.  Its renderer HWND is
/// reparented as a child of the SharpEmu SDL window.  Same-process Bink decode
/// requires the licensed Bink SDK runtime, which RAD Video Tools does not ship.
/// </summary>
internal interface IRadBinkHostApi : IDisposable
{
    bool IsEmbedded { get; }
    nint HostWindow { get; }
    nint PlayerWindow { get; }
    int RendererProcessId { get; }
    double WindowReadyMilliseconds { get; }
    double PlaybackAnchorMilliseconds { get; }
    bool IsPlaybackFinished { get; }
    int? PlaybackExitCode { get; }
}

internal sealed class RadBinkEmbeddedHostApiV724323171 : IRadBinkHostApi
{
    // V31.7.10_RAD_PLAYER_LOCK
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const long WsChild = 0x40000000L;
    private const long WsVisible = 0x10000000L;
    private const long WsPopup = unchecked((long)0x80000000L);
    private const long WsCaption = 0x00C00000L;
    private const long WsThickFrame = 0x00040000L;
    private const long WsSysMenu = 0x00080000L;
    private const long WsMinimizeBox = 0x00020000L;
    private const long WsMaximizeBox = 0x00010000L;
    private const long WsExNoActivate = 0x08000000L;

    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const int SwHide = 0;
    private const int SwShowNoActivate = 4;

    private static readonly nint HwndTop = 0;

    private readonly Process _launcherProcess;
    private readonly Process _rendererProcess;
    private readonly bool _rendererIsLauncher;
    private readonly Timer _resizeTimer;
    private readonly Timer _visualCutoffTimer;
    private readonly Timer _nominalEndTimer;
    private readonly Stopwatch _lifetime = Stopwatch.StartNew();
    private readonly double _nominalDurationMilliseconds;
    private readonly double _preRevealElapsedMilliseconds;
    private readonly int _visualCutoffLeadMilliseconds;
    private readonly int _nominalEndGraceMilliseconds;
    private int _lastWidth = -1;
    private int _lastHeight = -1;
    private int _visualCutoffTriggered;
    private int _nominalEndTriggered;
    private bool _disposed;

    private RadBinkEmbeddedHostApiV724323171(
        Process launcherProcess,
        Process rendererProcess,
        nint hostWindow,
        nint playerWindow,
        double windowReadyMilliseconds,
        double playbackAnchorMilliseconds,
        double nominalDurationMilliseconds)
    {
        _launcherProcess = launcherProcess;
        _rendererProcess = rendererProcess;
        _rendererIsLauncher = rendererProcess.Id == launcherProcess.Id;
        HostWindow = hostWindow;
        PlayerWindow = playerWindow;
        RendererProcessId = rendererProcess.Id;
        WindowReadyMilliseconds = windowReadyMilliseconds;
        PlaybackAnchorMilliseconds = playbackAnchorMilliseconds;
        _nominalDurationMilliseconds = nominalDurationMilliseconds;
        // V31.7.4 started the nominal timer only after the playback anchor, even
        // though BinkPlay had already been alive/rendering while its child HWND
        // was hidden.  Subtract that pre-reveal interval so the boundary follows
        // the BK2 timeline rather than the host-object lifetime.
        _preRevealElapsedMilliseconds = Math.Max(
            0.0,
            playbackAnchorMilliseconds - windowReadyMilliseconds);
        _visualCutoffLeadMilliseconds = ResolveIntEnvironment(
            "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
            defaultValue: 120,
            minimum: 0,
            maximum: 750);
        _nominalEndGraceMilliseconds = ResolveIntEnvironment(
            "SHARPEMU_RAD_NOMINAL_END_GRACE_MS",
            defaultValue: 0,
            minimum: 0,
            maximum: 1_000);
        IsEmbedded = true;

        _resizeTimer = new Timer(
            static state =>
            {
                if (state is RadBinkEmbeddedHostApiV724323171 host)
                {
                    host.SyncBounds();
                }
            },
            this,
            dueTime: 250,
            period: 250);

        var visualCutoffDue = nominalDurationMilliseconds > 0
            ? (int)Math.Clamp(
                Math.Ceiling(Math.Max(1.0,
                    nominalDurationMilliseconds -
                    _preRevealElapsedMilliseconds -
                    _visualCutoffLeadMilliseconds)),
                1.0,
                int.MaxValue)
            : Timeout.Infinite;

        _visualCutoffTimer = new Timer(
            static state =>
            {
                if (state is RadBinkEmbeddedHostApiV724323171 host)
                {
                    host.CutVisualBeforePostroll();
                }
            },
            this,
            dueTime: visualCutoffDue,
            period: Timeout.Infinite);

        var nominalDue = nominalDurationMilliseconds > 0
            ? (int)Math.Clamp(
                Math.Ceiling(Math.Max(1.0,
                    nominalDurationMilliseconds -
                    _preRevealElapsedMilliseconds +
                    _nominalEndGraceMilliseconds)),
                1.0,
                int.MaxValue)
            : Timeout.Infinite;

        _nominalEndTimer = new Timer(
            static state =>
            {
                if (state is RadBinkEmbeddedHostApiV724323171 host)
                {
                    host.EndAtNominalMovieBoundary();
                }
            },
            this,
            dueTime: nominalDue,
            period: Timeout.Infinite);
    }

    public bool IsEmbedded { get; }
    public nint HostWindow { get; }
    public nint PlayerWindow { get; }
    public int RendererProcessId { get; }
    public double WindowReadyMilliseconds { get; }
    public double PlaybackAnchorMilliseconds { get; }

    public bool IsPlaybackFinished
    {
        get
        {
            if (_disposed || Volatile.Read(ref _nominalEndTriggered) != 0)
            {
                return true;
            }

            return SafeHasExited(_rendererProcess);
        }
    }

    public int? PlaybackExitCode
    {
        get
        {
            if (!IsPlaybackFinished)
            {
                return null;
            }

            if (Volatile.Read(ref _nominalEndTriggered) != 0)
            {
                return 0;
            }

            try
            {
                return _rendererProcess.ExitCode;
            }
            catch
            {
                return null;
            }
        }
    }

    internal static IReadOnlySet<nint> CaptureTopLevelWindowSnapshot()
    {
        var windows = new HashSet<nint>();
        if (!OperatingSystem.IsWindows())
        {
            return windows;
        }

        _ = EnumWindows(
            (window, ignored) =>
            {
                windows.Add(window);
                return true;
            },
            0);
        return windows;
    }

    internal static IReadOnlySet<int> CaptureRadProcessSnapshot()
    {
        var pids = new HashSet<int>();
        if (!OperatingSystem.IsWindows())
        {
            return pids;
        }

        CaptureNamedProcesses("binkplay", pids);
        CaptureNamedProcesses("radvideo64", pids);
        return pids;
    }

    private static void CaptureNamedProcesses(
        string processName,
        HashSet<int> pids)
    {
        Process[] processes;
        try
        {
            processes = Process.GetProcessesByName(processName);
        }
        catch
        {
            return;
        }

        foreach (var process in processes)
        {
            try
            {
                pids.Add(process.Id);
            }
            catch
            {
            }
            finally
            {
                process.Dispose();
            }
        }
    }

    internal static bool TryAttach(
        Process launcherProcess,
        IReadOnlySet<nint> windowsBeforeLaunch,
        IReadOnlySet<int> radProcessesBeforeLaunch,
        string moviePath,
        double nominalDurationMilliseconds,
        Action<double>? beforeReveal,
        out RadBinkEmbeddedHostApiV724323171? hostApi)
    {
        hostApi = null;

        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        var stopwatch = Stopwatch.StartNew();
        var timeoutMs = ResolveIntEnvironment(
            "SHARPEMU_RAD_EMBED_TIMEOUT_MS",
            defaultValue: 6_000,
            minimum: 1_000,
            maximum: 20_000);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_host_attach_begin " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"launcher_pid={SafeProcessId(launcherProcess)} " +
            $"timeout_ms={timeoutMs} discovery=pid-mainwindow-no-windowtext");

        // Resolve SharpEmu first.  Do not read the window title.  In V31.7.3,
        // GetWindowText on the in-process SDL HWND could synchronously send
        // WM_GETTEXT to the presenter thread and stall this movie thread.
        var hostWindow = FindSharpEmuHostWindow(out var hostClass, out var hostArea);
        if (hostWindow != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_host_window_ready " +
                $"host_hwnd=0x{hostWindow.ToInt64():X} " +
                $"class='{Sanitize(hostClass)}' area={hostArea}");
        }

        Process? rendererProcess = null;
        nint playerWindow = 0;
        var lastProgressLog = -500L;
        // V31.7.17_RENDERER_TIMELINE_ZERO_AUDIO_SYNC
        // The nominal-end code already models BK2 timeline zero as the instant
        // the renderer HWND exists: it subtracts (playbackAnchor-windowReady).
        // Start the external Demon's Souls sidecar from that same clock.
        var beforeRevealInvokedAtRendererTimelineZero = false;
        var rendererTimelineZeroMs = double.NaN;

        while (stopwatch.ElapsedMilliseconds < timeoutMs)
        {
            if (hostWindow == 0)
            {
                hostWindow = FindSharpEmuHostWindow(out hostClass, out hostArea);
                if (hostWindow != 0)
                {
                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.rad_host_window_ready " +
                        $"host_hwnd=0x{hostWindow.ToInt64():X} " +
                        $"class='{Sanitize(hostClass)}' area={hostArea}");
                }
            }

            if (rendererProcess is null || playerWindow == 0)
            {
                var found = TryFindRadRenderer(
                    launcherProcess,
                    windowsBeforeLaunch,
                    radProcessesBeforeLaunch,
                    out var foundProcess,
                    out var foundWindow);

                if (found && foundProcess is not null && foundWindow != 0)
                {
                    rendererProcess = foundProcess;
                    playerWindow = foundWindow;
                    // V31.7.20_PREPARENT_HIDE
                    // Belt-and-suspenders: startup creation is hidden, and the
                    // first discovered HWND is hidden again before any style or
                    // SetParent operation. It is only shown after parent verify.
                    _ = ShowWindow(playerWindow, SwHide);
                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.rad_preparent_hidden " +
                        $"file='{Path.GetFileName(moviePath)}' " +
                        $"player_hwnd=0x{playerWindow.ToInt64():X} " +
                        "visible_before_parent=False");

                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.rad_renderer_window_ready " +
                        $"file='{Path.GetFileName(moviePath)}' " +
                        $"renderer_pid={rendererProcess.Id} " +
                        $"player_hwnd=0x{playerWindow.ToInt64():X} " +
                        $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
                    // V31.7.17: EBOOT StartIntro and the host's own nominal
                    // timer both use the movie timeline, not the later
                    // CPU-activity probe.  For attract only, fire the already
                    // prepared sample-exact WAV as soon as the RAD renderer
                    // HWND proves the movie timeline exists.
                    if (beforeReveal is not null &&
                        string.Equals(
                            Path.GetFileName(moviePath),
                            "attract_movie.bk2",
                            StringComparison.OrdinalIgnoreCase) &&
                        string.Equals(
                            Environment.GetEnvironmentVariable(
                                "SHARPEMU_RAD_ATTRACT_AUDIO_RENDERER_TIMELINE_ZERO"),
                            "1",
                            StringComparison.Ordinal) /* V31.7.20.5_PLAYBACK_ANCHOR_SIDECAR_OPTIN_EARLY */)
                    {
                        rendererTimelineZeroMs =
                            stopwatch.Elapsed.TotalMilliseconds;

                        try
                        {
                            beforeReveal(rendererTimelineZeroMs);
                            beforeRevealInvokedAtRendererTimelineZero = true;

                            Console.Error.WriteLine(
                                "[LOADER][INFO] bink2.rad_attract_audio_renderer_timeline_zero " +
                                $"file='attract_movie.bk2' " +
                                $"timeline_zero_ms={rendererTimelineZeroMs:F1} " +
                                "source=rad-renderer-window-ready " +
                                "eboot_state=StartIntro/MusicSkipIntro " +
                                "wav=sample-exact");
                        }
                        catch (Exception ex)
                        {
                            Console.Error.WriteLine(
                                "[LOADER][ERROR] bink2.rad_attract_audio_renderer_timeline_zero_failed " +
                                $"file='attract_movie.bk2' type={ex.GetType().Name} " +
                                $"message='{Sanitize(ex.Message)}'");
                            return false;
                        }
                    }
                }
            }

            if (hostWindow != 0 &&
                rendererProcess is not null &&
                playerWindow != 0)
            {
                break;
            }

            if (stopwatch.ElapsedMilliseconds - lastProgressLog >= 500)
            {
                lastProgressLog = stopwatch.ElapsedMilliseconds;
                Console.Error.WriteLine(
                    "[LOADER][TRACE] bink2.rad_host_attach_wait " +
                    $"file='{Path.GetFileName(moviePath)}' " +
                    $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1} " +
                    $"host=0x{hostWindow.ToInt64():X} " +
                    $"player=0x{playerWindow.ToInt64():X}");
            }

            Thread.Sleep(10);
        }

        if (hostWindow == 0 ||
            rendererProcess is null ||
            playerWindow == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_window_missing " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"host=0x{hostWindow.ToInt64():X} " +
                $"player=0x{playerWindow.ToInt64():X} " +
                $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1} " +
                "discovery=pid-mainwindow-no-windowtext");
            return false;
        }

        _ = ShowWindow(playerWindow, SwHide);

        TryPromoteRendererPriority(rendererProcess, moviePath);

        Marshal.SetLastPInvokeError(0);
        var stylePtr = GetWindowLongPtr(playerWindow, GwlStyle);
        var styleError = Marshal.GetLastPInvokeError();
        if (stylePtr == 0 && styleError != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_style_read_failed " +
                $"file='{Path.GetFileName(moviePath)}' win32={styleError}");
            return false;
        }

        var style = stylePtr.ToInt64();
        style &= ~(WsPopup |
                   WsCaption |
                   WsThickFrame |
                   WsSysMenu |
                   WsMinimizeBox |
                   WsMaximizeBox);
        // V31.7.20_HIDDEN_UNTIL_PARENTED
        style |= WsChild;
        style &= ~WsVisible;

        Marshal.SetLastPInvokeError(0);
        _ = SetWindowLongPtr(
            playerWindow,
            GwlStyle,
            new IntPtr(style));
        var setStyleError = Marshal.GetLastPInvokeError();
        if (setStyleError != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_style_write_failed " +
                $"file='{Path.GetFileName(moviePath)}' win32={setStyleError}");
            return false;
        }

        Marshal.SetLastPInvokeError(0);
        var previousParent = SetParent(playerWindow, hostWindow);
        var parentError = Marshal.GetLastPInvokeError();
        if (previousParent == 0 && parentError != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_setparent_failed " +
                $"file='{Path.GetFileName(moviePath)}' win32={parentError}");
            return false;
        }

        var actualParent = GetParent(playerWindow);
        var isChild = IsChild(hostWindow, playerWindow);
        if (actualParent != hostWindow && !isChild)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_parent_verify_failed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"expected=0x{hostWindow.ToInt64():X} " +
                $"actual=0x{actualParent.ToInt64():X}");
            return false;
        }

        if (!ResizeChildToHost(hostWindow, playerWindow))
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_resize_failed " +
                $"file='{Path.GetFileName(moviePath)}'");
            return false;
        }

        // Keep the renderer hidden while BinkPlay initializes.  V31.7.3
        // exposed the player's own BINK logo between movies.  Reveal only after
        // the playback anchor and hide again at the nominal BK2 boundary.
        var windowReadyMs = stopwatch.Elapsed.TotalMilliseconds;
        var anchorMs = WaitForPlaybackAnchor(rendererProcess, stopwatch);
        if (beforeRevealInvokedAtRendererTimelineZero)
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_old_anchor_delta " +
                $"file='attract_movie.bk2' " +
                $"renderer_timeline_zero_ms={rendererTimelineZeroMs:F1} " +
                $"old_playback_anchor_ms={anchorMs:F1} " +
                $"audio_advanced_vs_old_anchor_ms={Math.Max(0.0, anchorMs - rendererTimelineZeroMs):F1} " +
                "old_anchor=renderer-cpu-delta-8ms " +
                "new_anchor=renderer-window-ready");
        }

        // V31.7.7: synchronize sidecar audio to the same RAD playback anchor
        // while the child HWND is still hidden.  Starting audio after ShowWindow
        // added an avoidable host-side lag even when both streams ran at 1.0000x.
        if (beforeReveal is not null &&
            !beforeRevealInvokedAtRendererTimelineZero)
        {
            try
            {
                beforeReveal(anchorMs);
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_before_reveal_callback " +
                    $"file='{Path.GetFileName(moviePath)}' anchor_ms={anchorMs:F1} success=True");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    "[LOADER][ERROR] bink2.rad_before_reveal_callback_failed " +
                    $"file='{Path.GetFileName(moviePath)}' type={ex.GetType().Name} " +
                    $"message='{Sanitize(ex.Message)}'");
                return false;
            }
        }

        // V31.7.15_ATTRACT_AUDIO_PREROLL
        // The sidecar callback above starts WinMM audio asynchronously while
        // RAD is still hidden. Give the device a short head start before the
        // first visible attract frame. This is start-latency compensation,
        // not a movie-content offset and not a playback-rate correction.
        if (beforeReveal is not null &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            var audioPrerollMs = ResolveIntEnvironment(
                "SHARPEMU_RAD_ATTRACT_AUDIO_PREROLL_MS",
                defaultValue: 5,
                minimum: 0,
                maximum: 500);

            // V31.7.16_EBOOT_CURSOR_ARM
        // The sample-exact EBOOT timeline removes content lead/lag; the waveOut cursor now only proves playback has armed (5 ms default).
        // V31.7.15.2_WAVEOUT_AUDIO_CURSOR_PREROLL
            // Do not assume that sleeping N milliseconds after PlaySound means
            // N milliseconds of audio reached the device.  The deterministic
            // waveOut backend exposes its playback cursor; keep the RAD child
            // hidden until the requested PCM progress is observed.
            var cursorReached = true;
            var observedAudioMs = 0.0;
            var audioCursorWallWaitMs = 0.0;

            if (audioPrerollMs > 0)
            {
                cursorReached =
                    BinkDemonSoulsIntroAudioV7243227
                        .WaitForPresentationAudioProgress(
                            moviePath,
                            audioPrerollMs,
                            timeoutMilliseconds:
                                Math.Max(1_000, audioPrerollMs + 750),
                            out observedAudioMs,
                            out audioCursorWallWaitMs);

                if (!cursorReached)
                {
                    // Compatibility fallback for an unusual waveOut driver
                    // that does not expose TIME_SAMPLES/TIME_MS/TIME_BYTES.
                    Thread.Sleep(audioPrerollMs);
                }
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_preroll " +
                $"file='attract_movie.bk2' audio_head_start_ms={audioPrerollMs} " +
                $"audio_cursor_reached={cursorReached} " +
                $"audio_progress_ms={observedAudioMs:F1} " +
                $"audio_cursor_wall_wait_ms={audioCursorWallWaitMs:F1} " +
                $"anchor_ms={anchorMs:F1} reveal_elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1} " +
                "tempo=1.0000 offset_s=12.000 " +
                $"strategy={(cursorReached ? "waveout-playback-cursor" : "wallclock-fallback")}");
        }
        if (!ApplyPlayerInteractionLock(playerWindow, moviePath))
        {
            return false;
        }

        _ = ShowWindow(playerWindow, SwShowNoActivate);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_renderer_revealed " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"anchor_ms={anchorMs:F1} initial_logo_suppressed=True no_activate=True input_locked=True");

        hostApi = new RadBinkEmbeddedHostApiV724323171(
            launcherProcess,
            rendererProcess,
            hostWindow,
            playerWindow,
            windowReadyMs,
            anchorMs,
            nominalDurationMilliseconds);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_host_attached " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"launcher_pid={SafeProcessId(launcherProcess)} " +
            $"renderer_pid={rendererProcess.Id} " +
            $"host_hwnd=0x{hostWindow.ToInt64():X} " +
            $"player_hwnd=0x{playerWindow.ToInt64():X} " +
            $"window_ready_ms={windowReadyMs:F1} " +
            $"playback_anchor_ms={anchorMs:F1} " +
            $"nominal_duration_ms={nominalDurationMilliseconds:F1} " +
            "render_location=sharpemu-child-window " +
            "verified_parent=True");

        return true;
    }

    internal static void KillSpawnedRadProcesses(
        IReadOnlySet<int> radProcessesBeforeLaunch)
    {
        foreach (var processName in new[] { "binkplay", "radvideo64" })
        {
            Process[] processes;
            try
            {
                processes = Process.GetProcessesByName(processName);
            }
            catch
            {
                continue;
            }

            foreach (var process in processes)
            {
                try
                {
                    if (radProcessesBeforeLaunch.Contains(process.Id))
                    {
                        continue;
                    }

                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                        process.WaitForExit(1_500);
                    }
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
        }
    }

    private static bool TryFindRadRenderer(
        Process launcherProcess,
        IReadOnlySet<nint> windowsBeforeLaunch,
        IReadOnlySet<int> radProcessesBeforeLaunch,
        out Process? rendererProcess,
        out nint playerWindow)
    {
        rendererProcess = null;
        playerWindow = 0;

        // First use the exact process that Process.Start returned.  Refresh is
        // required because MainWindowHandle is cached by System.Diagnostics.
        if (TryGetMainWindow(launcherProcess, out var launcherWindow) ||
            TryFindTopLevelWindowByPidV31720(
                launcherProcess.Id,
                out launcherWindow))
        {
            rendererProcess = launcherProcess;
            playerWindow = launcherWindow;
            return true;
        }

        // RAD Video Tools often delegates to binkplay.exe.  Track that renderer
        // by PID rather than by caption text.
        if (TryFindNamedRenderer(
                "binkplay",
                radProcessesBeforeLaunch,
                out rendererProcess,
                out playerWindow))
        {
            return true;
        }

        if (TryFindNamedRenderer(
                "radvideo64",
                radProcessesBeforeLaunch,
                launcherProcess.Id,
                out rendererProcess,
                out playerWindow))
        {
            return true;
        }

        // Last-resort safe enumeration: only new HWNDs whose owning executable
        // is binkplay/radvideo64 are eligible.  No GetWindowText call is made.
        var bestWindow = (nint)0;
        var bestPid = 0;
        long bestArea = 0;

        _ = EnumWindows(
            (window, ignored) =>
            {
                // V31.7.20_HIDDEN_WINDOW_DISCOVERY
                // Startup-hidden RAD windows are intentionally not visible.
                // PID/executable provenance, not visibility, is the safety gate.
                if (windowsBeforeLaunch.Contains(window))
                {
                    return true;
                }

                _ = GetWindowThreadProcessId(window, out var pid);
                if (pid <= 0 ||
                    radProcessesBeforeLaunch.Contains(pid) ||
                    pid == Environment.ProcessId ||
                    !IsRadProcessId(pid))
                {
                    return true;
                }

                if (!GetWindowRect(window, out var rect))
                {
                    return true;
                }

                var width = Math.Max(0, rect.Right - rect.Left);
                var height = Math.Max(0, rect.Bottom - rect.Top);
                var area = (long)width * height;
                if (area <= bestArea)
                {
                    return true;
                }

                bestArea = area;
                bestWindow = window;
                bestPid = pid;
                return true;
            },
            0);

        if (bestWindow == 0 || bestPid <= 0)
        {
            return false;
        }

        try
        {
            rendererProcess = Process.GetProcessById(bestPid);
            playerWindow = bestWindow;
            return true;
        }
        catch
        {
            rendererProcess?.Dispose();
            rendererProcess = null;
            playerWindow = 0;
            return false;
        }
    }

    // V31.7.20_HIDDEN_WINDOW_DISCOVERY
    private static bool TryFindTopLevelWindowByPidV31720(
        int processId,
        out nint playerWindow)
    {
        playerWindow = 0;
        if (processId <= 0)
        {
            return false;
        }

        nint bestWindow = 0;
        long bestArea = -1;

        _ = EnumWindows(
            (window, ignored) =>
            {
                if (!IsWindow(window))
                {
                    return true;
                }

                _ = GetWindowThreadProcessId(window, out var pid);
                if (pid != processId)
                {
                    return true;
                }

                long area = 0;
                if (GetWindowRect(window, out var rect))
                {
                    var width = Math.Max(0, rect.Right - rect.Left);
                    var height = Math.Max(0, rect.Bottom - rect.Top);
                    area = (long)width * height;
                }

                if (bestWindow == 0 || area > bestArea)
                {
                    bestWindow = window;
                    bestArea = area;
                }

                return true;
            },
            0);

        playerWindow = bestWindow;
        return playerWindow != 0;
    }
    private static bool TryFindNamedRenderer(
        string processName,
        IReadOnlySet<int> radProcessesBeforeLaunch,
        out Process? rendererProcess,
        out nint playerWindow) =>
        TryFindNamedRenderer(
            processName,
            radProcessesBeforeLaunch,
            -1,
            out rendererProcess,
            out playerWindow);

    private static bool TryFindNamedRenderer(
        string processName,
        IReadOnlySet<int> radProcessesBeforeLaunch,
        int excludedPid,
        out Process? rendererProcess,
        out nint playerWindow)
    {
        rendererProcess = null;
        playerWindow = 0;

        Process[] processes;
        try
        {
            processes = Process.GetProcessesByName(processName);
        }
        catch
        {
            return false;
        }

        Process? bestProcess = null;
        nint bestWindow = 0;
        long bestArea = 0;

        foreach (var process in processes)
        {
            var keep = false;
            try
            {
                if (process.Id == excludedPid ||
                    radProcessesBeforeLaunch.Contains(process.Id) ||
                    process.HasExited)
                {
                    continue;
                }

                if (!TryGetMainWindow(process, out var window) &&
                    !TryFindTopLevelWindowByPidV31720(
                        process.Id,
                        out window))
                {
                    continue;
                }

                if (!GetWindowRect(window, out var rect))
                {
                    continue;
                }

                var width = Math.Max(0, rect.Right - rect.Left);
                var height = Math.Max(0, rect.Bottom - rect.Top);
                var area = (long)width * height;
                if (area <= bestArea)
                {
                    continue;
                }

                bestProcess?.Dispose();
                bestProcess = process;
                bestWindow = window;
                bestArea = area;
                keep = true;
            }
            catch
            {
            }
            finally
            {
                if (!keep && !ReferenceEquals(process, bestProcess))
                {
                    process.Dispose();
                }
            }
        }

        if (bestProcess is null || bestWindow == 0)
        {
            bestProcess?.Dispose();
            return false;
        }

        rendererProcess = bestProcess;
        playerWindow = bestWindow;
        return true;
    }

    private static bool TryGetMainWindow(
        Process process,
        out nint window)
    {
        window = 0;
        try
        {
            if (process.HasExited)
            {
                return false;
            }

            process.Refresh();
            window = process.MainWindowHandle;
            return window != 0 &&
                   IsWindow(window) &&
                   IsWindowVisible(window);
        }
        catch
        {
            window = 0;
            return false;
        }
    }

    private static bool IsRadProcessId(int pid)
    {
        Process? process = null;
        try
        {
            process = Process.GetProcessById(pid);
            var name = process.ProcessName;
            return string.Equals(
                       name,
                       "binkplay",
                       StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(
                       name,
                       "radvideo64",
                       StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
        finally
        {
            process?.Dispose();
        }
    }

    private static nint FindSharpEmuHostWindow(
        out string windowClass,
        out long area)
    {
        var currentPid = Environment.ProcessId;
        var best = (nint)0;
        var bestClass = string.Empty;
        var bestArea = 0L;
        var bestScore = long.MinValue;

        _ = EnumWindows(
            (window, ignored) =>
            {
                _ = GetWindowThreadProcessId(window, out var pid);
                if (pid != currentPid || !IsWindowVisible(window))
                {
                    return true;
                }

                if (!GetClientRect(window, out var rect))
                {
                    return true;
                }

                var width = Math.Max(0, rect.Right - rect.Left);
                var height = Math.Max(0, rect.Bottom - rect.Top);
                var candidateArea = (long)width * height;
                if (candidateArea <= 0)
                {
                    return true;
                }

                var candidateClass = GetWindowClass(window);
                var classBonus =
                    candidateClass.Contains(
                        "SDL",
                        StringComparison.OrdinalIgnoreCase)
                        ? long.MaxValue / 8
                        : 0;

                var score = candidateArea + classBonus;
                if (score > bestScore)
                {
                    bestScore = score;
                    bestArea = candidateArea;
                    bestClass = candidateClass;
                    best = window;
                }

                return true;
            },
            0);

        windowClass = bestClass;
        area = bestArea;
        return best;
    }

    private static string GetWindowClass(nint window)
    {
        var buffer = new StringBuilder(256);
        var length = GetClassNameW(
            window,
            buffer,
            buffer.Capacity);
        return length > 0
            ? buffer.ToString()
            : string.Empty;
    }

    private static double WaitForPlaybackAnchor(
        Process rendererProcess,
        Stopwatch launchWatch)
    {
        var delayMs = ResolveIntEnvironment(
            "SHARPEMU_RAD_AUDIO_ANCHOR_DELAY_MS",
            defaultValue: 0,
            minimum: 0,
            maximum: 750);

        TimeSpan initialCpu;
        try
        {
            rendererProcess.Refresh();
            initialCpu = rendererProcess.TotalProcessorTime;
        }
        catch
        {
            initialCpu = TimeSpan.Zero;
        }

        var cpuDeadline = Stopwatch.StartNew();
        while (cpuDeadline.ElapsedMilliseconds < 1_000 &&
               !SafeHasExited(rendererProcess))
        {
            try
            {
                rendererProcess.Refresh();
                var cpuDelta =
                    rendererProcess.TotalProcessorTime - initialCpu;
                if (cpuDelta.TotalMilliseconds >= 8.0)
                {
                    break;
                }
            }
            catch
            {
                break;
            }

            Thread.Sleep(5);
        }

        if (delayMs > 0 && !SafeHasExited(rendererProcess))
        {
            Thread.Sleep(delayMs);
        }

        return launchWatch.Elapsed.TotalMilliseconds;
    }

    private void SyncBounds()
    {
        if (_disposed ||
            SafeHasExited(_rendererProcess) ||
            HostWindow == 0 ||
            PlayerWindow == 0 ||
            !IsWindow(HostWindow) ||
            !IsWindow(PlayerWindow) ||
            !GetClientRect(HostWindow, out var rect))
        {
            return;
        }

        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        if (width == _lastWidth && height == _lastHeight)
        {
            return;
        }

        if (ResizeChild( PlayerWindow, width, height))
        {
            _lastWidth = width;
            _lastHeight = height;
            Console.Error.WriteLine(
                "[LOADER][TRACE] bink2.rad_host_resize " +
                $"renderer_pid={RendererProcessId} width={width} height={height} changed=True");
        }
    }

    private static bool ResizeChildToHost(
        nint hostWindow,
        nint playerWindow)
    {
        if (!GetClientRect(hostWindow, out var rect))
        {
            return false;
        }

        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        return ResizeChild(playerWindow, width, height);
    }

    private static bool ResizeChild(nint playerWindow, int width, int height)
    {
        var clipPixels = ResolveIntEnvironment(
            "SHARPEMU_RAD_CONTROL_STRIP_CLIP_PX",
            defaultValue: 24,
            minimum: 0,
            maximum: 96);

        // Keep the player's bottom seek/control strip below the SharpEmu child
        // clipping rectangle.  This is presentation-only; the movie timeline is
        // still owned by RAD and continues advancing normally.
        return SetWindowPos(
            playerWindow,
            HwndTop,
            0,
            0,
            width,
            checked(height + clipPixels),
            SwpNoActivate | SwpNoZOrder);
    }

    private static bool ApplyPlayerInteractionLock(
        nint playerWindow,
        string moviePath)
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_RAD_PLAYER_INPUT_LOCK"),
                "0",
                StringComparison.Ordinal))
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.rad_player_interaction_lock_disabled " +
                $"file='{Path.GetFileName(moviePath)}' explicit_override=True");
            return true;
        }

        Marshal.SetLastPInvokeError(0);
        var exStylePtr = GetWindowLongPtr(playerWindow, GwlExStyle);
        var exStyleError = Marshal.GetLastPInvokeError();
        if (exStylePtr == 0 && exStyleError != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_player_interaction_lock_failed " +
                $"file='{Path.GetFileName(moviePath)}' stage=read-exstyle win32={exStyleError}");
            return false;
        }

        var exStyle = exStylePtr.ToInt64() | WsExNoActivate;
        Marshal.SetLastPInvokeError(0);
        _ = SetWindowLongPtr(playerWindow, GwlExStyle, new IntPtr(exStyle));
        var setExStyleError = Marshal.GetLastPInvokeError();
        if (setExStyleError != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_player_interaction_lock_failed " +
                $"file='{Path.GetFileName(moviePath)}' stage=write-exstyle win32={setExStyleError}");
            return false;
        }

        _ = EnableWindow(playerWindow, false);

        var descendantsDisabled = 0;
        var controlsHidden = 0;
        _ = EnumChildWindows(
            playerWindow,
            (child, ignored) =>
            {
                _ = EnableWindow(child, false);
                descendantsDisabled++;

                var className = GetWindowClass(child);
                if (IsInteractiveControlClass(className))
                {
                    _ = ShowWindow(child, SwHide);
                    controlsHidden++;
                }

                return true;
            },
            0);

        var inputLocked = !IsWindowEnabled(playerWindow);
        var clipPixels = ResolveIntEnvironment(
            "SHARPEMU_RAD_CONTROL_STRIP_CLIP_PX",
            defaultValue: 24,
            minimum: 0,
            maximum: 96);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_player_interaction_locked " +
            $"file='{Path.GetFileName(moviePath)}' root_enabled={!inputLocked} " +
            $"descendants_disabled={descendantsDisabled} controls_hidden={controlsHidden} " +
            $"no_activate=True control_strip_clip_px={clipPixels} " +
            "mouse_keyboard_player_control=False");

        if (!inputLocked)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_player_interaction_lock_failed " +
                $"file='{Path.GetFileName(moviePath)}' stage=verify-root-disabled");
            return false;
        }

        return true;
    }

    private static bool IsInteractiveControlClass(string className)
    {
        return className.Equals("msctls_trackbar32", StringComparison.OrdinalIgnoreCase) ||
               className.Equals("ScrollBar", StringComparison.OrdinalIgnoreCase) ||
               className.Equals("ToolbarWindow32", StringComparison.OrdinalIgnoreCase) ||
               className.Equals("ReBarWindow32", StringComparison.OrdinalIgnoreCase) ||
               className.Equals("msctls_statusbar32", StringComparison.OrdinalIgnoreCase) ||
               className.Equals("Button", StringComparison.OrdinalIgnoreCase);
    }

    private static void TryPromoteRendererPriority(
        Process rendererProcess,
        string moviePath)
    {
        try
        {
            if (SafeHasExited(rendererProcess))
            {
                return;
            }

            rendererProcess.PriorityClass = ProcessPriorityClass.AboveNormal;
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_renderer_priority " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"renderer_pid={rendererProcess.Id} class=AboveNormal");
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            NotSupportedException)
        {
            Console.Error.WriteLine(
                "[LOADER][TRACE] bink2.rad_renderer_priority_unavailable " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"type={ex.GetType().Name}");
        }
    }

    private void CutVisualBeforePostroll()
    {
        if (_disposed ||
            _nominalDurationMilliseconds <= 0 ||
            Interlocked.Exchange(ref _visualCutoffTriggered, 1) != 0)
        {
            return;
        }

        if (PlayerWindow != 0 && IsWindow(PlayerWindow))
        {
            _ = ShowWindow(PlayerWindow, SwHide);
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_visual_cutoff " +
            $"renderer_pid={RendererProcessId} " +
            $"duration_ms={_nominalDurationMilliseconds:F1} " +
            $"lead_ms={_visualCutoffLeadMilliseconds} " +
            $"timeline_correction_ms={_preRevealElapsedMilliseconds:F1} " +
            "transition=black postroll_logo_visible=False");
    }

    private void EndAtNominalMovieBoundary()
    {
        if (_disposed ||
            _nominalDurationMilliseconds <= 0 ||
            Interlocked.Exchange(ref _nominalEndTriggered, 1) != 0)
        {
            return;
        }

        if (PlayerWindow != 0 && IsWindow(PlayerWindow))
        {
            _ = ShowWindow(PlayerWindow, SwHide);
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_nominal_end " +
            $"renderer_pid={RendererProcessId} " +
            $"duration_ms={_nominalDurationMilliseconds:F1} " +
            $"grace_ms={_nominalEndGraceMilliseconds} " +
            $"timeline_correction_ms={_preRevealElapsedMilliseconds:F1} " +
            $"visual_cutoff_triggered={(Volatile.Read(ref _visualCutoffTriggered) != 0)} " +
            "postroll_logo_suppressed=True");

        TryKillProcess(_rendererProcess);
    }

    private static bool SafeHasExited(Process process)
    {
        try
        {
            return process.HasExited;
        }
        catch
        {
            return true;
        }
    }

    private static int SafeProcessId(Process process)
    {
        try
        {
            return process.Id;
        }
        catch
        {
            return -1;
        }
    }

    private static int ResolveIntEnvironment(
        string name,
        int defaultValue,
        int minimum,
        int maximum)
    {
        var configured = Environment.GetEnvironmentVariable(name);
        return int.TryParse(configured, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : defaultValue;
    }

    private static string Sanitize(string? text) =>
        string.IsNullOrWhiteSpace(text)
            ? string.Empty
            : text.Replace('\r', ' ').Replace('\n', ' ').Trim();

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _resizeTimer.Dispose();
        _visualCutoffTimer.Dispose();
        _nominalEndTimer.Dispose();
        _lifetime.Stop();

        if (PlayerWindow != 0 && IsWindow(PlayerWindow))
        {
            _ = ShowWindow(PlayerWindow, SwHide);
        }

        // If RADVideo delegated to a separate binkplay.exe, ensure the actual
        // renderer cannot become a desktop top-level window during teardown.
        if (!_rendererIsLauncher)
        {
            TryKillProcess(_rendererProcess);
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_host_released " +
            $"renderer_pid={RendererProcessId} " +
            $"lifetime_ms={_lifetime.Elapsed.TotalMilliseconds:F1} " +
            "render_location=sharpemu-child-window");
    }

    private static void TryKillProcess(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(1_500);
            }
        }
        catch
        {
        }
        finally
        {
            try
            {
                process.Dispose();
            }
            catch
            {
            }
        }
    }

    private delegate bool EnumWindowsProc(nint hwnd, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(
        EnumWindowsProc lpEnumFunc,
        nint lParam);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumChildWindows(
        nint hWndParent,
        EnumWindowsProc lpEnumFunc,
        nint lParam);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnableWindow(
        nint hWnd,
        [MarshalAs(UnmanagedType.Bool)] bool bEnable);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowEnabled(nint hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(
        nint hWnd,
        out int lpdwProcessId);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint hWnd);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint hWnd);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsChild(
        nint hWndParent,
        nint hWnd);

    [DllImport("user32.dll", SetLastError = false)]
    private static extern nint GetParent(nint hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(
        nint hWnd,
        out Rect lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(
        nint hWnd,
        out Rect lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetParent(
        nint hWndChild,
        nint hWndNewParent);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(
        nint hWnd,
        int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(
        nint hWnd,
        int nIndex,
        nint dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint hWnd,
        nint hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags);

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(
        nint hWnd,
        int nCmdShow);

    [DllImport(
        "user32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = false)]
    private static extern int GetClassNameW(
        nint hWnd,
        StringBuilder lpClassName,
        int nMaxCount);
}
