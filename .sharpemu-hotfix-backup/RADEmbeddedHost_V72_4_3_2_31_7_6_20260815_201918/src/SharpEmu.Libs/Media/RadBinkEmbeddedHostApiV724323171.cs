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
/// V72.4.3.2.31.7.5 keeps PID/HWND discovery and adds a two-stage PS5-like transition: the RAD child remains hidden through initialization, is revealed at the playback anchor, is hidden shortly before the nominal BK2 boundary, and the renderer is killed exactly at the nominal boundary.  This prevents the BinkPlay post-roll logo from ever becoming a SharpEmu frame while preserving all but the last few fade frames.
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
    private const int GwlStyle = -16;
    private const long WsChild = 0x40000000L;
    private const long WsVisible = 0x10000000L;
    private const long WsPopup = unchecked((long)0x80000000L);
    private const long WsCaption = 0x00C00000L;
    private const long WsThickFrame = 0x00040000L;
    private const long WsSysMenu = 0x00080000L;
    private const long WsMinimizeBox = 0x00020000L;
    private const long WsMaximizeBox = 0x00010000L;

    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const int SwHide = 0;
    private const int SwShow = 5;

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

                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.rad_renderer_window_ready " +
                        $"file='{Path.GetFileName(moviePath)}' " +
                        $"renderer_pid={rendererProcess.Id} " +
                        $"player_hwnd=0x{playerWindow.ToInt64():X} " +
                        $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
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
        style |= WsChild | WsVisible;

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
        _ = ShowWindow(playerWindow, SwShow);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_renderer_revealed " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"anchor_ms={anchorMs:F1} initial_logo_suppressed=True");

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
        if (TryGetMainWindow(launcherProcess, out var launcherWindow))
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
                if (windowsBeforeLaunch.Contains(window) ||
                    !IsWindowVisible(window))
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

                if (!TryGetMainWindow(process, out var window))
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
            defaultValue: 80,
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

    private static bool ResizeChild(nint playerWindow, int width, int height) =>
        SetWindowPos(
            playerWindow,
            HwndTop,
            0,
            0,
            width,
            height,
            SwpNoActivate | SwpNoZOrder);

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
