using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// Host-side edge latch used only while HostMovieBridge owns the direct boot cinematic.
/// It does not replace scePad input during normal guest execution.
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
        if (!OperatingSystem.IsWindows() || Interlocked.Exchange(ref _started, 1) != 0)
            return;

        var thread = new Thread(Poll)
        {
            IsBackground = true,
            Name = "SharpEmu-OptionsDirectBootSkip",
            Priority = ThreadPriority.BelowNormal,
        };
        thread.Start();
        Console.Error.WriteLine("[OPTIONS-SKIP][V61.13.26.2] bridge_ready vk=0x09");
    }

    internal static bool ConsumeRequest()
        => Interlocked.Exchange(ref _skipRequested, 0) != 0;

    private static void Poll()
    {
        var wasDown = false;
        while (true)
        {
            var down = (GetAsyncKeyState(VkTab) & 0x8000) != 0;
            if (down && !wasDown)
            {
                Interlocked.Exchange(ref _skipRequested, 1);
                Console.Error.WriteLine("[OPTIONS-SKIP][V61.13.26.2] host_tab_options_edge");
            }
            wasDown = down;
            Thread.Sleep(4);
        }
    }
}
