// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Runtime.InteropServices;

namespace SharpEmu.HLE.Host;

/// <summary>
/// Routes emulated input through the active cross-platform host window.
/// </summary>
internal sealed class WindowHostInput : IHostInput
{
    public void EnsureStarted()
    {
        // SDL owns device discovery and pumps it on the window thread.
    }

    public int GetGamepadStates(Span<HostGamepadState> destination) =>
        HostWindowInputSource.Current?.GetGamepadStates(destination) ?? 0;

    public string? DescribeConnectedGamepad() =>
        HostWindowInputSource.Current?.DescribeConnectedGamepad();

    public void SetRumble(byte largeMotor, byte smallMotor) =>
        HostWindowInputSource.Current?.SetRumble(largeMotor, smallMotor);

    public void SetTriggerRumble(byte? leftTrigger, byte? rightTrigger) =>
        HostWindowInputSource.Current?.SetTriggerRumble(leftTrigger, rightTrigger);

    public void SetAdaptiveTriggerEffect(
        HostAdaptiveTriggerEffect? leftTrigger,
        HostAdaptiveTriggerEffect? rightTrigger) =>
        HostWindowInputSource.Current?.SetAdaptiveTriggerEffect(leftTrigger, rightTrigger);

    public void SetLightbar(byte red, byte green, byte blue) =>
        HostWindowInputSource.Current?.SetLightbar(red, green, blue);

    public void ResetLightbar() => HostWindowInputSource.Current?.ResetLightbar();

    public bool IsHostWindowFocused()
    {
        if (HostWindowInputSource.Current?.HasKeyboardFocus == true)
        {
            return true;
        }

        // SHARPEMU_V69_0_3_GLOBAL_HOST_INPUT
        return IsCurrentProcessForegroundWindow();
    }

    public bool IsKeyDown(int virtualKey)
    {
        if (HostWindowInputSource.Current?.IsKeyDown(virtualKey) == true)
        {
            return true;
        }

        if (!IsCurrentProcessForegroundWindow())
        {
            return false;
        }

        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private static bool IsCurrentProcessForegroundWindow()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        var foregroundWindow = GetForegroundWindow();
        if (foregroundWindow == 0)
        {
            return false;
        }

        _ = GetWindowThreadProcessId(foregroundWindow, out var processId);
        return processId == unchecked((uint)Environment.ProcessId);
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);
}
