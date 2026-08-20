using System.Text;
using System.Text.Json;

namespace SharpEmu.RuntimeAudit;

internal static class AuditHistoryManager
{
    private sealed class MetricDelta
    {
        public string Metric { get; set; } = "";
        public double Previous { get; set; }
        public double Current { get; set; }
        public double Delta { get; set; }
        public double DeltaPercent { get; set; }
        public string Direction { get; set; } = "";
        public string Verdict { get; set; } = "unchanged";
    }

    private sealed class HistoryEntry
    {
        public string ResultDirectory { get; set; } = "";
        public string Timestamp { get; set; } = "";
        public string EbootSha256 { get; set; } = "";
        public int ExitCode { get; set; }
        public double PresentLastHz { get; set; }
        public long GuestWorkPendingMax { get; set; }
        public double SlowRenderMaxMs { get; set; }
        public double SlowWaitMaxMs { get; set; }
        public double WorkingSetMaxMb { get; set; }
        public int UnmappedRuntimeCount { get; set; }
        public int HeapCorruptionHits { get; set; }
        public string ComparisonVerdict { get; set; } = "baseline";
    }

    public static void Update(
        string historyRoot,
        string currentOutputDirectory,
        AuditReport current)
    {
        Directory.CreateDirectory(historyRoot);

        var previousDirectory = Directory
            .EnumerateDirectories(historyRoot, "SharpEmu_RuntimeAudit_Result_*", SearchOption.TopDirectoryOnly)
            .Where(path => !Path.GetFullPath(path).Equals(
                Path.GetFullPath(currentOutputDirectory),
                StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .FirstOrDefault(path => File.Exists(Path.Combine(path, "consolidated_audit.json")));

        var verdict = "baseline";
        if (!string.IsNullOrWhiteSpace(previousDirectory))
        {
            try
            {
                var previousJson = File.ReadAllText(Path.Combine(previousDirectory, "consolidated_audit.json"));
                var previous = JsonSerializer.Deserialize<AuditReport>(
                    previousJson,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (previous is not null)
                    verdict = WriteComparison(currentOutputDirectory, previousDirectory, previous, current);
            }
            catch (Exception ex)
            {
                File.WriteAllText(
                    Path.Combine(currentOutputDirectory, "comparison_error.txt"),
                    ex.ToString(),
                    new UTF8Encoding(true));
                verdict = "comparison-error";
            }
        }
        else
        {
            File.WriteAllText(
                Path.Combine(currentOutputDirectory, "COMPARISON_PREVIOUS.md"),
                "# RuntimeAudit comparison\n\nThis is the first stored run for this game. It becomes the comparison baseline.\n",
                new UTF8Encoding(true));
        }

        UpdateHistoryIndex(historyRoot, currentOutputDirectory, current, verdict);
    }

    private static string WriteComparison(
        string currentOutputDirectory,
        string previousDirectory,
        AuditReport previous,
        AuditReport current)
    {
        var p = previous.Runtime.Summary;
        var c = current.Runtime.Summary;

        var metrics = new List<MetricDelta>
        {
            Metric("Present cadence last (Hz)", p.PresentCadenceLastHz, c.PresentCadenceLastHz, "higher"),
            Metric("Present cadence average (Hz)", p.PresentCadenceAverageHz, c.PresentCadenceAverageHz, "higher"),
            Metric("Guest work pending max", p.MaxGuestWorkPending, c.MaxGuestWorkPending, "lower"),
            Metric("Submission overcommit max", p.MaxSubmissionOvercommitPending, c.MaxSubmissionOvercommitPending, "lower"),
            Metric("Slow render max (ms)", p.MaxSlowRenderWorkMs, c.MaxSlowRenderWorkMs, "lower"),
            Metric("Slow wait max (ms)", p.MaxSlowWaitMs, c.MaxSlowWaitMs, "lower"),
            Metric("Compute total max (ms)", p.MaxComputeResourceTotalMs, c.MaxComputeResourceTotalMs, "lower"),
            Metric("Compute storage max (ms)", p.MaxComputeStorageMs, c.MaxComputeStorageMs, "lower"),
            Metric("Compute texture max (ms)", p.MaxComputeTextureMs, c.MaxComputeTextureMs, "lower"),
            Metric("Compute buffer max (ms)", p.MaxComputeBufferMs, c.MaxComputeBufferMs, "lower"),
            Metric("Compute descriptor max (ms)", p.MaxComputeDescriptorMs, c.MaxComputeDescriptorMs, "lower"),
            Metric("Compute pipeline max (ms)", p.MaxComputePipelineMs, c.MaxComputePipelineMs, "lower"),
            Metric("Working set max (MB)", p.MaxWorkingSetMb, c.MaxWorkingSetMb, "lower"),
            Metric("Private memory max (MB)", p.MaxPrivateMemoryMb, c.MaxPrivateMemoryMb, "lower"),
            Metric("Unmapped runtime count", p.UnmappedRuntimeCount, c.UnmappedRuntimeCount, "lower"),
            Metric("Heap corruption hits", p.HeapCorruptionHits, c.HeapCorruptionHits, "lower"),
            Metric("Access violation hits", p.AccessViolationHits, c.AccessViolationHits, "lower"),
            Metric("Device lost hits", p.DeviceLostHits, c.DeviceLostHits, "lower")
        };

        var previousExitGood = previous.Runtime.ExitCode == 0;
        var currentExitGood = current.Runtime.ExitCode == 0;

        var improved = metrics.Count(x => x.Verdict == "improved");
        var regressed = metrics.Count(x => x.Verdict == "regressed");

        string overall;
        if (!previousExitGood && currentExitGood)
            overall = "improved";
        else if (previousExitGood && !currentExitGood)
            overall = "regressed";
        else if (regressed == 0 && improved > 0)
            overall = "improved";
        else if (improved == 0 && regressed > 0)
            overall = "regressed";
        else if (improved > regressed * 2)
            overall = "improved";
        else if (regressed > improved * 2)
            overall = "regressed";
        else
            overall = "mixed";

        var comparison = new
        {
            schema = "SharpEmu.RuntimeAuditComparison/1",
            previous_result = previousDirectory,
            current_result = currentOutputDirectory,
            previous_eboot_sha256 = previous.Eboot.Sha256,
            current_eboot_sha256 = current.Eboot.Sha256,
            previous_exit_code = previous.Runtime.ExitCode,
            current_exit_code = current.Runtime.ExitCode,
            improved_metrics = improved,
            regressed_metrics = regressed,
            overall,
            metrics
        };

        File.WriteAllText(
            Path.Combine(currentOutputDirectory, "comparison_previous.json"),
            JsonSerializer.Serialize(comparison, new JsonSerializerOptions { WriteIndented = true }),
            new UTF8Encoding(true));

        var sb = new StringBuilder();
        sb.AppendLine("# RuntimeAudit comparison with previous run");
        sb.AppendLine();
        sb.AppendLine($"Overall verdict: **{overall.ToUpperInvariant()}**");
        sb.AppendLine();
        sb.AppendLine($"Previous: `{previousDirectory}`");
        sb.AppendLine($"Current: `{currentOutputDirectory}`");
        sb.AppendLine();
        sb.AppendLine($"Exit code: **{previous.Runtime.ExitCode} -> {current.Runtime.ExitCode}**");
        sb.AppendLine();
        sb.AppendLine("| Metric | Previous | Current | Delta | Verdict |");
        sb.AppendLine("|---|---:|---:|---:|---|");
        foreach (var metric in metrics)
        {
            sb.AppendLine(
                $"| {metric.Metric} | {metric.Previous:F3} | {metric.Current:F3} | {metric.Delta:+0.###;-0.###;0} ({metric.DeltaPercent:+0.0;-0.0;0.0}%) | {metric.Verdict} |");
        }

        sb.AppendLine();
        sb.AppendLine($"Improved metrics: **{improved}**");
        sb.AppendLine($"Regressed metrics: **{regressed}**");

        File.WriteAllText(
            Path.Combine(currentOutputDirectory, "COMPARISON_PREVIOUS.md"),
            sb.ToString(),
            new UTF8Encoding(true));

        return overall;
    }

    private static MetricDelta Metric(string name, double previous, double current, string direction)
    {
        var delta = current - previous;
        var denominator = Math.Abs(previous) < 0.000001 ? Math.Max(Math.Abs(current), 1.0) : Math.Abs(previous);
        var pct = delta / denominator * 100.0;

        var tolerance = Math.Max(0.001, Math.Abs(previous) * 0.03);
        string verdict;
        if (Math.Abs(delta) <= tolerance)
        {
            verdict = "unchanged";
        }
        else
        {
            var better = direction == "higher" ? delta > 0 : delta < 0;
            verdict = better ? "improved" : "regressed";
        }

        return new MetricDelta
        {
            Metric = name,
            Previous = previous,
            Current = current,
            Delta = delta,
            DeltaPercent = pct,
            Direction = direction,
            Verdict = verdict
        };
    }

    private static void UpdateHistoryIndex(
        string historyRoot,
        string currentOutputDirectory,
        AuditReport current,
        string comparisonVerdict)
    {
        var indexPath = Path.Combine(historyRoot, "history_index.json");
        var entries = new List<HistoryEntry>();

        if (File.Exists(indexPath))
        {
            try
            {
                entries = JsonSerializer.Deserialize<List<HistoryEntry>>(
                              File.ReadAllText(indexPath),
                              new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                          ?? [];
            }
            catch
            {
                entries = [];
            }
        }

        entries.RemoveAll(x =>
            Path.GetFullPath(x.ResultDirectory).Equals(
                Path.GetFullPath(currentOutputDirectory),
                StringComparison.OrdinalIgnoreCase));

        entries.Add(new HistoryEntry
        {
            ResultDirectory = currentOutputDirectory,
            Timestamp = current.FinishedAt.ToString("O"),
            EbootSha256 = current.Eboot.Sha256,
            ExitCode = current.Runtime.ExitCode,
            PresentLastHz = current.Runtime.Summary.PresentCadenceLastHz,
            GuestWorkPendingMax = current.Runtime.Summary.MaxGuestWorkPending,
            SlowRenderMaxMs = current.Runtime.Summary.MaxSlowRenderWorkMs,
            SlowWaitMaxMs = current.Runtime.Summary.MaxSlowWaitMs,
            WorkingSetMaxMb = current.Runtime.Summary.MaxWorkingSetMb,
            UnmappedRuntimeCount = current.Runtime.Summary.UnmappedRuntimeCount,
            HeapCorruptionHits = current.Runtime.Summary.HeapCorruptionHits,
            ComparisonVerdict = comparisonVerdict
        });

        entries = entries
            .OrderBy(x => x.Timestamp, StringComparer.Ordinal)
            .ToList();

        File.WriteAllText(
            indexPath,
            JsonSerializer.Serialize(entries, new JsonSerializerOptions { WriteIndented = true }),
            new UTF8Encoding(true));
    }
}
