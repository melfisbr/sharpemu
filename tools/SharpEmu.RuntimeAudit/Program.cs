using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace SharpEmu.RuntimeAudit;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        try
        {
            var options = ParseOptions(args);
            var repo = Path.GetFullPath(options.RepositoryRoot);
            var eboot = Path.GetFullPath(options.EbootPath);
            var gameRoot = Path.GetFullPath(options.GameRoot ?? Path.GetDirectoryName(eboot)!);

            if (!Directory.Exists(repo))
                throw new DirectoryNotFoundException($"Repository root not found: {repo}");
            if (!File.Exists(eboot))
                throw new FileNotFoundException("EBOOT not found.", eboot);

            var emulator = ResolveEmulator(repo, options.EmulatorPath);
            var configPath = ResolveConfig(repo, options.ConfigPath);
            var config = LoadConfig(configPath);

            var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var outputRoot = Path.GetFullPath(options.OutputRoot ?? repo);
            var output = Path.Combine(outputRoot, $"SharpEmu_RuntimeAudit_Result_{timestamp}");
            Directory.CreateDirectory(output);

            Console.WriteLine("============================================================");
            Console.WriteLine("[SharpEmu RuntimeAudit V1.1]");
            Console.WriteLine($"Repo    : {repo}");
            Console.WriteLine($"EBOOT   : {eboot}");
            Console.WriteLine($"GameRoot: {gameRoot}");
            Console.WriteLine($"Emulator: {emulator}");
            Console.WriteLine($"Output  : {output}");
            Console.WriteLine("============================================================");
            Console.WriteLine();

            var memory = MemoryInfo.Get();
            var report = new AuditReport
            {
                StartedAt = DateTimeOffset.Now,
                RepositoryRoot = repo,
                EbootPath = eboot,
                GameRoot = gameRoot,
                EmulatorPath = emulator,
                OutputDirectory = output,
                Host = new HostInfo
                {
                    MachineName = Environment.MachineName,
                    OSDescription = RuntimeInformation.OSDescription,
                    OSArchitecture = RuntimeInformation.OSArchitecture.ToString(),
                    ProcessArchitecture = RuntimeInformation.ProcessArchitecture.ToString(),
                    ProcessorCount = Environment.ProcessorCount,
                    TotalPhysicalMemoryBytes = memory.TotalBytes
                }
            };

            File.Copy(configPath, Path.Combine(output, "audit_profile_used.json"), true);

            Console.WriteLine("[1/4] Static source, EBOOT, game-content and API audit...");
            var staticAuditor = new StaticAuditor(repo, gameRoot, eboot, output, config);
            await staticAuditor.CollectAsync(report);
            Console.WriteLine($"      Source files scanned : {report.Source.SourceFileCount:N0}");
            Console.WriteLine($"      Runtime parameters   : {report.Source.RuntimeParameters.Select(x => x.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count():N0}");
            Console.WriteLine($"      Game files inventoried: {report.Game.FileCount:N0}");
            Console.WriteLine();

            Console.WriteLine("[2/4] Launching SharpEmu with safe full-audit telemetry...");
            Console.WriteLine("      Use the emulator normally. Close the SharpEmu window when the");
            Console.WriteLine("      behavior you want audited has been reproduced.");
            Console.WriteLine();

            var runtimeMonitor = new RuntimeMonitor(repo, eboot, emulator, output, config);
            await runtimeMonitor.RunAsync(report);

            Console.WriteLine();
            Console.WriteLine("[3/4] Consolidating runtime, media, queue, RAM, API and unmapped evidence...");
            report.FinishedAt = DateTimeOffset.Now;
            var reportWriter = new ReportWriter(output);
            reportWriter.FinalizeReport(report);

            AuditHistoryManager.Update(outputRoot, output, report);

            File.WriteAllText(
                Path.Combine(output, "AUDIT_READY.txt"),
                $"SharpEmu RuntimeAudit V1.1{Environment.NewLine}" +
                $"PRIMARY=consolidated_audit.json{Environment.NewLine}" +
                $"CORRECTION_INPUT=correction_inputs.json{Environment.NewLine}" +
                $"SUMMARY=AUDIT_SUMMARY.md{Environment.NewLine}" +
                $"NOTE=ZIP SHA256 is printed by the tool after bundle creation.{Environment.NewLine}");

            WriteManifest(output);

            Console.WriteLine("[4/4] Creating audit bundle...");
            var zip = output + ".zip";
            if (File.Exists(zip))
                File.Delete(zip);
            ZipFile.CreateFromDirectory(
                output,
                zip,
                CompressionLevel.Optimal,
                includeBaseDirectory: true);

            var zipHash = AuditUtil.Sha256File(zip);

            Console.WriteLine();
            Console.WriteLine("============================================================");
            Console.WriteLine("[RuntimeAudit] COMPLETED");
            Console.WriteLine($"Exit code       : {report.Runtime.ExitCode}");
            Console.WriteLine($"Wall seconds    : {report.Runtime.WallSeconds:F2}");
            Console.WriteLine($"Present last Hz : {report.Runtime.Summary.PresentCadenceLastHz:F3}");
            Console.WriteLine($"RAM max MB      : {report.Runtime.Summary.MaxWorkingSetMb:F0}");
            Console.WriteLine($"Unmapped runtime: {report.Runtime.Summary.UnmappedRuntimeCount}");
            Console.WriteLine($"Findings        : {report.Findings.Count}");
            Console.WriteLine($"ZIP             : {zip}");
            Console.WriteLine($"SHA256          : {zipHash}");
            Console.WriteLine("============================================================");
            Console.WriteLine();
            Console.WriteLine("Envie o ZIP completo. Os arquivos principais para analise sao:");
            Console.WriteLine("  consolidated_audit.json");
            Console.WriteLine("  correction_inputs.json");
            Console.WriteLine("  AUDIT_SUMMARY.md");

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[RuntimeAudit] FATAL: " + ex);
            return 1;
        }
    }

    private static AuditOptions ParseOptions(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (!arg.StartsWith("--", StringComparison.Ordinal))
                continue;

            var key = arg[2..];
            if (i + 1 >= args.Length)
                throw new ArgumentException($"Missing value for --{key}");
            values[key] = args[++i];
        }

        var repo = values.TryGetValue("repo", out var repoValue)
            ? repoValue
            : Directory.GetCurrentDirectory();

        if (!values.TryGetValue("eboot", out var eboot))
            throw new ArgumentException("Required argument: --eboot <path>");

        values.TryGetValue("emulator", out var emulator);
        values.TryGetValue("game-root", out var gameRoot);
        values.TryGetValue("config", out var config);
        values.TryGetValue("output-root", out var outputRoot);

        return new AuditOptions
        {
            RepositoryRoot = repo,
            EbootPath = eboot,
            EmulatorPath = emulator,
            GameRoot = gameRoot,
            ConfigPath = config,
            OutputRoot = outputRoot
        };
    }

    private static AuditConfig LoadConfig(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<AuditConfig>(
                   json,
                   new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
               ?? new AuditConfig();
    }

    private static string ResolveConfig(string repo, string? explicitPath)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            var full = Path.GetFullPath(explicitPath);
            if (!File.Exists(full))
                throw new FileNotFoundException("Audit config not found.", full);
            return full;
        }

        var candidates = new[]
        {
            Path.Combine(repo, "tools", "SharpEmu.RuntimeAudit", "audit-profile.json"),
            Path.Combine(AppContext.BaseDirectory, "audit-profile.json")
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
                return candidate;
        }

        throw new FileNotFoundException("audit-profile.json not found.");
    }

    private static string ResolveEmulator(string repo, string? explicitPath)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            var full = Path.GetFullPath(explicitPath);
            if (!File.Exists(full))
                throw new FileNotFoundException("SharpEmu executable not found.", full);
            return full;
        }

        var candidates = new[]
        {
            Path.Combine(repo, "artifacts", "bin", "Debug", "net10.0", "win-x64", "SharpEmu.exe"),
            Path.Combine(repo, "artifacts", "bin", "Release", "net10.0", "win-x64", "SharpEmu.exe"),
            Path.Combine(repo, "artifacts", "bin", "Debug", "net10.0", "SharpEmu.exe"),
            Path.Combine(repo, "artifacts", "bin", "Release", "net10.0", "SharpEmu.exe")
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
                return candidate;
        }

        var discovered = Directory.EnumerateFiles(
                Path.Combine(repo, "artifacts"),
                "SharpEmu.exe",
                SearchOption.AllDirectories)
            .FirstOrDefault();

        return discovered
            ?? throw new FileNotFoundException("Could not locate SharpEmu.exe under artifacts.");
    }

    private static void WriteManifest(string output)
    {
        var manifest = new List<string>();
        foreach (var file in Directory.EnumerateFiles(output, "*", SearchOption.AllDirectories)
                     .OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
        {
            var relative = Path.GetRelativePath(output, file).Replace('\\', '/');
            if (relative.Equals("AUDIT_MANIFEST_SHA256.txt", StringComparison.OrdinalIgnoreCase))
                continue;
            try
            {
                manifest.Add($"{AuditUtil.Sha256File(file)} *{relative}");
            }
            catch
            {
                // Best-effort.
            }
        }

        File.WriteAllLines(
            Path.Combine(output, "AUDIT_MANIFEST_SHA256.txt"),
            manifest);
    }
}
