// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE.Host;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-side Options/Start edge latch used only while HostMovieBridge owns a
/// Bink movie. The physical controller START button is already normalized by
/// SDL as HostGamepadButtons.Options. Keyboard TAB remains the default keyboard
/// Options binding. The bridge observes input; it does not replace scePad.
/// </summary>
internal static class HostOptionsSkipBridgeV6113262
{
    private const int VkTab = 0x09;
    private static int _started;
    private static int _skipRequested;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (Interlocked.Exchange(ref _started, 1) != 0)
        {
            return;
        }

        var thread = new Thread(Poll)
        {
            IsBackground = true,
            Name = "SharpEmu-BinkOptionsStartSkip",
            Priority = ThreadPriority.BelowNormal,
        };
        thread.Start();

        Console.Error.WriteLine(
            "[OPTIONS-SKIP][V1.0] bridge_ready " +
            "keyboard=TAB gamepad=START/OPTIONS active_movie_only=True");
    }

    internal static bool ConsumeRequest() =>
        Interlocked.Exchange(ref _skipRequested, 0) != 0;

    private static bool ReadOptionsDown(out string source)
    {
        source = string.Empty;

        try
        {
            var host = HostWindowInputSource.Current;
            if (host is not null)
            {
                Span<HostGamepadState> states = stackalloc HostGamepadState[4];
                var count = Math.Clamp(
                    host.GetGamepadStates(states),
                    0,
                    states.Length);

                for (var index = 0; index < count; index++)
                {
                    if ((states[index].Buttons & HostGamepadButtons.Options) != 0)
                    {
                        source = "GAMEPAD_START_OPTIONS";
                        return true;
                    }
                }

                if (host.IsKeyDown(VkTab))
                {
                    source = "KEYBOARD_TAB";
                    return true;
                }
            }
        }
        catch
        {
            // Input polling is best-effort and must never disturb emulation.
        }

        if (OperatingSystem.IsWindows())
        {
            try
            {
                if ((GetAsyncKeyState(VkTab) & 0x8000) != 0)
                {
                    source = "KEYBOARD_TAB_ASYNC";
                    return true;
                }
            }
            catch
            {
            }
        }

        return false;
    }

    private static void Poll()
    {
        var wasDown = false;

        while (true)
        {
            var down = ReadOptionsDown(out var source);
            if (down &&
                !wasDown &&
                HostMovieBridge.IsHostPlaybackActive)
            {
                Interlocked.Exchange(ref _skipRequested, 1);
                Console.Error.WriteLine(
                    "[OPTIONS-SKIP][V1.0] options_edge " +
                    $"source={source} action=request-current-bink-skip");
            }

            wasDown = down;
            Thread.Sleep(4);
        }
    }
}

