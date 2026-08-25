namespace SharpEmu.Libs.VideoOut;

internal static class HostFramePacerV7609
{
    private static readonly bool Enabled =
        !string.Equals(Environment.GetEnvironmentVariable("SHARPEMU_HOST_FRAME_PACER"), "0", StringComparison.Ordinal);
    private static readonly double TargetFps =
        double.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_HOST_TARGET_FPS"), out var fps)
            ? Math.Clamp(fps, 30.0, 120.0) : 60.0;
    private static readonly long PeriodTicks =
        (long)(System.Diagnostics.Stopwatch.Frequency / TargetFps);
    private static long _next;

    internal static void PaceBeforePresent()
    {
        if (!Enabled || PeriodTicks <= 0) return;
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        var next = Interlocked.Read(ref _next);
        if (next == 0 || now > next + PeriodTicks * 2)
        {
            Interlocked.Exchange(ref _next, now + PeriodTicks);
            return;
        }
        if (now < next)
        {
            var remainMs = (next - now) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
            if (remainMs >= 1.0)
            {
                var sleepMs = Math.Max(0, (int)(remainMs - 0.3));
                if (sleepMs > 0) Thread.Sleep(sleepMs);
                while (System.Diagnostics.Stopwatch.GetTimestamp() < next) Thread.SpinWait(32);
            }
            Interlocked.Exchange(ref _next, next + PeriodTicks);
            return;
        }
        Interlocked.Exchange(ref _next, now + PeriodTicks);
    }
}
