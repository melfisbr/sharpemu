using System.Text;
using System.Text.Json;

namespace SharpEmu.RuntimeAudit;

internal sealed class ReportWriter
{
    private readonly string _output;

    public ReportWriter(string outputDirectory)
    {
        _output = outputDirectory;
    }

    public void FinalizeReport(AuditReport report)
    {
        UpdateApiRuntimeCounts(report);
        BuildFindings(report);
        WriteCsvArtifacts(report);
        WriteEventArtifacts(report);
        WriteCorrectionInputs(report);
        WriteSummaryMarkdown(report);

        var jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true
        };
        File.WriteAllText(
            Path.Combine(_output, "consolidated_audit.json"),
            JsonSerializer.Serialize(report, jsonOptions),
            new System.Text.UTF8Encoding(true));
    }

    private static void UpdateApiRuntimeCounts(AuditReport report)
    {
        var runtime = report.Runtime.ApiEvents.Select(x => x.Text).ToList();

        foreach (var api in report.Source.ApiIntegrations)
        {
            string[] keywords = api.Api switch
            {
                "Vulkan" => ["vulkan", "vk."],
                "SDL" => ["sdl"],
                "Bink" => ["bink", ".bk2", "nihav"],
                "Audio/AJM" => ["ajm", "audioout", "atrac", ".at9"],
                "AMPR" => ["ampr", "apr_read"],
                "AGC" => ["agc", "pm4"],
                "VideoOut" => ["videoout"],
                "SceDynamic" => ["scedynamic", "relocation"],
                "Kernel/Pthread" => ["pthread", "directmemory", "kernelmemory"],
                "PlayGo" => ["playgo"],
                "NP" => ["scenp"],
                "SaveData" => ["savedata"],
                _ => [api.Api]
            };

            api.RuntimeLineHits = runtime.Count(line =>
                keywords.Any(k => line.Contains(k, StringComparison.OrdinalIgnoreCase)));
        }
    }

    private static void BuildFindings(AuditReport report)
    {
        var s = report.Runtime.Summary;

        if (report.Runtime.ExitCode != 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "process",
                Code = "PROCESS_NONZERO_EXIT",
                Message = $"SharpEmu exited with code {report.Runtime.ExitCode}.",
                Evidence = report.Runtime.StageEvents.TakeLast(10).Select(x => x.Text).ToList()
            });
        }

        if (s.HeapCorruptionHits > 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "critical",
                Category = "memory",
                Code = "NATIVE_HEAP_CORRUPTION",
                Message = $"Native heap corruption markers observed: {s.HeapCorruptionHits}.",
                Evidence = FindEvidence(report, "HEAP_CORRUPTION", "0xC0000374")
            });
        }

        if (s.AccessViolationHits > 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "critical",
                Category = "memory",
                Code = "ACCESS_VIOLATION",
                Message = $"Access violation markers observed: {s.AccessViolationHits}.",
                Evidence = FindEvidence(report, "ACCESS_VIOLATION", "0xC0000005")
            });
        }

        if (s.DeviceLostHits > 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "gpu",
                Code = "VULKAN_DEVICE_LOST",
                Message = $"Vulkan device-lost markers observed: {s.DeviceLostHits}.",
                Evidence = FindEvidence(report, "DEVICE_LOST", "VK_ERROR_DEVICE_LOST")
            });
        }

        if (s.PresentCadenceLastHz > 0 && s.PresentCadenceLastHz < 1.0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "presentation",
                Code = "VERY_LOW_PRESENT_CADENCE",
                Message = $"Last measured guest presentation cadence is {s.PresentCadenceLastHz:F3} Hz.",
                Evidence = report.Runtime.QueueEvents
                    .Where(x => x.Text.Contains("PRESENT_CADENCE", StringComparison.OrdinalIgnoreCase))
                    .TakeLast(8)
                    .Select(x => x.Text)
                    .ToList()
            });
        }

        if (s.MaxGuestWorkPending >= 100)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "gpu_queue",
                Code = "GUEST_WORK_BACKLOG",
                Message = $"Guest GPU work backlog reached {s.MaxGuestWorkPending} queued items.",
                Evidence = report.Runtime.QueueEvents
                    .Where(x => x.Text.Contains("guest_work_pending=", StringComparison.OrdinalIgnoreCase))
                    .TakeLast(8)
                    .Select(x => x.Text)
                    .ToList()
            });
        }

        if (s.MaxSlowRenderWorkMs >= 500)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "gpu_queue",
                Code = "SLOW_RENDER_WORK",
                Message = $"Slow render work reached {s.MaxSlowRenderWorkMs:F1} ms.",
                Evidence = report.Runtime.QueueEvents
                    .Where(x => x.Text.Contains("slow_render_work", StringComparison.OrdinalIgnoreCase))
                    .OrderByDescending(x => ExtractMs(x.Text, "slow_render_work"))
                    .Take(10)
                    .Select(x => x.Text)
                    .ToList()
            });
        }

        if (s.MaxSlowWaitMs >= 500)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "synchronization",
                Code = "SLOW_WAIT",
                Message = $"Guest/producer waits reached {s.MaxSlowWaitMs:F1} ms.",
                Evidence = report.Runtime.QueueEvents
                    .Where(x => x.Text.Contains("SLOW_WAIT_PRODUCER", StringComparison.OrdinalIgnoreCase))
                    .TakeLast(10)
                    .Select(x => x.Text)
                    .ToList()
            });
        }

        var computePhases = new Dictionary<string, double>
        {
            ["storage"] = s.MaxComputeStorageMs,
            ["texture"] = s.MaxComputeTextureMs,
            ["buffer"] = s.MaxComputeBufferMs,
            ["descriptor"] = s.MaxComputeDescriptorMs,
            ["pipeline"] = s.MaxComputePipelineMs
        };
        var worstPhase = computePhases.OrderByDescending(x => x.Value).First();
        if (worstPhase.Value >= 100)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "error",
                Category = "compute",
                Code = "COMPUTE_RESOURCE_PHASE",
                Message = $"Largest compute setup phase is {worstPhase.Key}: {worstPhase.Value:F1} ms.",
                Evidence = report.Runtime.QueueEvents
                    .Where(x => x.Text.Contains("COMPUTE_RESOURCE_PHASES", StringComparison.OrdinalIgnoreCase))
                    .TakeLast(10)
                    .Select(x => x.Text)
                    .ToList()
            });
        }

        if (report.Runtime.UnmappedEvents.Count > 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "warning",
                Category = "hle",
                Code = "RUNTIME_UNMAPPED",
                Message = $"{report.Runtime.UnmappedEvents.Count} runtime lines indicate unmapped/unsupported functionality.",
                Evidence = report.Runtime.UnmappedEvents.Take(20).Select(x => x.Text).ToList()
            });
        }

        if (report.Source.PotentialGaps.Count > 0)
        {
            var notImplemented = report.Source.PotentialGaps.Count(x =>
                x.Kind is "NotImplementedException" or "Unimplemented" or "NotMapped");
            report.Findings.Add(new AuditFinding
            {
                Severity = notImplemented > 0 ? "warning" : "info",
                Category = "source",
                Code = "SOURCE_GAPS",
                Message = $"Source scan found {report.Source.PotentialGaps.Count} potential gap markers; {notImplemented} are strong not-implemented/unmapped markers.",
                Evidence = report.Source.PotentialGaps.Take(20)
                    .Select(x => $"{x.SourceFile}:{x.Line}: {x.Text}")
                    .ToList()
            });
        }

        if (report.Runtime.VideoEvents.Count == 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "warning",
                Category = "video",
                Code = "NO_VIDEO_RUNTIME_EVIDENCE",
                Message = "No video/Bink/VideoOut runtime event was detected in the captured logs."
            });
        }

        if (report.Runtime.AudioEvents.Count == 0)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "warning",
                Category = "audio",
                Code = "NO_AUDIO_RUNTIME_EVIDENCE",
                Message = "No AJM/ATRAC/AudioOut runtime event was detected in the captured logs."
            });
        }

        if (report.Host.TotalPhysicalMemoryBytes > 0 &&
            s.MaxWorkingSetMb * 1048576.0 > report.Host.TotalPhysicalMemoryBytes * 0.75)
        {
            report.Findings.Add(new AuditFinding
            {
                Severity = "warning",
                Category = "memory",
                Code = "HIGH_PROCESS_RAM",
                Message = $"SharpEmu working set reached {s.MaxWorkingSetMb:F0} MB, over 75% of physical RAM."
            });
        }

        report.Findings = report.Findings
            .OrderBy(x => SeverityOrder(x.Severity))
            .ThenBy(x => x.Category, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static int SeverityOrder(string severity) => severity.ToLowerInvariant() switch
    {
        "critical" => 0,
        "error" => 1,
        "warning" => 2,
        _ => 3
    };

    private static List<string> FindEvidence(AuditReport report, params string[] terms)
    {
        return report.Runtime.StageEvents
            .Concat(report.Runtime.QueueEvents)
            .Concat(report.Runtime.UnmappedEvents)
            .Where(e => terms.Any(t => e.Text.Contains(t, StringComparison.OrdinalIgnoreCase)))
            .Take(20)
            .Select(e => e.Text)
            .Distinct()
            .ToList();
    }

    private static double ExtractMs(string text, string marker)
    {
        var index = text.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (index < 0)
            return 0;
        var tail = text[index..];
        var match = System.Text.RegularExpressions.Regex.Match(
            tail,
            @"([0-9]+(?:[\.,][0-9]+)?)ms");
        return match.Success ? AuditUtil.ParseDouble(match.Groups[1].Value) : 0;
    }

    private void WriteCsvArtifacts(AuditReport report)
    {
        WriteCsv(
            "runtime_parameters.csv",
            ["name", "child_value", "source_file", "line", "context"],
            report.Source.RuntimeParameters.Select(x =>
                new[] { x.Name, x.ChildValue, x.SourceFile, x.Line.ToString(), x.Context }));

        WriteCsv(
            "source_potential_gaps.csv",
            ["kind", "source_file", "line", "text"],
            report.Source.PotentialGaps.Select(x =>
                new[] { x.Kind, x.SourceFile, x.Line.ToString(), x.Text }));

        WriteCsv(
            "native_api_integrations.csv",
            ["kind", "library", "source_file", "line"],
            report.Source.NativeIntegrations.Select(x =>
                new[] { x.Kind, x.Library, x.SourceFile, x.Line.ToString() }));

        WriteCsv(
            "managed_dependencies.csv",
            ["project", "package", "version"],
            report.Source.ManagedDependencies.Select(x =>
                new[] { x.Project, x.Package, x.Version }));

        WriteCsv(
            "api_integration_summary.csv",
            ["api", "source_file_hits", "runtime_line_hits", "representative_files"],
            report.Source.ApiIntegrations.Select(x =>
                new[]
                {
                    x.Api,
                    x.SourceFileHits.ToString(),
                    x.RuntimeLineHits.ToString(),
                    string.Join(" | ", x.RepresentativeFiles)
                }));

        WriteCsv(
            "source_hashes.csv",
            ["path", "sha256", "size_bytes"],
            report.Source.SourceHashes.Select(x =>
                new[] { x.Path, x.Sha256, x.SizeBytes.ToString() }));

        WriteCsv(
            "game_extensions.csv",
            ["extension", "count", "bytes"],
            report.Game.Extensions.Select(x =>
                new[] { x.Extension, x.Count.ToString(), x.Bytes.ToString() }));

        WriteCsv(
            "game_media_files.csv",
            ["relative_path", "size_bytes", "readable", "header_hex"],
            report.Game.MediaFiles.Select(x =>
                new[] { x.RelativePath, x.SizeBytes.ToString(), x.Readable ? "1" : "0", x.HeaderHex }));

        WriteCsv(
            "game_largest_files.csv",
            ["relative_path", "size_bytes"],
            report.Game.LargestFiles.Select(x =>
                new[] { x.RelativePath, x.SizeBytes.ToString() }));

        WriteCsv(
            "runtime_unmapped_functions.csv",
            ["function", "nid", "count", "first_evidence"],
            report.Runtime.UnmappedFunctions.Select(x =>
                new[] { x.Function, x.Nid, x.Count.ToString(), x.FirstEvidence }));

        WriteCsv(
            "runtime_file_accesses.csv",
            ["path", "count", "category", "first_evidence"],
            report.Runtime.FileAccesses.Select(x =>
                new[] { x.Path, x.Count.ToString(), x.FirstCategory, x.FirstEvidence }));
    }

    private void WriteEventArtifacts(AuditReport report)
    {
        WriteEvents("runtime_stages.log", report.Runtime.StageEvents);
        WriteEvents("video_timeline.log", report.Runtime.VideoEvents);
        WriteEvents("audio_timeline.log", report.Runtime.AudioEvents);
        WriteEvents("queue_timeline.log", report.Runtime.QueueEvents);
        WriteEvents("runtime_unmapped.log", report.Runtime.UnmappedEvents);
        WriteEvents("runtime_api.log", report.Runtime.ApiEvents);
    }

    private void WriteCorrectionInputs(AuditReport report)
    {
        var payload = new
        {
            schema = "SharpEmu.CorrectionInputs/1",
            generated_at = DateTimeOffset.Now,
            eboot = new
            {
                path = report.EbootPath,
                sha256 = report.Eboot.Sha256,
                size_bytes = report.Eboot.SizeBytes,
                libraries = report.Eboot.Libraries.Take(200).ToArray(),
                modules = report.Eboot.Modules.Take(200).ToArray()
            },
            runtime = new
            {
                exit_code = report.Runtime.ExitCode,
                wall_seconds = report.Runtime.WallSeconds,
                summary = report.Runtime.Summary
            },
            highest_priority_findings = report.Findings.Take(30).ToArray(),
            runtime_unmapped = report.Runtime.UnmappedEvents.Take(200).ToArray(),
            runtime_unmapped_functions = report.Runtime.UnmappedFunctions.Take(500).ToArray(),
            queue_evidence = report.Runtime.QueueEvents
                .Where(x =>
                    x.Text.Contains("PRESENT_CADENCE", StringComparison.OrdinalIgnoreCase) ||
                    x.Text.Contains("slow_render_work", StringComparison.OrdinalIgnoreCase) ||
                    x.Text.Contains("SLOW_WAIT_PRODUCER", StringComparison.OrdinalIgnoreCase) ||
                    x.Text.Contains("COMPUTE_RESOURCE_PHASES", StringComparison.OrdinalIgnoreCase) ||
                    x.Text.Contains("SUBMISSION_OVERCOMMIT", StringComparison.OrdinalIgnoreCase))
                .TakeLast(300)
                .ToArray(),
            video_evidence = report.Runtime.VideoEvents.Take(200).ToArray(),
            audio_evidence = report.Runtime.AudioEvents.Take(200).ToArray(),
            source_gaps = report.Source.PotentialGaps
                .Where(x => x.Kind is "NotImplementedException" or "Unimplemented" or "NotMapped" or "Unsupported")
                .Take(500)
                .ToArray(),
            source_snapshot_files = report.Source.SnapshotFiles,
            key_source_hashes = report.Repository.KeySourceHashes,
            runtime_parameters = report.Source.RuntimeParameters
                .GroupBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .Select(g => new
                {
                    name = g.Key,
                    child_value = g.First().ChildValue,
                    definitions = g.Take(10).ToArray()
                })
                .Take(1000)
                .ToArray()
        };

        File.WriteAllText(
            Path.Combine(_output, "correction_inputs.json"),
            JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }),
            new System.Text.UTF8Encoding(true));
    }

    private void WriteSummaryMarkdown(AuditReport report)
    {
        var s = report.Runtime.Summary;
        var sb = new StringBuilder();

        sb.AppendLine("# SharpEmu Full Runtime Audit");
        sb.AppendLine();
        sb.AppendLine($"Generated: `{report.FinishedAt:O}`");
        sb.AppendLine($"EBOOT: `{report.EbootPath}`");
        sb.AppendLine($"SHA256: `{report.Eboot.Sha256}`");
        sb.AppendLine($"Emulator: `{report.EmulatorPath}`");
        sb.AppendLine();

        sb.AppendLine("## Execution");
        sb.AppendLine();
        sb.AppendLine($"- Exit code: **{report.Runtime.ExitCode}**");
        sb.AppendLine($"- Wall time: **{report.Runtime.WallSeconds:F2} s**");
        sb.AppendLine($"- Stdout/stderr lines: **{report.Runtime.StdoutLines:N0} / {report.Runtime.StderrLines:N0}**");
        sb.AppendLine($"- Heap corruption / access violation / device lost: **{s.HeapCorruptionHits} / {s.AccessViolationHits} / {s.DeviceLostHits}**");
        sb.AppendLine();

        sb.AppendLine("## CPU / RAM / GPU");
        sb.AppendLine();
        sb.AppendLine($"- CPU avg/max: **{s.AvgCpuPercent:F1}% / {s.MaxCpuPercent:F1}%**");
        sb.AppendLine($"- Working set max: **{s.MaxWorkingSetMb:F0} MB**");
        sb.AppendLine($"- Private memory max: **{s.MaxPrivateMemoryMb:F0} MB**");
        sb.AppendLine($"- System RAM minimum available: **{s.MinAvailableSystemMemoryMb:F0} MB**");
        sb.AppendLine($"- GPU utilization max: **{s.MaxGpuUtilizationPercent:F1}%**");
        sb.AppendLine($"- GPU memory used max: **{s.MaxGpuMemoryUsedMb:F0} MB**");
        sb.AppendLine();

        sb.AppendLine("## Renderer / queues");
        sb.AppendLine();
        sb.AppendLine($"- Present cadence avg/last: **{s.PresentCadenceAverageHz:F3} / {s.PresentCadenceLastHz:F3} Hz**");
        sb.AppendLine($"- Guest work pending max: **{s.MaxGuestWorkPending}**");
        sb.AppendLine($"- Submission overcommit max: **{s.MaxSubmissionOvercommitPending}**");
        sb.AppendLine($"- Slow render max: **{s.MaxSlowRenderWorkMs:F1} ms**");
        sb.AppendLine($"- Slow wait max: **{s.MaxSlowWaitMs:F1} ms**");
        sb.AppendLine($"- Compute setup max: **{s.MaxComputeResourceTotalMs:F1} ms**");
        sb.AppendLine($"  - storage: {s.MaxComputeStorageMs:F1} ms");
        sb.AppendLine($"  - texture: {s.MaxComputeTextureMs:F1} ms");
        sb.AppendLine($"  - buffer: {s.MaxComputeBufferMs:F1} ms");
        sb.AppendLine($"  - descriptor: {s.MaxComputeDescriptorMs:F1} ms");
        sb.AppendLine($"  - pipeline: {s.MaxComputePipelineMs:F1} ms");
        sb.AppendLine();

        sb.AppendLine("## Loader / media / APIs");
        sb.AppendLine();
        sb.AppendLine($"- Game files: **{report.Game.FileCount:N0}** ({AuditUtil.FormatBytes(report.Game.TotalBytes)})");
        sb.AppendLine($"- Runtime unique file paths observed: **{s.UniqueFileAccessCount:N0}**");
        sb.AppendLine($"- Video events: **{s.VideoEventCount:N0}**");
        sb.AppendLine($"- Audio events: **{s.AudioEventCount:N0}**");
        sb.AppendLine($"- Runtime unmapped/unsupported events: **{s.UnmappedRuntimeCount:N0}**");
        sb.AppendLine($"- Source runtime parameters inventoried: **{report.Source.RuntimeParameters.Select(x => x.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count():N0}**");
        sb.AppendLine($"- Source potential gap markers: **{report.Source.PotentialGaps.Count:N0}**");
        sb.AppendLine();

        sb.AppendLine("## Highest-priority findings");
        sb.AppendLine();
        if (report.Findings.Count == 0)
        {
            sb.AppendLine("No high-priority findings were generated.");
        }
        else
        {
            foreach (var finding in report.Findings.Take(30))
            {
                sb.AppendLine($"- **[{finding.Severity.ToUpperInvariant()}] {finding.Code}** — {finding.Message}");
            }
        }
        sb.AppendLine();

        sb.AppendLine("## Files intended for correction generation");
        sb.AppendLine();
        sb.AppendLine("- `consolidated_audit.json` — complete machine-readable audit");
        sb.AppendLine("- `correction_inputs.json` — compact evidence for the next code correction");
        sb.AppendLine("- `runtime_unmapped.log` / `runtime_unmapped_functions.csv` — unmapped/unsupported runtime calls and NIDs");
        sb.AppendLine("- `queue_timeline.log` — queue, waits, cadence, compute phases");
        sb.AppendLine("- `video_timeline.log` / `audio_timeline.log` — media sequence");
        sb.AppendLine("- `process_metrics.csv` / `gpu_metrics.csv` — CPU/RAM/GPU time series");
        sb.AppendLine("- `runtime_parameters.csv` — every SHARPEMU/environment parameter found in source");
        sb.AppendLine("- `source_potential_gaps.csv` — TODO/stub/not-implemented inventory");
        sb.AppendLine("- `native_api_integrations.csv` / `managed_dependencies.csv` — external API integration inventory");
        sb.AppendLine("- `source_snapshot/` — key current source files for patch generation");

        File.WriteAllText(
            Path.Combine(_output, "AUDIT_SUMMARY.md"),
            sb.ToString(),
            new System.Text.UTF8Encoding(true));
    }

    private void WriteCsv(string fileName, string[] header, IEnumerable<string[]> rows)
    {
        using var writer = new StreamWriter(
            Path.Combine(_output, fileName),
            false,
            new System.Text.UTF8Encoding(true));
        writer.WriteLine(string.Join(",", header.Select(AuditUtil.Csv)));
        foreach (var row in rows)
            writer.WriteLine(string.Join(",", row.Select(AuditUtil.Csv)));
    }

    private void WriteEvents(string fileName, IEnumerable<RuntimeEvent> events)
    {
        using var writer = new StreamWriter(
            Path.Combine(_output, fileName),
            false,
            new System.Text.UTF8Encoding(true));
        foreach (var item in events)
            writer.WriteLine($"{item.Timestamp:O}\t{item.Stream}\t{item.Category}\t{item.Text}");
    }
}
