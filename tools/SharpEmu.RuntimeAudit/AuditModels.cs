using System.Text.Json.Serialization;

namespace SharpEmu.RuntimeAudit;

internal sealed class AuditConfig
{
    public int SchemaVersion { get; set; } = 1;
    public int SampleIntervalMs { get; set; } = 500;
    public int GpuSampleIntervalMs { get; set; } = 2000;
    public int MaxRuntimeSeconds { get; set; }
    public int MaxEvidencePerCategory { get; set; } = 5000;
    public bool EnableGameInventory { get; set; } = true;
    public bool EnableSourceScan { get; set; } = true;
    public bool EnableEbootStringScan { get; set; } = true;
    public bool EnableSourceSnapshot { get; set; } = true;
    public int SourceSnapshotMaxFiles { get; set; } = 40;
    public Dictionary<string, string> ChildEnvironment { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<string> UnsetChildEnvironment { get; set; } = [];
    public List<string> InterestingMediaExtensions { get; set; } = [];
    public List<string> SnapshotFileNames { get; set; } = [];
}

internal sealed class AuditOptions
{
    public required string RepositoryRoot { get; init; }
    public required string EbootPath { get; init; }
    public string? EmulatorPath { get; init; }
    public string? GameRoot { get; init; }
    public string? ConfigPath { get; init; }
    public string? OutputRoot { get; init; }
}

internal sealed class AuditReport
{
    public string Schema { get; set; } = "SharpEmu.RuntimeAudit/1";
    public string ToolVersion { get; set; } = "1.1.0";
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset FinishedAt { get; set; }
    public string RepositoryRoot { get; set; } = "";
    public string EbootPath { get; set; } = "";
    public string GameRoot { get; set; } = "";
    public string EmulatorPath { get; set; } = "";
    public string OutputDirectory { get; set; } = "";
    public HostInfo Host { get; set; } = new();
    public RepositoryInfo Repository { get; set; } = new();
    public EbootInfo Eboot { get; set; } = new();
    public GameInventory Game { get; set; } = new();
    public SourceAudit Source { get; set; } = new();
    public RuntimeAudit Runtime { get; set; } = new();
    public List<string> Warnings { get; set; } = [];
    public List<AuditFinding> Findings { get; set; } = [];
}

internal sealed class HostInfo
{
    public string MachineName { get; set; } = "";
    public string OSDescription { get; set; } = "";
    public string OSArchitecture { get; set; } = "";
    public string ProcessArchitecture { get; set; } = "";
    public int ProcessorCount { get; set; }
    public ulong TotalPhysicalMemoryBytes { get; set; }
    public string DotnetInfo { get; set; } = "";
    public string GpuInfo { get; set; } = "";
}

internal sealed class RepositoryInfo
{
    public string GitHead { get; set; } = "";
    public string GitStatus { get; set; } = "";
    public List<FileHashRecord> KeySourceHashes { get; set; } = [];
}

internal sealed class EbootInfo
{
    public long SizeBytes { get; set; }
    public string Sha256 { get; set; } = "";
    public List<string> InterestingStrings { get; set; } = [];
    public List<string> Libraries { get; set; } = [];
    public List<string> Modules { get; set; } = [];
}

internal sealed class GameInventory
{
    public long FileCount { get; set; }
    public long TotalBytes { get; set; }
    public List<ExtensionStat> Extensions { get; set; } = [];
    public List<GameFileRecord> MediaFiles { get; set; } = [];
    public List<GameFileRecord> LargestFiles { get; set; } = [];
}

internal sealed class SourceAudit
{
    public int SourceFileCount { get; set; }
    public List<RuntimeParameterRecord> RuntimeParameters { get; set; } = [];
    public List<SourceGapRecord> PotentialGaps { get; set; } = [];
    public List<NativeIntegrationRecord> NativeIntegrations { get; set; } = [];
    public List<ManagedDependencyRecord> ManagedDependencies { get; set; } = [];
    public List<ApiIntegrationSummary> ApiIntegrations { get; set; } = [];
    public List<FileHashRecord> SourceHashes { get; set; } = [];
    public List<string> SnapshotFiles { get; set; } = [];
}

internal sealed class RuntimeAudit
{
    public int ExitCode { get; set; }
    public double WallSeconds { get; set; }
    public bool KilledByTimeout { get; set; }
    public long StdoutLines { get; set; }
    public long StderrLines { get; set; }
    public List<ProcessMetric> ProcessMetrics { get; set; } = [];
    public List<GpuMetric> GpuMetrics { get; set; } = [];
    public RuntimeSummary Summary { get; set; } = new();
    public List<RuntimeEvent> StageEvents { get; set; } = [];
    public List<RuntimeEvent> VideoEvents { get; set; } = [];
    public List<RuntimeEvent> AudioEvents { get; set; } = [];
    public List<RuntimeEvent> QueueEvents { get; set; } = [];
    public List<RuntimeEvent> UnmappedEvents { get; set; } = [];
    public List<UnmappedFunctionRecord> UnmappedFunctions { get; set; } = [];
    public List<RuntimeEvent> ApiEvents { get; set; } = [];
    public List<FileAccessRecord> FileAccesses { get; set; } = [];
}

internal sealed class UnmappedFunctionRecord
{
    public string Function { get; set; } = "";
    public string Nid { get; set; } = "";
    public long Count { get; set; }
    public string FirstEvidence { get; set; } = "";
}

internal sealed class RuntimeSummary
{
    public double MaxWorkingSetMb { get; set; }
    public double MaxPrivateMemoryMb { get; set; }
    public double MaxCpuPercent { get; set; }
    public double AvgCpuPercent { get; set; }
    public double MinAvailableSystemMemoryMb { get; set; }
    public double MaxGpuMemoryUsedMb { get; set; }
    public double MaxGpuUtilizationPercent { get; set; }
    public double PresentCadenceLastHz { get; set; }
    public double PresentCadenceAverageHz { get; set; }
    public long MaxGuestWorkPending { get; set; }
    public double MaxSlowRenderWorkMs { get; set; }
    public double MaxSlowWaitMs { get; set; }
    public long MaxSubmissionOvercommitPending { get; set; }
    public double MaxComputeResourceTotalMs { get; set; }
    public double MaxComputeStorageMs { get; set; }
    public double MaxComputeTextureMs { get; set; }
    public double MaxComputeBufferMs { get; set; }
    public double MaxComputeDescriptorMs { get; set; }
    public double MaxComputePipelineMs { get; set; }
    public int UnmappedRuntimeCount { get; set; }
    public int VideoEventCount { get; set; }
    public int AudioEventCount { get; set; }
    public int ApiEventCount { get; set; }
    public int UniqueFileAccessCount { get; set; }
    public int HeapCorruptionHits { get; set; }
    public int AccessViolationHits { get; set; }
    public int DeviceLostHits { get; set; }
}

internal sealed class AuditFinding
{
    public string Severity { get; set; } = "info";
    public string Category { get; set; } = "";
    public string Code { get; set; } = "";
    public string Message { get; set; } = "";
    public List<string> Evidence { get; set; } = [];
}

internal sealed class FileHashRecord
{
    public string Path { get; set; } = "";
    public string Sha256 { get; set; } = "";
    public long SizeBytes { get; set; }
}

internal sealed class ExtensionStat
{
    public string Extension { get; set; } = "";
    public long Count { get; set; }
    public long Bytes { get; set; }
}

internal sealed class GameFileRecord
{
    public string RelativePath { get; set; } = "";
    public long SizeBytes { get; set; }
    public bool Readable { get; set; } = true;
    public string HeaderHex { get; set; } = "";
}

internal sealed class RuntimeParameterRecord
{
    public string Name { get; set; } = "";
    public string SourceFile { get; set; } = "";
    public int Line { get; set; }
    public string Context { get; set; } = "";
    public string ChildValue { get; set; } = "";
}

internal sealed class SourceGapRecord
{
    public string Kind { get; set; } = "";
    public string SourceFile { get; set; } = "";
    public int Line { get; set; }
    public string Text { get; set; } = "";
}

internal sealed class NativeIntegrationRecord
{
    public string Kind { get; set; } = "";
    public string Library { get; set; } = "";
    public string SourceFile { get; set; } = "";
    public int Line { get; set; }
}

internal sealed class ManagedDependencyRecord
{
    public string Project { get; set; } = "";
    public string Package { get; set; } = "";
    public string Version { get; set; } = "";
}

internal sealed class ApiIntegrationSummary
{
    public string Api { get; set; } = "";
    public int SourceFileHits { get; set; }
    public int RuntimeLineHits { get; set; }
    public List<string> RepresentativeFiles { get; set; } = [];
}

internal sealed class ProcessMetric
{
    public DateTimeOffset Timestamp { get; set; }
    public double ElapsedSeconds { get; set; }
    public double CpuPercent { get; set; }
    public double WorkingSetMb { get; set; }
    public double PrivateMemoryMb { get; set; }
    public double VirtualMemoryMb { get; set; }
    public int ThreadCount { get; set; }
    public int HandleCount { get; set; }
    public double AvailableSystemMemoryMb { get; set; }
}

internal sealed class GpuMetric
{
    public DateTimeOffset Timestamp { get; set; }
    public double ElapsedSeconds { get; set; }
    public int ProcessId { get; set; }
    public string GpuName { get; set; } = "";
    public double UtilizationPercent { get; set; }
    public double MemoryUsedMb { get; set; }
    public double MemoryTotalMb { get; set; }
    public double ProcessMemoryMb { get; set; }
}

internal sealed class RuntimeEvent
{
    public DateTimeOffset Timestamp { get; set; }
    public string Stream { get; set; } = "";
    public string Category { get; set; } = "";
    public string Text { get; set; } = "";
}

internal sealed class FileAccessRecord
{
    public string Path { get; set; } = "";
    public long Count { get; set; }
    public string FirstCategory { get; set; } = "";
    public string FirstEvidence { get; set; } = "";
}
