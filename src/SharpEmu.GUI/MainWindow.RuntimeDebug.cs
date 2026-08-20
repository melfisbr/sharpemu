using System;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace SharpEmu.GUI;

public partial class MainWindow
{
    private bool _runtimeDebugChildCaptureHooked;
    private bool _runtimeDebugLaunchObserved;
    private int _runtimeDebugConsoleBacklogIndex;
    private EmulatorProcess? _runtimeDebugAttachedEmulator;

    private void RuntimeDebugButton_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button button)
        {
            return;
        }

        try
        {
            if (RuntimeDebugSession.IsActive)
            {
                StopRuntimeDebugChildCapture();
                RuntimeDebugSession.Stop("user");
                button.Content = "Debug";
                return;
            }

            RuntimeDebugSession.Start(DataContext);
            StartRuntimeDebugChildCapture();
            button.Content = "Stop Debug";
        }
        catch (Exception ex)
        {
            StopRuntimeDebugChildCapture();
            RuntimeDebugSession.RecordFrontendError(ex);
            button.Content = RuntimeDebugSession.IsActive ? "Stop Debug" : "Debug";
        }
    }

    private void StartRuntimeDebugChildCapture()
    {
        if (_runtimeDebugChildCaptureHooked)
        {
            return;
        }

        _runtimeDebugLaunchObserved = false;
        _runtimeDebugAttachedEmulator = null;
        _runtimeDebugConsoleBacklogIndex = _allConsoleLines.Count;

        // This timer already exists and flushes EmulatorProcess.OutputReceived
        // into _allConsoleLines every 80 ms. Our handler is added later, so the
        // normal GUI flush executes first and gives us a loss-resistant backlog
        // for loader lines emitted before we can subscribe to the child event.
        _consoleFlushTimer.Tick += RuntimeDebugChildCaptureTick;
        _runtimeDebugChildCaptureHooked = true;
    }

    private void StopRuntimeDebugChildCapture()
    {
        if (_runtimeDebugChildCaptureHooked)
        {
            _consoleFlushTimer.Tick -= RuntimeDebugChildCaptureTick;
            _runtimeDebugChildCaptureHooked = false;
        }

        if (_runtimeDebugAttachedEmulator is not null)
        {
            _runtimeDebugAttachedEmulator.OutputReceived -= RuntimeDebugOnChildOutput;
            _runtimeDebugAttachedEmulator = null;
        }

        _runtimeDebugLaunchObserved = false;
        _runtimeDebugConsoleBacklogIndex = 0;
    }

    private void RuntimeDebugChildCaptureTick(object? sender, EventArgs e)
    {
        if (!RuntimeDebugSession.IsActive)
        {
            return;
        }

        var launchActive =
            _pendingLaunch is not null ||
            _emulator is not null ||
            _isRunning;

        if (!launchActive && !_runtimeDebugLaunchObserved)
        {
            _runtimeDebugConsoleBacklogIndex = _allConsoleLines.Count;
            return;
        }

        if (launchActive)
        {
            _runtimeDebugLaunchObserved = true;
        }

        // LaunchSelected clears the GUI console before starting the child.
        if (_runtimeDebugConsoleBacklogIndex > _allConsoleLines.Count)
        {
            _runtimeDebugConsoleBacklogIndex = 0;
        }

        if (_emulator is not null &&
            !ReferenceEquals(_runtimeDebugAttachedEmulator, _emulator))
        {
            if (_runtimeDebugAttachedEmulator is not null)
            {
                _runtimeDebugAttachedEmulator.OutputReceived -= RuntimeDebugOnChildOutput;
            }

            // Capture anything already forwarded before this subscription.
            while (_runtimeDebugConsoleBacklogIndex < _allConsoleLines.Count)
            {
                var line = _allConsoleLines[_runtimeDebugConsoleBacklogIndex++].Text;
                RuntimeDebugSession.RecordForwardedConsoleLine(line);
            }

            _runtimeDebugAttachedEmulator = _emulator;
            _runtimeDebugAttachedEmulator.OutputReceived += RuntimeDebugOnChildOutput;
        }
    }

    private static void RuntimeDebugOnChildOutput(string line, bool isError)
    {
        RuntimeDebugSession.RecordChildProcessOutput(line, isError);
    }
}

