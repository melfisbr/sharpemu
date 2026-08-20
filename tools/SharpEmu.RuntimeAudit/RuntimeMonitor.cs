using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace SharpEmu.RuntimeAudit;

internal sealed class RuntimeMonitor
{
    private readonly string _repo;
    private readonly string _eboot;
    private readonly string _emulator;
    private readonly string _output;
    private readonly AuditConfig _config;
    private readonly RuntimeClassifier _classifier;

    public RuntimeMonitor(
        string repositoryRoot,
        string ebootPath,
        string emulatorPath,
        string outputDirectory,
        AuditConfig config)
    {
        _repo = repositoryRoot;
        _eboot = ebootPath;
        _emulator = emulatorPath;
        _output = outputDirectory;
        _config = config;
        _classifier = new RuntimeClassifier(config.MaxEvidencePerCategory);
    }

    public async Task RunAsync(AuditReport report)
    {
        var runtime = report.Runtime;
        var stdoutPath = Path.Combine(_output, "stdout.log");
        var stderrPath = Path.Combine(_output, "stderr.log");
        var metricsPath = Path.Combine(_output, "process_metrics.csv");
        var gpuPath = Path.Combine(_output, "gpu_metrics.csv");

        var psi = new ProcessStartInfo
        {
            FileName = _emulator,
            Arguments = "\"" + _eboot + "\"",
            WorkingDirectory = Path.GetDirectoryName(_emulator) ?? _repo,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = false
        };

        foreach (var pair in _config.ChildEnvironment)
            psi.Environment[pair.Key] = pair.Value;
        foreach (var name in _config.UnsetChildEnvironment)
            psi.Environment.Remove(name);

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        using var stdoutWriter = new StreamWriter(stdoutPath, false, new System.Text.UTF8Encoding(true))
        {
            AutoFlush = true
        };
        using var stderrWriter = new StreamWriter(stderrPath, false, new System.Text.UTF8Encoding(true))
        {
            AutoFlush = true
        };

        var start = DateTimeOffset.Now;
        var sw = Stopwatch.StartNew();

        if (!process.Start())
            throw new InvalidOperationException("Failed to start SharpEmu.");

        var pid = process.Id;
        _classifier.AddStage("host", "process", $"SharpEmu started pid={pid}", start);

        var stdoutTask = PumpAsync(process.StandardOutput, stdoutWriter, "stdout", runtime);
        var stderrTask = PumpAsync(process.StandardError, stderrWriter, "stderr", runtime);
        var metricTask = SampleProcessAsync(process, sw, runtime.ProcessMetrics);
        var gpuTask = SampleGpuAsync(process, sw, runtime.GpuMetrics);

        var killedByTimeout = false;
        if (_config.MaxRuntimeSeconds > 0)
        {
            var timeout = Task.Delay(TimeSpan.FromSeconds(_config.MaxRuntimeSeconds));
            var exitTask = process.WaitForExitAsync();
            var first = await Task.WhenAny(exitTask, timeout);
            if (first == timeout && !process.HasExited)
            {
                killedByTimeout = true;
                try { process.Kill(true); } catch { }
            }
            await process.WaitForExitAsync();
        }
        else
        {
            await process.WaitForExitAsync();
        }

        await Task.WhenAll(stdoutTask, stderrTask);
        await metricTask;
        await gpuTask;
        sw.Stop();

        runtime.ExitCode = process.ExitCode;
        runtime.WallSeconds = sw.Elapsed.TotalSeconds;
        runtime.KilledByTimeout = killedByTimeout;
        runtime.StageEvents = _classifier.StageEvents;
        runtime.VideoEvents = _classifier.VideoEvents;
        runtime.AudioEvents = _classifier.AudioEvents;
        runtime.QueueEvents = _classifier.QueueEvents;
        runtime.UnmappedEvents = _classifier.UnmappedEvents;
        runtime.UnmappedFunctions = _classifier.GetUnmappedFunctions();
        runtime.ApiEvents = _classifier.ApiEvents;
        runtime.FileAccesses = _classifier.GetFileAccesses();

        BuildSummary(runtime);
        WriteMetricsCsv(metricsPath, runtime.ProcessMetrics);
        WriteGpuCsv(gpuPath, runtime.GpuMetrics);
    }

    private async Task PumpAsync(
        StreamReader reader,
        StreamWriter writer,
        string stream,
        RuntimeAudit runtime)
    {
        string? line;
        while ((line = await reader.ReadLineAsync()) is not null)
        {
            await writer.WriteLineAsync(line);
            if (stream == "stdout")
                runtime.StdoutLines++;
            else
                runtime.StderrLines++;

            _classifier.Ingest(stream, line, DateTimeOffset.Now);
        }
    }

    private async Task SampleProcessAsync(
        Process process,
        Stopwatch sw,
        List<ProcessMetric> metrics)
    {
        var previousCpu = TimeSpan.Zero;
        var previousElapsed = 0.0;

        while (true)
        {
            if (process.HasExited)
                break;

            try
            {
                process.Refresh();
                var currentCpu = process.TotalProcessorTime;
                var elapsed = sw.Elapsed.TotalSeconds;
                var cpuDelta = (currentCpu - previousCpu).TotalSeconds;
                var wallDelta = elapsed - previousElapsed;
                var cpuPercent = wallDelta > 0
                    ? Math.Max(0, cpuDelta / wallDelta / Environment.ProcessorCount * 100.0)
                    : 0;

                previousCpu = currentCpu;
                previousElapsed = elapsed;

                var memory = MemoryInfo.Get();
                metrics.Add(new ProcessMetric
                {
                    Timestamp = DateTimeOffset.Now,
                    ElapsedSeconds = elapsed,
                    CpuPercent = cpuPercent,
                    WorkingSetMb = process.WorkingSet64 / 1048576.0,
                    PrivateMemoryMb = process.PrivateMemorySize64 / 1048576.0,
                    VirtualMemoryMb = process.VirtualMemorySize64 / 1048576.0,
                    ThreadCount = SafeThreadCount(process),
                    HandleCount = SafeHandleCount(process),
                    AvailableSystemMemoryMb = memory.AvailableBytes / 1048576.0
                });
            }
            catch
            {
                // Process can exit between HasExited and Refresh.
            }

            await Task.Delay(Math.Max(100, _config.SampleIntervalMs));
        }
    }

    private async Task SampleGpuAsync(
        Process process,
        Stopwatch sw,
        List<GpuMetric> metrics)
    {
        while (true)
        {
            if (process.HasExited)
                break;

            try
            {
                var global = await AuditUtil.RunCaptureAsync(
                    "nvidia-smi.exe",
                    "--query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits",
                    _repo,
                    5000);

                var processMemory = await AuditUtil.RunCaptureAsync(
                    "nvidia-smi.exe",
                    "--query-compute-apps=pid,used_memory --format=csv,noheader,nounits",
                    _repo,
                    5000);

                if (!string.IsNullOrWhiteSpace(global))
                {
                    var firstLine = global.Split(
                        ['\r', '\n'],
                        StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
                    var fields = firstLine.Split(',').Select(x => x.Trim()).ToArray();
                    if (fields.Length >= 4)
                    {
                        var processMb = 0.0;
                        foreach (var line in processMemory.Split(
                                     ['\r', '\n'],
                                     StringSplitOptions.RemoveEmptyEntries))
                        {
                            var parts = line.Split(',').Select(x => x.Trim()).ToArray();
                            if (parts.Length >= 2 &&
                                int.TryParse(parts[0], out var pid) &&
                                pid == process.Id)
                            {
                                processMb = AuditUtil.ParseDouble(parts[1]);
                                break;
                            }
                        }

                        metrics.Add(new GpuMetric
                        {
                            Timestamp = DateTimeOffset.Now,
                            ElapsedSeconds = sw.Elapsed.TotalSeconds,
                            ProcessId = process.Id,
                            GpuName = fields[0],
                            UtilizationPercent = AuditUtil.ParseDouble(fields[1]),
                            MemoryUsedMb = AuditUtil.ParseDouble(fields[2]),
                            MemoryTotalMb = AuditUtil.ParseDouble(fields[3]),
                            ProcessMemoryMb = processMb
                        });
                    }
                }
            }
            catch
            {
                // NVIDIA telemetry is optional.
            }

            await Task.Delay(Math.Max(1000, _config.GpuSampleIntervalMs));
        }
    }

    private void BuildSummary(RuntimeAudit runtime)
    {
        var summary = runtime.Summary;

        if (runtime.ProcessMetrics.Count > 0)
        {
            summary.MaxWorkingSetMb = runtime.ProcessMetrics.Max(x => x.WorkingSetMb);
            summary.MaxPrivateMemoryMb = runtime.ProcessMetrics.Max(x => x.PrivateMemoryMb);
            summary.MaxCpuPercent = runtime.ProcessMetrics.Max(x => x.CpuPercent);
            summary.AvgCpuPercent = runtime.ProcessMetrics.Average(x => x.CpuPercent);
            summary.MinAvailableSystemMemoryMb = runtime.ProcessMetrics.Min(x => x.AvailableSystemMemoryMb);
        }

        if (runtime.GpuMetrics.Count > 0)
        {
            summary.MaxGpuMemoryUsedMb = runtime.GpuMetrics.Max(x => x.MemoryUsedMb);
            summary.MaxGpuUtilizationPercent = runtime.GpuMetrics.Max(x => x.UtilizationPercent);
        }

        summary.PresentCadenceLastHz = _classifier.PresentCadenceLastHz;
        summary.PresentCadenceAverageHz = _classifier.PresentCadences.Count > 0
            ? _classifier.PresentCadences.Average()
            : 0;
        summary.MaxGuestWorkPending = _classifier.MaxGuestWorkPending;
        summary.MaxSlowRenderWorkMs = _classifier.MaxSlowRenderWorkMs;
        summary.MaxSlowWaitMs = _classifier.MaxSlowWaitMs;
        summary.MaxSubmissionOvercommitPending = _classifier.MaxSubmissionOvercommitPending;
        summary.MaxComputeResourceTotalMs = _classifier.MaxComputeResourceTotalMs;
        summary.MaxComputeStorageMs = _classifier.MaxComputeStorageMs;
        summary.MaxComputeTextureMs = _classifier.MaxComputeTextureMs;
        summary.MaxComputeBufferMs = _classifier.MaxComputeBufferMs;
        summary.MaxComputeDescriptorMs = _classifier.MaxComputeDescriptorMs;
        summary.MaxComputePipelineMs = _classifier.MaxComputePipelineMs;
        summary.UnmappedRuntimeCount = runtime.UnmappedEvents.Count;
        summary.VideoEventCount = runtime.VideoEvents.Count;
        summary.AudioEventCount = runtime.AudioEvents.Count;
        summary.ApiEventCount = runtime.ApiEvents.Count;
        summary.UniqueFileAccessCount = runtime.FileAccesses.Count;
        summary.HeapCorruptionHits = _classifier.HeapCorruptionHits;
        summary.AccessViolationHits = _classifier.AccessViolationHits;
        summary.DeviceLostHits = _classifier.DeviceLostHits;
    }

    private static int SafeThreadCount(Process process)
    {
        try { return process.Threads.Count; }
        catch { return 0; }
    }

    private static int SafeHandleCount(Process process)
    {
        try { return process.HandleCount; }
        catch { return 0; }
    }

    private static void WriteMetricsCsv(string path, IEnumerable<ProcessMetric> metrics)
    {
        using var writer = new StreamWriter(path, false, new System.Text.UTF8Encoding(true));
        writer.WriteLine("timestamp,elapsed_seconds,cpu_percent,working_set_mb,private_memory_mb,virtual_memory_mb,threads,handles,available_system_memory_mb");
        foreach (var m in metrics)
        {
            writer.WriteLine(string.Join(",",
                AuditUtil.Csv(m.Timestamp.ToString("O")),
                m.ElapsedSeconds.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.CpuPercent.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.WorkingSetMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.PrivateMemoryMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.VirtualMemoryMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.ThreadCount,
                m.HandleCount,
                m.AvailableSystemMemoryMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture)));
        }
    }

    private static void WriteGpuCsv(string path, IEnumerable<GpuMetric> metrics)
    {
        using var writer = new StreamWriter(path, false, new System.Text.UTF8Encoding(true));
        writer.WriteLine("timestamp,elapsed_seconds,pid,gpu_name,gpu_util_percent,gpu_memory_used_mb,gpu_memory_total_mb,process_gpu_memory_mb");
        foreach (var m in metrics)
        {
            writer.WriteLine(string.Join(",",
                AuditUtil.Csv(m.Timestamp.ToString("O")),
                m.ElapsedSeconds.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.ProcessId,
                AuditUtil.Csv(m.GpuName),
                m.UtilizationPercent.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.MemoryUsedMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.MemoryTotalMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture),
                m.ProcessMemoryMb.ToString("F3", System.Globalization.CultureInfo.InvariantCulture)));
        }
    }
}

internal sealed class RuntimeClassifier
{
    private readonly int _limit;
    private readonly Dictionary<string, FileAccessRecord> _fileAccesses = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, UnmappedFunctionRecord> _unmappedFunctions = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    public List<RuntimeEvent> StageEvents { get; } = [];
    public List<RuntimeEvent> VideoEvents { get; } = [];
    public List<RuntimeEvent> AudioEvents { get; } = [];
    public List<RuntimeEvent> QueueEvents { get; } = [];
    public List<RuntimeEvent> UnmappedEvents { get; } = [];
    public List<RuntimeEvent> ApiEvents { get; } = [];
    public List<double> PresentCadences { get; } = [];

    public double PresentCadenceLastHz { get; private set; }
    public long MaxGuestWorkPending { get; private set; }
    public double MaxSlowRenderWorkMs { get; private set; }
    public double MaxSlowWaitMs { get; private set; }
    public long MaxSubmissionOvercommitPending { get; private set; }
    public double MaxComputeResourceTotalMs { get; private set; }
    public double MaxComputeStorageMs { get; private set; }
    public double MaxComputeTextureMs { get; private set; }
    public double MaxComputeBufferMs { get; private set; }
    public double MaxComputeDescriptorMs { get; private set; }
    public double MaxComputePipelineMs { get; private set; }
    public int HeapCorruptionHits { get; private set; }
    public int AccessViolationHits { get; private set; }
    public int DeviceLostHits { get; private set; }

    private static readonly Regex PathQuotedRegex = new(
        @"(?:path|file|source|target|root|movie|audio)\s*=\s*['""]([^'""]+)['""]",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex WindowsPathRegex = new(
        @"(?<![A-Za-z0-9_])([A-Za-z]:\\[^|<>""\r\n]+)",
        RegexOptions.Compiled);

    private static readonly Regex SceApiRegex = new(
        @"\b(?:sce[A-Z][A-Za-z0-9_]+|libSce[A-Za-z0-9_+\-.]+)\b",
        RegexOptions.Compiled);

    private static readonly Regex UnmappedRegex = new(
        @"\b(unmapped|unsupported|unimplemented|not implemented|unknown import|unknown nid|missing export|missing nid|missing function|stubbed|placeholder)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public RuntimeClassifier(int limit)
    {
        _limit = Math.Max(100, limit);
    }

    public void AddStage(string stream, string category, string text, DateTimeOffset timestamp)
    {
        lock (_gate)
            AddLimited(StageEvents, new RuntimeEvent { Timestamp = timestamp, Stream = stream, Category = category, Text = text });
    }

    public void Ingest(string stream, string line, DateTimeOffset timestamp)
    {
        lock (_gate)
        {
            var lower = line.ToLowerInvariant();

            if (IsStageLine(lower))
                AddLimited(StageEvents, Event(timestamp, stream, "stage", line));

            if (IsVideoLine(lower))
                AddLimited(VideoEvents, Event(timestamp, stream, "video", line));

            if (IsAudioLine(lower))
                AddLimited(AudioEvents, Event(timestamp, stream, "audio", line));

            if (IsQueueLine(lower))
                AddLimited(QueueEvents, Event(timestamp, stream, "queue", line));

            if (UnmappedRegex.IsMatch(line))
            {
                AddLimited(UnmappedEvents, Event(timestamp, stream, "unmapped", line));
                CaptureUnmappedFunction(line);
            }

            if (SceApiRegex.IsMatch(line) ||
                lower.Contains("vulkan") ||
                lower.Contains("vk.") ||
                lower.Contains("sdl"))
                AddLimited(ApiEvents, Event(timestamp, stream, "api", line));

            CapturePaths(line);
            CaptureQueueMetrics(line);

            if (line.Contains("0xC0000374", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("HEAP_CORRUPTION", StringComparison.OrdinalIgnoreCase))
                HeapCorruptionHits++;

            if (line.Contains("0xC0000005", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("ACCESS_VIOLATION", StringComparison.OrdinalIgnoreCase))
                AccessViolationHits++;

            if (line.Contains("VK_ERROR_DEVICE_LOST", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("ErrorDeviceLost", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("device lost", StringComparison.OrdinalIgnoreCase))
                DeviceLostHits++;
        }
    }

    public List<UnmappedFunctionRecord> GetUnmappedFunctions()
    {
        lock (_gate)
        {
            return _unmappedFunctions.Values
                .OrderByDescending(x => x.Count)
                .ThenBy(x => x.Function, StringComparer.OrdinalIgnoreCase)
                .ThenBy(x => x.Nid, StringComparer.OrdinalIgnoreCase)
                .Take(10000)
                .ToList();
        }
    }

    public List<FileAccessRecord> GetFileAccesses()
    {
        lock (_gate)
        {
            return _fileAccesses.Values
                .OrderByDescending(x => x.Count)
                .ThenBy(x => x.Path, StringComparer.OrdinalIgnoreCase)
                .Take(20000)
                .ToList();
        }
    }

    private void CaptureUnmappedFunction(string line)
    {
        var nidMatch = Regex.Match(
            line,
            @"\bnid\s*[=:]\s*([^\s,;\]\)]+)",
            RegexOptions.IgnoreCase);
        var functionMatch = Regex.Match(
            line,
            @"\b(?:function|func|import|export|name)\s*[=:]\s*['""]?([A-Za-z_][A-Za-z0-9_:+.\-]*)",
            RegexOptions.IgnoreCase);
        if (!functionMatch.Success)
        {
            functionMatch = Regex.Match(line, @"\b(sce[A-Z][A-Za-z0-9_]+)\b");
        }

        var function = functionMatch.Success ? functionMatch.Groups[1].Value : "";
        var nid = nidMatch.Success ? nidMatch.Groups[1].Value : "";
        if (string.IsNullOrEmpty(function) && string.IsNullOrEmpty(nid))
            return;

        var key = function + "|" + nid;
        if (!_unmappedFunctions.TryGetValue(key, out var record))
        {
            record = new UnmappedFunctionRecord
            {
                Function = function,
                Nid = nid,
                Count = 0,
                FirstEvidence = line
            };
            _unmappedFunctions[key] = record;
        }

        record.Count++;
    }

    private void CapturePaths(string line)
    {
        foreach (Match match in PathQuotedRegex.Matches(line))
            AddPath(match.Groups[1].Value, line);

        foreach (Match match in WindowsPathRegex.Matches(line))
        {
            var path = match.Groups[1].Value.TrimEnd(' ', '\t', ',', ';', ')', ']', '}');
            if (path.Length > 3 && path.Length < 1024)
                AddPath(path, line);
        }
    }

    private void AddPath(string path, string evidence)
    {
        if (!_fileAccesses.TryGetValue(path, out var record))
        {
            record = new FileAccessRecord
            {
                Path = path,
                Count = 0,
                FirstCategory = GuessPathCategory(path),
                FirstEvidence = evidence
            };
            _fileAccesses[path] = record;
        }
        record.Count++;
    }

    private void CaptureQueueMetrics(string line)
    {
        var cadence = Regex.Match(line, @"PRESENT_CADENCE[^\r\n]*\bhz=([0-9]+(?:[\.,][0-9]+)?)", RegexOptions.IgnoreCase);
        if (cadence.Success)
        {
            var value = AuditUtil.ParseDouble(cadence.Groups[1].Value);
            if (value > 0)
            {
                PresentCadences.Add(value);
                PresentCadenceLastHz = value;
            }
        }

        MaxGuestWorkPending = Math.Max(MaxGuestWorkPending, ExtractLong(line, @"guest_work_pending=(\d+)"));
        MaxSubmissionOvercommitPending = Math.Max(
            MaxSubmissionOvercommitPending,
            ExtractLong(line, @"SUBMISSION_OVERCOMMIT[^\r\n]*pending=(\d+)"));

        MaxSlowRenderWorkMs = Math.Max(
            MaxSlowRenderWorkMs,
            ExtractDouble(line, @"vk\.slow_render_work\s+([0-9]+(?:[\.,][0-9]+)?)ms"));

        MaxSlowWaitMs = Math.Max(
            MaxSlowWaitMs,
            ExtractDouble(line, @"SLOW_WAIT_PRODUCER[^\r\n]*waited_ms=([0-9]+(?:[\.,][0-9]+)?)"));

        if (line.Contains("COMPUTE_RESOURCE_PHASES", StringComparison.OrdinalIgnoreCase))
        {
            MaxComputeResourceTotalMs = Math.Max(MaxComputeResourceTotalMs, ExtractDouble(line, @"total_ms=([0-9]+(?:[\.,][0-9]+)?)"));
            MaxComputeStorageMs = Math.Max(MaxComputeStorageMs, ExtractDouble(line, @"storage_ms=([0-9]+(?:[\.,][0-9]+)?)"));
            MaxComputeTextureMs = Math.Max(MaxComputeTextureMs, ExtractDouble(line, @"texture_ms=([0-9]+(?:[\.,][0-9]+)?)"));
            MaxComputeBufferMs = Math.Max(MaxComputeBufferMs, ExtractDouble(line, @"buffer_ms=([0-9]+(?:[\.,][0-9]+)?)"));
            MaxComputeDescriptorMs = Math.Max(MaxComputeDescriptorMs, ExtractDouble(line, @"descriptor_ms=([0-9]+(?:[\.,][0-9]+)?)"));
            MaxComputePipelineMs = Math.Max(MaxComputePipelineMs, ExtractDouble(line, @"pipeline_ms=([0-9]+(?:[\.,][0-9]+)?)"));
        }
    }

    private static long ExtractLong(string line, string pattern)
    {
        var match = Regex.Match(line, pattern, RegexOptions.IgnoreCase);
        return match.Success ? AuditUtil.ParseLong(match.Groups[1].Value) : 0;
    }

    private static double ExtractDouble(string line, string pattern)
    {
        var match = Regex.Match(line, pattern, RegexOptions.IgnoreCase);
        return match.Success ? AuditUtil.ParseDouble(match.Groups[1].Value) : 0;
    }

    private static RuntimeEvent Event(DateTimeOffset timestamp, string stream, string category, string text)
        => new() { Timestamp = timestamp, Stream = stream, Category = category, Text = text };

    private void AddLimited(List<RuntimeEvent> list, RuntimeEvent item)
    {
        if (list.Count < _limit)
            list.Add(item);
    }

    private static bool IsStageLine(string lower)
    {
        return lower.Contains("loading:") ||
               lower.Contains("self") ||
               lower.Contains("elf") ||
               lower.Contains("sce dynamic") ||
               lower.Contains("scedynamic") ||
               lower.Contains("starting main loop") ||
               lower.Contains("resourcepool::") ||
               lower.Contains("startupscript") ||
               lower.Contains("app0_index") ||
               lower.Contains("apr_read") ||
               lower.Contains("presented guest frame");
    }

    private static bool IsVideoLine(string lower)
    {
        return lower.Contains(".bk2") ||
               lower.Contains(".bik") ||
               lower.Contains("bink") ||
               lower.Contains("nihav") ||
               lower.Contains("radplayer") ||
               lower.Contains("videoout") ||
               lower.Contains("movie") ||
               lower.Contains("playstation studio");
    }

    private static bool IsAudioLine(string lower)
    {
        return lower.Contains(".at9") ||
               lower.Contains(".wem") ||
               lower.Contains("atrac") ||
               lower.Contains("audioout") ||
               lower.Contains("ajm") ||
               lower.Contains("audio ");
    }

    private static bool IsQueueLine(string lower)
    {
        return lower.Contains("queue") ||
               lower.Contains("submission") ||
               lower.Contains("present_cadence") ||
               lower.Contains("slow_render_work") ||
               lower.Contains("slow_wait_producer") ||
               lower.Contains("compute_resource_phases") ||
               lower.Contains("capacity_backoff") ||
               lower.Contains("wait_reg_mem");
    }

    private static string GuessPathCategory(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        return ext switch
        {
            ".bk2" or ".bik" or ".mp4" or ".webm" => "video",
            ".at9" or ".wav" or ".wem" or ".ogg" or ".opus" or ".mp3" => "audio",
            ".spv" or ".shader" or ".pssl" => "shader",
            ".cmsh" => "mesh",
            _ => "file"
        };
    }
}

internal static class MemoryInfo
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);

    public static (ulong TotalBytes, ulong AvailableBytes) Get()
    {
        if (!OperatingSystem.IsWindows())
            return (0, 0);

        try
        {
            var status = new MemoryStatusEx
            {
                Length = (uint)Marshal.SizeOf<MemoryStatusEx>()
            };
            return GlobalMemoryStatusEx(ref status)
                ? (status.TotalPhysical, status.AvailablePhysical)
                : (0, 0);
        }
        catch
        {
            return (0, 0);
        }
    }
}
