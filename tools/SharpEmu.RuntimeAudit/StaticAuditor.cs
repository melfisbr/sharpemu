using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace SharpEmu.RuntimeAudit;

internal sealed class StaticAuditor
{
    private readonly string _repo;
    private readonly string _gameRoot;
    private readonly string _eboot;
    private readonly string _output;
    private readonly AuditConfig _config;

    private static readonly Regex EnvRegex = new(
        @"GetEnvironmentVariable\s*\(\s*""([^""]+)""\s*\)",
        RegexOptions.Compiled);

    private static readonly Regex DllImportRegex = new(
        @"(?:DllImport|LibraryImport)\s*\(\s*""([^""]+)""",
        RegexOptions.Compiled);

    private static readonly Regex NativeLoadRegex = new(
        @"NativeLibrary\.(?:Load|TryLoad)\s*\(\s*""([^""]+)""",
        RegexOptions.Compiled);

    private static readonly (string Kind, Regex Pattern)[] GapPatterns =
    [
        ("NotImplementedException", new Regex(@"\bNotImplementedException\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("NotSupportedException", new Regex(@"\bNotSupportedException\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("TODO", new Regex(@"\bTODO\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("FIXME", new Regex(@"\bFIXME\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("Stub", new Regex(@"\bstub(?:bed)?\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("Unsupported", new Regex(@"\bunsupported\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("Unimplemented", new Regex(@"\bunimplemented\b", RegexOptions.IgnoreCase | RegexOptions.Compiled)),
        ("NotMapped", new Regex(@"\b(?:unmapped|not mapped|missing export|unknown import|unknown nid)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled))
    ];

    private static readonly Dictionary<string, string[]> ApiKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Vulkan"] = ["Vulkan", "Silk.NET.Vulkan", "Vk."],
        ["SDL"] = ["SDL", "SDL3", "SDL2"],
        ["Bink"] = ["Bink", ".bk2", "Nihav"],
        ["Audio/AJM"] = ["Ajm", "AudioOut", "Atrac9", "ATRAC9", ".at9"],
        ["AMPR"] = ["Ampr", "APR_READ", "sceAmpr"],
        ["AGC"] = ["Agc", "sceAgc", "PM4"],
        ["VideoOut"] = ["VideoOut", "sceVideoOut"],
        ["SceDynamic"] = ["SceDynamic", "Ps5SceDynamic", "relocation"],
        ["Kernel/Pthread"] = ["Pthread", "KernelMemory", "DirectMemory"],
        ["PlayGo"] = ["PlayGo", "scePlayGo"],
        ["NP"] = ["sceNp", "SharpEmu.Libs.Np"],
        ["SaveData"] = ["SaveData", "sceSaveData"]
    };

    public StaticAuditor(
        string repositoryRoot,
        string gameRoot,
        string ebootPath,
        string outputDirectory,
        AuditConfig config)
    {
        _repo = repositoryRoot;
        _gameRoot = gameRoot;
        _eboot = ebootPath;
        _output = outputDirectory;
        _config = config;
    }

    public async Task CollectAsync(AuditReport report)
    {
        report.Repository.GitHead = await AuditUtil.RunCaptureAsync("git.exe", "rev-parse HEAD", _repo);
        report.Repository.GitStatus = await AuditUtil.RunCaptureAsync("git.exe", "status --short", _repo);
        report.Host.DotnetInfo = await AuditUtil.RunCaptureAsync("dotnet.exe", "--info", _repo, 20000);
        report.Host.GpuInfo = await AuditUtil.RunCaptureAsync(
            "nvidia-smi.exe",
            "--query-gpu=name,driver_version,memory.total --format=csv,noheader",
            _repo);

        if (File.Exists(_eboot))
        {
            report.Eboot.SizeBytes = new FileInfo(_eboot).Length;
            report.Eboot.Sha256 = AuditUtil.Sha256File(_eboot);
            if (_config.EnableEbootStringScan)
                ScanEbootStrings(report.Eboot);
        }

        if (_config.EnableGameInventory && Directory.Exists(_gameRoot))
            ScanGameInventory(report.Game);

        if (_config.EnableSourceScan)
            ScanSource(report.Source, report.Repository);

        if (_config.EnableSourceSnapshot)
            CopySourceSnapshot(report.Source);

        WriteStaticArtifacts(report);
    }

    private void ScanGameInventory(GameInventory inventory)
    {
        var ext = new Dictionary<string, (long Count, long Bytes)>(StringComparer.OrdinalIgnoreCase);
        var largest = new List<GameFileRecord>();
        var media = new List<GameFileRecord>();
        var mediaSet = new HashSet<string>(_config.InterestingMediaExtensions, StringComparer.OrdinalIgnoreCase);

        foreach (var file in EnumerateFilesSafe(_gameRoot))
        {
            try
            {
                var info = new FileInfo(file);
                inventory.FileCount++;
                inventory.TotalBytes += info.Length;

                var extension = Path.GetExtension(file);
                if (string.IsNullOrEmpty(extension))
                    extension = "<none>";
                if (!ext.TryGetValue(extension, out var stat))
                    stat = (0, 0);
                ext[extension] = (stat.Count + 1, stat.Bytes + info.Length);

                var record = new GameFileRecord
                {
                    RelativePath = AuditUtil.RelativeOrFull(_gameRoot, file),
                    SizeBytes = info.Length
                };

                if (mediaSet.Contains(Path.GetExtension(file)))
                {
                    try
                    {
                        using var mediaStream = File.Open(
                            file,
                            FileMode.Open,
                            FileAccess.Read,
                            FileShare.ReadWrite | FileShare.Delete);
                        var header = new byte[Math.Min(16, (int)Math.Min(info.Length, 16))];
                        var headerRead = mediaStream.Read(header, 0, header.Length);
                        record.Readable = true;
                        record.HeaderHex = Convert.ToHexString(header.AsSpan(0, headerRead));
                    }
                    catch
                    {
                        record.Readable = false;
                        record.HeaderHex = "";
                    }

                    if (media.Count < 10000)
                        media.Add(record);
                }

                largest.Add(record);
                if (largest.Count > 1000)
                {
                    largest = largest
                        .OrderByDescending(x => x.SizeBytes)
                        .Take(500)
                        .ToList();
                }
            }
            catch
            {
                // Inventory is best-effort; inaccessible files are reported by count drift.
            }
        }

        inventory.Extensions = ext
            .Select(x => new ExtensionStat
            {
                Extension = x.Key,
                Count = x.Value.Count,
                Bytes = x.Value.Bytes
            })
            .OrderByDescending(x => x.Count)
            .ThenBy(x => x.Extension, StringComparer.OrdinalIgnoreCase)
            .ToList();

        inventory.MediaFiles = media
            .OrderBy(x => x.RelativePath, StringComparer.OrdinalIgnoreCase)
            .ToList();

        inventory.LargestFiles = largest
            .OrderByDescending(x => x.SizeBytes)
            .Take(200)
            .ToList();
    }

    private void ScanEbootStrings(EbootInfo eboot)
    {
        var interesting = new HashSet<string>(StringComparer.Ordinal);
        var libraries = new HashSet<string>(StringComparer.Ordinal);
        var modules = new HashSet<string>(StringComparer.Ordinal);

        using var stream = File.OpenRead(_eboot);
        var buffer = new byte[1024 * 1024];
        var current = new StringBuilder(256);
        int read;

        void Flush()
        {
            if (current.Length < 5)
            {
                current.Clear();
                return;
            }

            var value = current.ToString();
            current.Clear();

            if (value.Length > 1024)
                return;

            var lower = value.ToLowerInvariant();
            if (lower.Contains("libsce") ||
                lower.Contains(".prx") ||
                lower.Contains(".sprx") ||
                lower.Contains("sce") ||
                lower.Contains("bink") ||
                lower.Contains("video") ||
                lower.Contains("audio") ||
                lower.Contains("shader") ||
                lower.Contains("resource") ||
                lower.Contains("playgo"))
            {
                if (interesting.Count < 20000)
                    interesting.Add(value);
            }

            foreach (Match match in Regex.Matches(value, @"libSce[A-Za-z0-9_+\-.]+"))
                libraries.Add(match.Value);

            foreach (Match match in Regex.Matches(value, @"[A-Za-z0-9_+\-.]+\.(?:prx|sprx)", RegexOptions.IgnoreCase))
                modules.Add(match.Value);
        }

        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            for (var i = 0; i < read; i++)
            {
                var b = buffer[i];
                if (b is >= 32 and <= 126)
                {
                    if (current.Length < 2048)
                        current.Append((char)b);
                }
                else
                {
                    Flush();
                }
            }
        }
        Flush();

        eboot.InterestingStrings = interesting.OrderBy(x => x, StringComparer.Ordinal).ToList();
        eboot.Libraries = libraries.OrderBy(x => x, StringComparer.Ordinal).ToList();
        eboot.Modules = modules.OrderBy(x => x, StringComparer.Ordinal).ToList();
    }

    private void ScanSource(SourceAudit source, RepositoryInfo repository)
    {
        var srcRoot = Path.Combine(_repo, "src");
        if (!Directory.Exists(srcRoot))
            return;

        var apiFiles = ApiKeywords.ToDictionary(
            x => x.Key,
            _ => new HashSet<string>(StringComparer.OrdinalIgnoreCase),
            StringComparer.OrdinalIgnoreCase);

        foreach (var file in EnumerateFilesSafe(srcRoot)
                     .Where(x => x.EndsWith(".cs", StringComparison.OrdinalIgnoreCase)))
        {
            if (AuditUtil.IsExcludedRepoPath(file))
                continue;

            source.SourceFileCount++;
            var relative = AuditUtil.RelativeOrFull(_repo, file);

            try
            {
                var info = new FileInfo(file);
                var hash = new FileHashRecord
                {
                    Path = relative,
                    Sha256 = AuditUtil.Sha256File(file),
                    SizeBytes = info.Length
                };
                source.SourceHashes.Add(hash);

                if (IsKeySourceFile(file))
                    repository.KeySourceHashes.Add(hash);

                var lines = File.ReadAllLines(file);
                for (var index = 0; index < lines.Length; index++)
                {
                    var line = lines[index];
                    var lineNo = index + 1;

                    foreach (Match match in EnvRegex.Matches(line))
                    {
                        source.RuntimeParameters.Add(new RuntimeParameterRecord
                        {
                            Name = match.Groups[1].Value,
                            SourceFile = relative,
                            Line = lineNo,
                            Context = line.Trim()
                        });
                    }

                    foreach (var (kind, pattern) in GapPatterns)
                    {
                        if (pattern.IsMatch(line))
                        {
                            source.PotentialGaps.Add(new SourceGapRecord
                            {
                                Kind = kind,
                                SourceFile = relative,
                                Line = lineNo,
                                Text = line.Trim()
                            });
                            break;
                        }
                    }

                    foreach (Match match in DllImportRegex.Matches(line))
                    {
                        source.NativeIntegrations.Add(new NativeIntegrationRecord
                        {
                            Kind = "PInvoke",
                            Library = match.Groups[1].Value,
                            SourceFile = relative,
                            Line = lineNo
                        });
                    }

                    foreach (Match match in NativeLoadRegex.Matches(line))
                    {
                        source.NativeIntegrations.Add(new NativeIntegrationRecord
                        {
                            Kind = "NativeLibrary",
                            Library = match.Groups[1].Value,
                            SourceFile = relative,
                            Line = lineNo
                        });
                    }

                    foreach (var api in ApiKeywords)
                    {
                        if (api.Value.Any(keyword =>
                                line.Contains(keyword, StringComparison.OrdinalIgnoreCase)))
                            apiFiles[api.Key].Add(relative);
                    }
                }
            }
            catch
            {
                // Per-file source scan is best-effort.
            }
        }

        var childValues = _config.ChildEnvironment;
        foreach (var parameter in source.RuntimeParameters)
        {
            if (childValues.TryGetValue(parameter.Name, out var value))
                parameter.ChildValue = value;
            else if (_config.UnsetChildEnvironment.Contains(parameter.Name, StringComparer.OrdinalIgnoreCase))
                parameter.ChildValue = "<unset>";
            else
                parameter.ChildValue = Environment.GetEnvironmentVariable(parameter.Name) ?? "";
        }

        source.RuntimeParameters = source.RuntimeParameters
            .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.SourceFile, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.Line)
            .ToList();

        source.PotentialGaps = source.PotentialGaps
            .Take(20000)
            .ToList();

        source.ApiIntegrations = apiFiles
            .Select(x => new ApiIntegrationSummary
            {
                Api = x.Key,
                SourceFileHits = x.Value.Count,
                RepresentativeFiles = x.Value
                    .OrderBy(v => v, StringComparer.OrdinalIgnoreCase)
                    .Take(20)
                    .ToList()
            })
            .OrderByDescending(x => x.SourceFileHits)
            .ToList();

        ScanManagedDependencies(source);
    }

    private void ScanManagedDependencies(SourceAudit source)
    {
        foreach (var project in EnumerateFilesSafe(_repo)
                     .Where(x => x.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase)))
        {
            if (AuditUtil.IsExcludedRepoPath(project))
                continue;

            try
            {
                var doc = XDocument.Load(project);
                foreach (var package in doc.Descendants().Where(x => x.Name.LocalName == "PackageReference"))
                {
                    var name = package.Attribute("Include")?.Value ?? package.Attribute("Update")?.Value ?? "";
                    var version = package.Attribute("Version")?.Value
                        ?? package.Elements().FirstOrDefault(x => x.Name.LocalName == "Version")?.Value
                        ?? "";
                    if (string.IsNullOrWhiteSpace(name))
                        continue;

                    source.ManagedDependencies.Add(new ManagedDependencyRecord
                    {
                        Project = AuditUtil.RelativeOrFull(_repo, project),
                        Package = name,
                        Version = version
                    });
                }
            }
            catch
            {
                // Invalid/nonstandard project files are ignored.
            }
        }
    }

    private void CopySourceSnapshot(SourceAudit source)
    {
        var snapshotRoot = Path.Combine(_output, "source_snapshot");
        Directory.CreateDirectory(snapshotRoot);

        var names = new HashSet<string>(_config.SnapshotFileNames, StringComparer.OrdinalIgnoreCase);
        var candidates = EnumerateFilesSafe(Path.Combine(_repo, "src"))
            .Where(x => x.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
            .Where(x => names.Contains(Path.GetFileName(x)))
            .Take(_config.SourceSnapshotMaxFiles)
            .ToList();

        foreach (var file in candidates)
        {
            try
            {
                var relative = AuditUtil.RelativeOrFull(_repo, file);
                var destination = Path.Combine(snapshotRoot, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(file, destination, true);
                source.SnapshotFiles.Add(relative);
            }
            catch
            {
                // Snapshot is best-effort.
            }
        }
    }

    private void WriteStaticArtifacts(AuditReport report)
    {
        File.WriteAllLines(
            Path.Combine(_output, "eboot_interesting_strings.txt"),
            report.Eboot.InterestingStrings);

        File.WriteAllLines(
            Path.Combine(_output, "git_status.txt"),
            new[] { report.Repository.GitStatus });

        File.WriteAllLines(
            Path.Combine(_output, "dotnet_info.txt"),
            new[] { report.Host.DotnetInfo });

        File.WriteAllLines(
            Path.Combine(_output, "gpu_info.txt"),
            new[] { report.Host.GpuInfo });
    }

    private bool IsKeySourceFile(string path)
    {
        var name = Path.GetFileName(path);
        return _config.SnapshotFileNames.Contains(name, StringComparer.OrdinalIgnoreCase);
    }

    private static IEnumerable<string> EnumerateFilesSafe(string root)
    {
        if (!Directory.Exists(root))
            yield break;

        var pending = new Stack<string>();
        pending.Push(root);

        while (pending.Count > 0)
        {
            var current = pending.Pop();
            string[] files;
            try { files = Directory.GetFiles(current); }
            catch { files = []; }

            foreach (var file in files)
                yield return file;

            string[] dirs;
            try { dirs = Directory.GetDirectories(current); }
            catch { dirs = []; }

            foreach (var dir in dirs)
            {
                if (!AuditUtil.IsExcludedRepoPath(dir + Path.DirectorySeparatorChar))
                    pending.Push(dir);
            }
        }
    }
}
