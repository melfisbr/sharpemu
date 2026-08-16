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
/// This interface deliberately separates the SharpEmu movie state machine from
/// the concrete RAD transport.  The current Windows implementation hosts the
/// official BinkPlay renderer as a child HWND of the SharpEmu SDL window.  A
/// licensed Bink SDK provider can later implement the same boundary without
/// changing HostMovieBridge.
/// </summary>
internal interface IRadBinkHostApi : IDisposable
{
    bool IsEmbedded { get; }
    nint HostWindow { get; }
    nint PlayerWindow { get; }
    double WindowReadyMilliseconds { get; }
    double PlaybackAnchorMilliseconds { get; }
}

/// <summary>
/// V72.4.3.2.31.7.1: embeds the official RAD BinkPlay window into SharpEmu.
///
/// Important distinction: this is an integrated host API, not a reimplementation
/// of the proprietary Bink decoder.  The decoder remains in the RAD process,
/// while its rendering HWND becomes a real child of SharpEmu (no independent
/// top-level player window).  True same-process decoding requires the licensed
/// Bink SDK DLL, which RAD Video Tools does not install.
/// </summary>
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

    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;
    private const uint SwpShowWindow = 0x0040;
    private const int SwHide = 0;
    private const int SwShow = 5;

    private static readonly nint HwndTop = 0;

    private readonly Process _playerProcess;
    private readonly Timer _resizeTimer;
    private readonly Stopwatch _lifetime = Stopwatch.StartNew();
    private bool _disposed;

    private RadBinkEmbeddedHostApiV724323171(
        Process playerProcess,
        nint hostWindow,
        nint playerWindow,
        double windowReadyMilliseconds,
        double playbackAnchorMilliseconds)
    {
        _playerProcess = playerProcess;
        HostWindow = hostWindow;
        PlayerWindow = playerWindow;
        WindowReadyMilliseconds = windowReadyMilliseconds;
        PlaybackAnchorMilliseconds = playbackAnchorMilliseconds;
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
            dueTime: 100,
            period: 100);
    }

    public bool IsEmbedded { get; }
    public nint HostWindow { get; }
    public nint PlayerWindow { get; }
    public double WindowReadyMilliseconds { get; }
    public double PlaybackAnchorMilliseconds { get; }

    internal static IReadOnlySet<nint> CaptureTopLevelWindowSnapshot()
    {
        if (!OperatingSystem.IsWindows())
        {
            return new HashSet<nint>();
        }

        var windows = new HashSet<nint>();
        _ = EnumWindows(
            (window, _) =>
            {
                windows.Add(window);
                return true;
            },
            0);
        return windows;
    }

    internal static bool TryAttach(
        Process playerProcess,
        IReadOnlySet<nint> windowsBeforeLaunch,
        string moviePath,
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
            defaultValue: 10_000,
            minimum: 1_000,
            maximum: 30_000);

        nint hostWindow = 0;
        nint playerWindow = 0;

        while (stopwatch.ElapsedMilliseconds < timeoutMs)
        {
            if (SafeHasExited(playerProcess))
            {
                break;
            }

            hostWindow = FindSharpEmuHostWindow();
            playerWindow = FindRadPlayerWindow(
                playerProcess.Id,
                windowsBeforeLaunch);

            if (hostWindow != 0 && playerWindow != 0)
            {
                break;
            }

            Thread.Sleep(15);
        }

        if (hostWindow == 0 || playerWindow == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_window_missing " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"host=0x{hostWindow.ToInt64():X} " +
                $"player=0x{playerWindow.ToInt64():X} " +
                $"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
            return false;
        }

        // Hide before reparenting so the user never gets a persistent external
        // BinkPlay top-level window.  A very short creation flash may still be
        // possible on some Windows window managers before EnumWindows sees it.
        _ = ShowWindow(playerWindow, SwHide);

        var style = GetWindowLongPtr(playerWindow, GwlStyle).ToInt64();
        style &= ~(WsPopup |
                   WsCaption |
                   WsThickFrame |
                   WsSysMenu |
                   WsMinimizeBox |
                   WsMaximizeBox);
        style |= WsChild | WsVisible;

        _ = SetWindowLongPtr(
            playerWindow,
            GwlStyle,
            new IntPtr(style));

        // SetParent legitimately returns NULL when the source HWND was a top-level
        // window (no previous parent). Clear the thread P/Invoke error first so a
        // stale Win32 error from Get/SetWindowLongPtr cannot turn that success into
        // a false failure.
        Marshal.SetLastPInvokeError(0);
        var previousParent = SetParent(playerWindow, hostWindow);
        var error = Marshal.GetLastPInvokeError();
        if (previousParent == 0 && error != 0)
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_setparent_failed " +
                $"file='{Path.GetFileName(moviePath)}' win32={error}");
            return false;
        }

        if (!ResizeChildToHost(hostWindow, playerWindow))
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_host_resize_failed " +
                $"file='{Path.GetFileName(moviePath)}'");
            return false;
        }

        _ = ShowWindow(playerWindow, SwShow);

        var windowReadyMs = stopwatch.Elapsed.TotalMilliseconds;
        var anchorMs = WaitForPlaybackAnchor(playerProcess, stopwatch);

        hostApi = new RadBinkEmbeddedHostApiV724323171(
            playerProcess,
            hostWindow,
            playerWindow,
            windowReadyMs,
            anchorMs);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_host_attached " +
            $"file='{Path.GetFileName(moviePath)}' " +
            $"host_hwnd=0x{hostWindow.ToInt64():X} " +
            $"player_hwnd=0x{playerWindow.ToInt64():X} " +
            $"window_ready_ms={windowReadyMs:F1} " +
            $"playback_anchor_ms={anchorMs:F1} " +
            "render_location=sharpemu-child-window");

        return true;
    }

    private static double WaitForPlaybackAnchor(
        Process playerProcess,
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
            playerProcess.Refresh();
            initialCpu = playerProcess.TotalProcessorTime;
        }
        catch
        {
            initialCpu = TimeSpan.Zero;
        }

        var cpuDeadline = Stopwatch.StartNew();
        while (cpuDeadline.ElapsedMilliseconds < 1_500 &&
               !SafeHasExited(playerProcess))
        {
            try
            {
                playerProcess.Refresh();
                var cpuDelta =
                    playerProcess.TotalProcessorTime - initialCpu;
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

        if (delayMs > 0 && !SafeHasExited(playerProcess))
        {
            Thread.Sleep(delayMs);
        }

        return launchWatch.Elapsed.TotalMilliseconds;
    }

    private static nint FindSharpEmuHostWindow()
    {
        var currentPid = Environment.ProcessId;
        nint best = 0;
        long bestArea = 0;

        _ = EnumWindows(
            (window, _) =>
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
                var area = (long)width * height;
                if (area <= 0)
                {
                    return true;
                }

                var title = GetWindowTitle(window);
                var titleLooksRight =
                    title.Contains("SharpEmu", StringComparison.OrdinalIgnoreCase);

                // Prefer a SharpEmu-titled SDL window.  If SDL reports an empty
                // title very early, still allow the largest process-owned HWND.
                var score = titleLooksRight ? area + long.MaxValue / 4 : area;
                if (score > bestArea)
                {
                    bestArea = score;
                    best = window;
                }

                return true;
            },
            0);

        return best;
    }

    private static nint FindRadPlayerWindow(
        int playerProcessId,
        IReadOnlySet<nint> windowsBeforeLaunch)
    {
        nint best = 0;
        long bestArea = 0;

        _ = EnumWindows(
            (window, _) =>
            {
                if (!IsWindowVisible(window))
                {
                    return true;
                }

                _ = GetWindowThreadProcessId(window, out var pid);
                var title = GetWindowTitle(window);
                var sameProcess = pid == playerProcessId;
                var newBinkWindow =
                    !windowsBeforeLaunch.Contains(window) &&
                    title.Contains("Bink", StringComparison.OrdinalIgnoreCase);

                if (!sameProcess && !newBinkWindow)
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
                if (area <= 0)
                {
                    return true;
                }

                if (area > bestArea)
                {
                    bestArea = area;
                    best = window;
                }

                return true;
            },
            0);

        return best;
    }

    private void SyncBounds()
    {
        if (_disposed ||
            SafeHasExited(_playerProcess) ||
            HostWindow == 0 ||
            PlayerWindow == 0 ||
            !IsWindow(HostWindow) ||
            !IsWindow(PlayerWindow))
        {
            return;
        }

        _ = ResizeChildToHost(HostWindow, PlayerWindow);
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

        return SetWindowPos(
            playerWindow,
            HwndTop,
            0,
            0,
            width,
            height,
            SwpNoActivate | SwpFrameChanged | SwpShowWindow);
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

    private static string GetWindowTitle(nint window)
    {
        var length = GetWindowTextLengthW(window);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        _ = GetWindowTextW(window, builder, builder.Capacity);
        return builder.ToString();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _resizeTimer.Dispose();
        _lifetime.Stop();

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_host_released " +
            $"lifetime_ms={_lifetime.Elapsed.TotalMilliseconds:F1} " +
            "render_location=sharpemu-child-window");
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetWindowTextLengthW(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetWindowTextW(
        nint hWnd,
        StringBuilder lpString,
        int nMaxCount);
}
