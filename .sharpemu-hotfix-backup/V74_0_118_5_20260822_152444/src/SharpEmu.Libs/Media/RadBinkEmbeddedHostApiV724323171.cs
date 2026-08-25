// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text;

using SharpEmu.Libs.VideoOut;

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
    // SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_V1_1_12
    private readonly Timer _v1112PostrollFenceTimer;
    private readonly string _v1112MoviePath;
    private readonly bool _v1112IsAttractMovie;
    private readonly int _v1112PostrollFenceDurationMilliseconds;
    private long _v1112PostrollFenceUntilTick;
    private int _v1112PostrollFenceActive;
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
        string moviePath,
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
        _v1112MoviePath = moviePath;
        _v1112IsAttractMovie =
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase);
        // V31.7.4 started the nominal timer only after the playback anchor, even
        // though BinkPlay had already been alive/rendering while its child HWND
        // was hidden.  Subtract that pre-reveal interval so the boundary follows
        // the BK2 timeline rather than the host-object lifetime.
        _preRevealElapsedMilliseconds = Math.Max(
            0.0,
            playbackAnchorMilliseconds - windowReadyMilliseconds);
        _visualCutoffLeadMilliseconds = _v1112IsAttractMovie
            ? ResolveIntEnvironment(
                "SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_LEAD_MS",
                defaultValue: 350,
                minimum: 120,
                maximum: 1_500)
            : ResolveIntEnvironment(
                "SHARPEMU_RAD_VISUAL_CUTOFF_LEAD_MS",
                defaultValue: 120,
                minimum: 0,
                maximum: 750);
        _v1112PostrollFenceDurationMilliseconds =
            ResolveIntEnvironment(
                "SHARPEMU_RAD_ATTRACT_POSTROLL_FENCE_MS",
                defaultValue: 1_200,
                minimum: 250,
                maximum: 3_000);
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

        _v1112PostrollFenceTimer = new Timer(
            static state =>
            {
                if (state is RadBinkEmbeddedHostApiV724323171 host)
                {
                    host.EnforceAttractPostrollHiddenV1112();
                }
            },
            this,
            dueTime: Timeout.Infinite,
            period: Timeout.Infinite);
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
        // V31.7.20.7_PLAYBACK_ANCHOR_IMMEDIATE
        // The previous sidecar callback was still executed only after RAD
        // attach/reparent work. Keep a separate latch so the exact WaveOut
        // callback can run immediately after WaitForPlaybackAnchor().
        var beforeRevealInvokedAtPlaybackAnchorImmediate = false;
        var rendererTimelineZeroMs = double.NaN;
        // SHARPEMU_DEMONS_ATTRACT_AUDIO_REVEAL_SYNC_V1_1_6
        // The observed build starts external attract audio while the RAD child
        // is still hidden. Keep the prepared callback, but make every legacy
        // pre-reveal branch see null. The callback is invoked only after
        // ShowWindow below.
        var v116AttractAudioRevealCallback = beforeReveal;
        var v116DeferAttractAudioToReveal =
            beforeReveal is not null &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase) &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_RAD_ATTRACT_AUDIO_REVEAL_SYNC") != "0";

        if (v116DeferAttractAudioToReveal)
        {
            beforeReveal = null;
        }

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
                                "SHARPEMU_RAD_ATTRACT_AUDIO_RENDERER_TIMELINE_ZERO_LEGACY"),
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

        if (!ResizeChildToHost(hostWindow, playerWindow, moviePath))
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
        // V31.7.20.9_DYNAMIC_VIDEO_TIMELINE_CURSOR
        // V20.8 proved sub-millisecond event -> WaveOut restart latency, but
        // starting local audio cursor 0 still mismatched. Publish anchorMs
        // through a named memory map before releasing the helper so it can
        // begin at the same inferred hidden-video cursor.
        var prearmedAudioEventName =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_PREARMED_AUDIO_EVENT");
        var prearmedAudioTimelineMapName =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_PREARMED_AUDIO_TIMELINE_MAP");
        if (v116DeferAttractAudioToReveal)
        {
            prearmedAudioEventName = null;
            prearmedAudioTimelineMapName = null;

            Console.Error.WriteLine(
                "[BINK-ATTRACT-SYNC][V1.1.6] pre_reveal_audio_paths_disabled " +
                "renderer_timeline_zero=True playback_anchor=True " +
                "prearmed_event=True preroll=True " +
                "target=renderer-show");
        }

        if (!string.IsNullOrWhiteSpace(prearmedAudioEventName) &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            var signalTicks = System.Diagnostics.Stopwatch.GetTimestamp();
            var mapWritten = false;
            var signaled = false;
            var signalError = string.Empty;

            try
            {
                if (!string.IsNullOrWhiteSpace(prearmedAudioTimelineMapName))
                {
                    using var timelineMap =
                        System.IO.MemoryMappedFiles.MemoryMappedFile.OpenExisting(
                            prearmedAudioTimelineMapName);
                    using var timelineView =
                        timelineMap.CreateViewAccessor(0, 64);

                    timelineView.Write(0, anchorMs);
                    timelineView.Write(8, signalTicks);
                    timelineView.Write(
                        16,
                        System.Diagnostics.Stopwatch.Frequency);
                    timelineView.Flush();
                    mapWritten = true;
                }

                using var prearmedAudioEvent =
                    System.Threading.EventWaitHandle.OpenExisting(
                        prearmedAudioEventName);
                signaled = prearmedAudioEvent.Set();
            }
            catch (Exception ex)
            {
                signalError =
                    ex.GetType().Name + ":" + Sanitize(ex.Message);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.v317209_dynamic_timeline_signal " +
                $"file='attract_movie.bk2' " +
                $"anchor_ms={anchorMs:F3} mono_ticks={signalTicks} " +
                $"freq={System.Diagnostics.Stopwatch.Frequency} " +
                $"event='{Sanitize(prearmedAudioEventName)}' " +
                $"timeline_map='{Sanitize(prearmedAudioTimelineMapName ?? string.Empty)}' " +
                $"map_written={mapWritten} signaled={signaled} " +
                $"cursor_policy=anchor-ms-as-hidden-video-position " +
                $"error='{signalError}'");

            if (!signaled ||
                (!string.IsNullOrWhiteSpace(prearmedAudioTimelineMapName) &&
                 !mapWritten))
            {
                return false;
            }
        }
        // V31.7.20.7: start the already-prepared V20.4 WaveOut program at
        // the first measured RAD playback anchor. Do this BEFORE the child
        // window is resized/reparented/locked/revealed so hidden RAD video
        // time and audio time advance together.
        if (beforeReveal is not null &&
            !beforeRevealInvokedAtRendererTimelineZero &&
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_PREARMED_AUDIO_EVENT")) &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase) &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_RAD_ATTRACT_AUDIO_PLAYBACK_ANCHOR_IMMEDIATE") != "0")
        {
            var immediateInvokeMs = stopwatch.Elapsed.TotalMilliseconds;
            try
            {
                beforeReveal(anchorMs);
                beforeRevealInvokedAtPlaybackAnchorImmediate = true;
                var immediateDoneMs = stopwatch.Elapsed.TotalMilliseconds;

                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.v317207_audio_anchor_immediate " +
                    $"file='attract_movie.bk2' " +
                    $"anchor_ms={anchorMs:F1} " +
                    $"callback_invoke_ms={immediateInvokeMs:F1} " +
                    $"invoke_delay_ms={Math.Max(0.0, immediateInvokeMs - anchorMs):F1} " +
                    $"callback_done_ms={immediateDoneMs:F1} " +
                    $"callback_cost_ms={Math.Max(0.0, immediateDoneMs - immediateInvokeMs):F1} " +
                    "clock=rad-playback-anchor");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    "[LOADER][ERROR] bink2.v317207_audio_anchor_immediate_failed " +
                    $"file='attract_movie.bk2' type={ex.GetType().Name} " +
                    $"message='{Sanitize(ex.Message)}'");
                return false;
            }
        }
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
            !beforeRevealInvokedAtRendererTimelineZero &&
            !beforeRevealInvokedAtPlaybackAnchorImmediate)
        {
            try
            {
                beforeReveal(anchorMs);
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_before_reveal_audio_arm " +
                    $"file='{Path.GetFileName(moviePath)}' anchor_ms={anchorMs:F1} success=True");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    "[LOADER][ERROR] bink2.rad_before_reveal_audio_arm_failed " +
                    $"file='{Path.GetFileName(moviePath)}' type={ex.GetType().Name} " +
                    $"message='{Sanitize(ex.Message)}'");
                return false;
            }
        }

        // V31.7.25_VISIBLE_FRAME_AUDIO_LATCH_STRUCTURAL_ADAPT
        // WaveOut is fully prepared but paused while the embedded RAD child is
        // hidden. The playback cursor remains exactly at zero until ShowWindow.
        if (beforeReveal is not null &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_preroll " +
                "file='attract_movie.bk2' audio_head_start_ms=0 " +
                "audio_cursor_reached=True audio_progress_ms=0.0 " +
                $"audio_cursor_wall_wait_ms=0.0 anchor_ms={anchorMs:F1} " +
                $"reveal_elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1} " +
                "tempo=1.0000 offset_s=12.000 strategy=visible-frame-audio-latch");
        }
        if (!ApplyPlayerInteractionLock(playerWindow, moviePath))
        {
            return false;
        }

        var revealCallMs = stopwatch.Elapsed.TotalMilliseconds;
        _ = ShowWindow(playerWindow, SwShowNoActivate);
        if (v116DeferAttractAudioToReveal &&
            v116AttractAudioRevealCallback is not null)
        {
            var v116RevealAudioInvokeMs =
                stopwatch.Elapsed.TotalMilliseconds;

            try
            {
                v116AttractAudioRevealCallback(
                    v116RevealAudioInvokeMs);
                // SHARPEMU_DEMONS_ATTRACT_DIRECT_RAD_WAVEOUT_RELEASE_V1_1_9
                // At this exact point V31.7.21 has already logged
                // state=paused-prepared.  Release the WinMM device here rather
                // than waiting for a Vulkan-visible-frame path that a RAD child
                // window never enters.
                var v119Released =
                    BinkDeterministicWavePlayerV317152.
                        TryReleasePreparedAfterRadCallbackV119(
                            out var v119ReleaseDetail);

                Console.Error.WriteLine(
                    "[BINK-ATTRACT-SYNC][V1.1.9] direct_rad_waveout_release " +
                    "file='attract_movie.bk2' " +
                    $"released={v119Released} " +
                    $"detail='{v119ReleaseDetail}' " +
                    "source=v116-post-showwindow-callback");

                if (v119Released)
                {
                    _ = System.Threading.Tasks.Task.Run(
                        async () =>
                        {
                            await System.Threading.Tasks.Task.Delay(120).
                                ConfigureAwait(false);

                            var v119CursorOk =
                                BinkDeterministicWavePlayerV317152.
                                    TryGetProgressMilliseconds(
                                        out var v119CursorMs);

                            Console.Error.WriteLine(
                                "[BINK-ATTRACT-SYNC][V1.1.9] waveout_cursor_probe " +
                                "file='attract_movie.bk2' " +
                                $"ok={v119CursorOk} " +
                                $"cursor_ms={v119CursorMs:F3} " +
                                "probe_delay_ms=120");
                        });
                }

                var v116RevealAudioDoneMs =
                    stopwatch.Elapsed.TotalMilliseconds;

                Console.Error.WriteLine(
                    "[BINK-ATTRACT-SYNC][V1.1.6] audio_started_at_renderer_reveal " +
                    $"file='attract_movie.bk2' " +
                    $"show_ms={v116RevealAudioInvokeMs:F1} " +
                    $"old_hidden_anchor_ms={anchorMs:F1} " +
                    $"hidden_lead_removed_ms={Math.Max(0.0, v116RevealAudioInvokeMs - anchorMs):F1} " +
                    $"callback_cost_ms={Math.Max(0.0, v116RevealAudioDoneMs - v116RevealAudioInvokeMs):F1} " +
                    "sync_source=renderer-show audio_preroll_ms=0");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    "[BINK-ATTRACT-SYNC][V1.1.6] audio_start_at_reveal_failed " +
                    $"type={ex.GetType().Name} " +
                    $"message='{Sanitize(ex.Message)}'");
                return false;
            }
        }

        if (beforeReveal is not null &&
            string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            var releaseBeginMs = stopwatch.Elapsed.TotalMilliseconds;
            var released = BinkDemonSoulsIntroAudioV7243227
                .NotifyPresentationStarted(moviePath);
            var releaseDoneMs = stopwatch.Elapsed.TotalMilliseconds;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_visible_frame_release " +
                "file='attract_movie.bk2' " +
                $"showwindow_ms={revealCallMs:F1} " +
                $"release_begin_ms={releaseBeginMs:F1} " +
                $"release_done_ms={releaseDoneMs:F1} " +
                $"release_cost_ms={Math.Max(0.0, releaseDoneMs - releaseBeginMs):F3} " +
                $"released={released} sync_source=post-showwindow-visible-frame");
        }
        // SHARPEMU_DEMONS_POST_STUDIOS_COVER_RELEASE_V1_1_4
        // Release only after the attract HWND is visible. Releasing before
        // ShowWindow would expose the stale guest Sony frame during RAD attach.
        if (string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            VulkanVideoPresenter.EndDemonSoulsPostStudiosBlackCoverV114(
                "attract-renderer-visible");
        }

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
            moviePath,
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
        if (Volatile.Read(
                ref _v1112PostrollFenceActive) != 0)
        {
            EnforceAttractPostrollHiddenV1112();
            return;
        }
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

        if (ResizeChild(PlayerWindow, width, height, _v1112MoviePath))
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
        nint playerWindow,
        string moviePath)
    {
        if (!GetClientRect(hostWindow, out var rect))
        {
            return false;
        }

        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        return ResizeChild(playerWindow, width, height, moviePath);
    }

    private static bool ResizeChild(
        nint playerWindow,
        int width,
        int height,
        string moviePath)
    {
        var clipPixels = ResolveIntEnvironment(
            "SHARPEMU_RAD_CONTROL_STRIP_CLIP_PX",
            defaultValue: 24,
            minimum: 0,
            maximum: 96);

        // Keep the player's bottom seek/control strip below the SharpEmu child
        // clipping rectangle.  This is presentation-only; the movie timeline is
        // still owned by RAD and continues advancing normally.
        var resized = SetWindowPos(
            playerWindow,
            HwndTop,
            0,
            0,
            width,
            checked(height + clipPixels),
            SwpNoActivate | SwpNoZOrder);

        if (resized)
        {
            ApplyDemonSoulsInteractiveRadRegionV111(
                playerWindow,
                moviePath,
                width,
                height);
        }

        return resized;
    }

    // SHARPEMU_V74_0_111_RAD_INTERACTIVE_UI_REGION
    private static void ApplyDemonSoulsInteractiveRadRegionV111(
        nint playerWindow,
        string moviePath,
        int width,
        int height)
    {
        if (!HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(moviePath) ||
            string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE"),
                "0",
                StringComparison.Ordinal))
        {
            return;
        }

        var fileName = Path.GetFileName(moviePath);
        var bottomGuestPercent = ResolveIntEnvironment(
            "SHARPEMU_DS_RAD_UI_BOTTOM_GUEST_PERCENT",
            defaultValue: 13,
            minimum: 0,
            maximum: 40);
        var leftGuestPercent =
            string.Equals(
                fileName,
                "logo_intro_loop.bk2",
                StringComparison.OrdinalIgnoreCase)
                ? 0
                : ResolveIntEnvironment(
                    "SHARPEMU_DS_RAD_MAIN_MENU_LEFT_GUEST_PERCENT",
                    defaultValue: 34,
                    minimum: 0,
                    maximum: 60);

        var left = Math.Clamp(
            (int)Math.Round(width * (leftGuestPercent / 100.0)),
            0,
            Math.Max(0, width - 1));
        var bottom = Math.Clamp(
            (int)Math.Round(height * ((100 - bottomGuestPercent) / 100.0)),
            1,
            height);

        var region = CreateRectRgn(left, 0, width, bottom);
        if (region == 0)
        {
            Console.Error.WriteLine(
                "[V74.0.111][RAD_INTERACTIVE_REGION] " +
                $"file='{fileName}' result=create-failed");
            return;
        }

        if (SetWindowRgn(playerWindow, region, true) == 0)
        {
            _ = DeleteObject(region);
            Console.Error.WriteLine(
                "[V74.0.111][RAD_INTERACTIVE_REGION] " +
                $"file='{fileName}' result=set-failed");
            return;
        }

        Console.Error.WriteLine(
            "[V74.0.111][RAD_INTERACTIVE_REGION] " +
            $"file='{fileName}' width={width} height={height} " +
            $"left_guest_pct={leftGuestPercent} bottom_guest_pct={bottomGuestPercent} " +
            $"rad_rect={left},0,{width},{bottom} guest_ui_visible=True");
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

    private void ArmAttractPostrollFenceV1112()
    {
        if (!_v1112IsAttractMovie ||
            _disposed ||
            SafeHasExited(_rendererProcess))
        {
            return;
        }

        var untilTick =
            checked(
                Environment.TickCount64 +
                _v1112PostrollFenceDurationMilliseconds);

        Volatile.Write(
            ref _v1112PostrollFenceUntilTick,
            untilTick);

        Interlocked.Exchange(
            ref _v1112PostrollFenceActive,
            1);

        EnforceAttractPostrollHiddenV1112();

        try
        {
            _ = _v1112PostrollFenceTimer.Change(
                dueTime: 0,
                period: 10);
        }
        catch (ObjectDisposedException)
        {
        }

        Console.Error.WriteLine(
            "[BINK-POSTROLL][V1.1.12] fence_armed " +
            "file='attract_movie.bk2' " +
            $"renderer_pid={RendererProcessId} " +
            $"lead_ms={_visualCutoffLeadMilliseconds} " +
            $"fence_ms={_v1112PostrollFenceDurationMilliseconds} " +
            $"until_tick={untilTick} rehide_period_ms=10");
    }

    private void EnforceAttractPostrollHiddenV1112()
    {
        if (_disposed ||
            Volatile.Read(
                ref _v1112PostrollFenceActive) == 0)
        {
            return;
        }

        var untilTick =
            Volatile.Read(
                ref _v1112PostrollFenceUntilTick);

        if (untilTick > 0 &&
            Environment.TickCount64 > untilTick)
        {
            Interlocked.Exchange(
                ref _v1112PostrollFenceActive,
                0);

            try
            {
                _ = _v1112PostrollFenceTimer.Change(
                    Timeout.Infinite,
                    Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
            }

            return;
        }

        if (PlayerWindow != 0 &&
            IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
        }

        // RAD/BinkPlay may create or re-show a top-level post-roll HWND after
        // the embedded child was hidden. Hide every window still owned by this
        // renderer PID. Never inspect titles and never touch SharpEmu's HWND.
        _ = EnumWindows(
            (window, ignored) =>
            {
                _ = GetWindowThreadProcessId(
                    window,
                    out var pid);

                if (pid == RendererProcessId)
                {
                    _ = ShowWindow(
                        window,
                        SwHide);
                }

                return true;
            },
            0);
    }
    private void CutVisualBeforePostroll()
    {
        if (_disposed ||
            _nominalDurationMilliseconds <= 0 ||
            Interlocked.Exchange(ref _visualCutoffTriggered, 1) != 0)
        {
            return;
        }

        // SHARPEMU_RAD_POSTROLL_HARD_CUTOFF_V1_1
        // Paint the SharpEmu swapchain black BEFORE the RAD child disappears.
        if (HostWindow != 0 &&
            IsWindow(HostWindow) &&
            GetClientRect(HostWindow, out var handoffRect))
        {
            var handoffWidth = Math.Max(1, handoffRect.Right - handoffRect.Left);
            var handoffHeight = Math.Max(1, handoffRect.Bottom - handoffRect.Top);
            VulkanVideoPresenter.SubmitHostMovieHandoffBlackV11(
                (uint)handoffWidth,
                (uint)handoffHeight,
                $"rad-pid-{RendererProcessId}");
        }
        if (_v1112IsAttractMovie)
        {
            ArmAttractPostrollFenceV1112();
        }
        else if (PlayerWindow != 0 &&
                 IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
        }
        // Hiding alone is insufficient: BinkPlay can expose its post-roll/icon
        // during the final window/process transition.  Terminate the renderer
        // at the already-established visual cutoff boundary (120 ms default).
        TryKillProcess(_rendererProcess);
        Interlocked.Exchange(ref _nominalEndTriggered, 1);


        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_visual_cutoff " +
            $"renderer_pid={RendererProcessId} " +
            $"duration_ms={_nominalDurationMilliseconds:F1} " +
            $"lead_ms={_visualCutoffLeadMilliseconds} " +
            $"timeline_correction_ms={_preRevealElapsedMilliseconds:F1} " +
            "transition=black postroll_logo_visible=False renderer_terminated_at_cutoff=True");
    }

    private void EndAtNominalMovieBoundary()
    {
        if (_disposed ||
            _nominalDurationMilliseconds <= 0 ||
            Interlocked.Exchange(ref _nominalEndTriggered, 1) != 0)
        {
            return;
        }

        if (_v1112IsAttractMovie)
        {
            Interlocked.Exchange(
                ref _v1112PostrollFenceActive,
                1);

            Volatile.Write(
                ref _v1112PostrollFenceUntilTick,
                checked(
                    Environment.TickCount64 +
                    _v1112PostrollFenceDurationMilliseconds));

            EnforceAttractPostrollHiddenV1112();

            BinkDemonSoulsIntroAudioV7243227.StopForMovie(
                _v1112MoviePath);

            try
            {
                _ = _v1112PostrollFenceTimer.Change(
                    Timeout.Infinite,
                    Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
            }

            Console.Error.WriteLine(
                "[BINK-POSTROLL][V1.1.12] attract_nominal_end " +
                "file='attract_movie.bk2' " +
                $"renderer_pid={RendererProcessId} " +
                "audio_stopped=True postroll_hidden=True " +
                "guest_drain_armed=True");
        }
        else if (PlayerWindow != 0 &&
                 IsWindow(PlayerWindow))
        {
            _ = ShowWindow(
                PlayerWindow,
                SwHide);
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
        _v1112PostrollFenceTimer.Dispose();
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

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern nint CreateRectRgn(
        int left,
        int top,
        int right,
        int bottom);

    [DllImport("gdi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(nint objectHandle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowRgn(
        nint window,
        nint region,
        [MarshalAs(UnmanagedType.Bool)] bool redraw);

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





