using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

internal static class HostOptionsSkipTraceV6113261
{
    private const int VkTab = 0x09;
    private static int _started;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [ModuleInitializer]
    internal static void Initialize()
    {
        if (!OperatingSystem.IsWindows() ||
            Interlocked.Exchange(ref _started, 1) != 0)
            return;

        var thread = new Thread(TraceLoop)
        {
            IsBackground = true,
            Name = "SharpEmu-OptionsSkipTrace",
            Priority = ThreadPriority.BelowNormal,
        };

        thread.Start();

        Console.Error.WriteLine(
            "[OPTIONS-SKIP][V61.13.26.1] host_tab_trace_ready vk=0x09");
    }

    private static void TraceLoop()
    {
        var wasDown = false;

        while (true)
        {
            var down = (GetAsyncKeyState(VkTab) & 0x8000) != 0;

            if (down != wasDown)
            {
                Console.Error.WriteLine(
                    down
                        ? "[OPTIONS-SKIP][V61.13.26.1] host_tab_down"
                        : "[OPTIONS-SKIP][V61.13.26.1] host_tab_up");
                wasDown = down;
            }

            Thread.Sleep(4);
        }
    }
}
