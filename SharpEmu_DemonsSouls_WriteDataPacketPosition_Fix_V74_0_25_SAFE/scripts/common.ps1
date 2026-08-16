Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV74025 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Get-Location).Path }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $markerPath = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($markerPath)) { throw "[V74.0.25] Repository root invalid: $repoRoot" }
    return $repoRoot
}

function Get-AgcPathV74025 {
    param([string]$Root)
    $sourcePath = [System.IO.Path]::Combine($Root, "src", "SharpEmu.Libs", "Agc", "AgcExports.cs")
    if (-not [System.IO.File]::Exists($sourcePath)) { throw "[V74.0.25] Missing AgcExports.cs: $sourcePath" }
    return $sourcePath
}
function Get-PresenterPathV74025 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs") }
function Get-CpuPathV74025 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","CpuDispatcher.cs") }
function Get-DirectPathV74025 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.cs") }
function Get-KernelPathV74025 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Kernel","KernelExports.cs") }
function Get-HostMoviePathV74025 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs") }

function Test-V21AbiAppliedV74025 {
    param([string]$Root)
    $cpuPath=Get-CpuPathV74025 -Root $Root
    $directPath=Get-DirectPathV74025 -Root $Root
    $kernelPath=Get-KernelPathV74025 -Root $Root
    foreach ($requiredPath in @($cpuPath,$directPath,$kernelPath)) { if (-not [System.IO.File]::Exists($requiredPath)) { return $false } }
    $cpuText=[System.IO.File]::ReadAllText($cpuPath)
    $directText=[System.IO.File]::ReadAllText($directPath)
    $kernelText=[System.IO.File]::ReadAllText($kernelPath)
    return $cpuText.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $cpuText.Contains("const ulong entryParamsSize = 0x118;") -and
        $cpuText.Contains("const int maxArguments = 33;") -and
        $directText.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and
        $kernelText.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")
}

function Test-PresenterRollupV74025 {
    param([string]$Root)
    $path=Get-PresenterPathV74025 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE") -and
        $text.Contains("SHARPEMU_V74_0_24_FRESH_STALE_SOURCE") -and
        $text.Contains("TryRefreshStaleTextureSourceV74024")
}

function Get-V25StateV74025 {
    param([string]$Text)
    $normalized=$Text.Replace("`r`n","`n")
    $marker=$normalized.Contains("SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION")
    $gate=$normalized.Contains("SHARPEMU_WRITE_DATA_PACKET_POSITION")
    $branch=$normalized.Contains("packetPositionWriteV74025")
    $resume=$normalized.Contains("[V74.0.25][WAIT_RESUME]")
    if ($marker -and $gate -and $branch -and $resume) { return "Applied" }
    if ($marker -or $gate -or $branch -or $resume) { return "Partial" }
    if (-not $normalized.Contains("SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT")) { return "Unknown" }
    if (-not $normalized.Contains("SubmitOrderedGuestActionAfterQueueCompletion(")) { return "Unknown" }
    if (-not $normalized.Contains("requiresGpuBufferReadback: false);")) { return "Unknown" }
    if (-not $normalized.Contains("private static void ResumeSuspendedDcb(")) { return "Unknown" }

    $fieldAnchor=@'
    private static readonly bool _traceAgc = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LOG_AGC"),
        "1",
        StringComparison.Ordinal);
'@
    $branchAnchor=@'
        var orderedSequence = requiresGpuBufferReadback
            ? GuestGpu.Current.SubmitOrderedGuestAction(
                ApplyAndQueueCompletion,
                debugName)
            : GuestGpu.Current.SubmitOrderedGuestActionAfterQueueCompletion(
                ApplyAndQueueCompletion,
                debugName);
'@
    $resumeAnchor=@'
        var waitedMilliseconds = waiter.RegisteredTicks == 0
            ? 0.0
            : (System.Diagnostics.Stopwatch.GetTimestamp() - waiter.RegisteredTicks) *
              1000.0 / System.Diagnostics.Stopwatch.Frequency;
        TraceAgcShader(
'@
    foreach ($anchor in @($fieldAnchor,$branchAnchor,$resumeAnchor)) {
        $a=$anchor.Replace("`r`n","`n").TrimStart("`n".ToCharArray()).TrimEnd()
        if (([regex]::Matches($normalized,[regex]::Escape($a))).Count -ne 1) { return "Unknown" }
    }
    return "Baseline"
}

function Convert-AgcV74025 {
    param([string]$Text)
    $state=Get-V25StateV74025 -Text $Text
    if ($state -eq "Applied") { return $Text }
    if ($state -ne "Baseline") { throw "[V74.0.25] AGC transform state is $state; refusing source modification." }
    $hadCrlf=$Text.Contains("`r`n")
    $normalized=$Text.Replace("`r`n","`n")

    $fieldAnchor=@'
    private static readonly bool _traceAgc = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LOG_AGC"),
        "1",
        StringComparison.Ordinal);
'@
    $fieldReplacement=@'
    private static readonly bool _traceAgc = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LOG_AGC"),
        "1",
        StringComparison.Ordinal);

    // SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION
    // Opt-in restoration of the pre-V73.5 WRITE_DATA scheduling contract.
    // WRITE_DATA carries an immediate CPU-resident payload. When enabled, its
    // side effect executes at its logical PM4 queue position after prior batched
    // commands are flushed, rather than waiting for the host fence of every
    // earlier shader dispatch in that queue. RELEASE_MEM/DMA/ACQUIRE visibility
    // behavior is untouched. The default remains the accumulated V73.5 path.
    private static readonly bool _writeDataPacketPositionV74025 = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_WRITE_DATA_PACKET_POSITION"),
        "1",
        StringComparison.Ordinal);
    private static long _v74025WriteDataPacketPositionTraceCount;
    private static long _v74025WaitResumeTraceCount;
'@

    $branchAnchor=@'
        var orderedSequence = requiresGpuBufferReadback
            ? GuestGpu.Current.SubmitOrderedGuestAction(
                ApplyAndQueueCompletion,
                debugName)
            : GuestGpu.Current.SubmitOrderedGuestActionAfterQueueCompletion(
                ApplyAndQueueCompletion,
                debugName);
'@
    $branchReplacement=@'
        var packetPositionWriteV74025 =
            !requiresGpuBufferReadback && _writeDataPacketPositionV74025;
        var orderedSequence = requiresGpuBufferReadback || packetPositionWriteV74025
            ? GuestGpu.Current.SubmitOrderedGuestAction(
                ApplyAndQueueCompletion,
                debugName)
            : GuestGpu.Current.SubmitOrderedGuestActionAfterQueueCompletion(
                ApplyAndQueueCompletion,
                debugName);
        if (packetPositionWriteV74025)
        {
            var packetPositionCount = Interlocked.Increment(
                ref _v74025WriteDataPacketPositionTraceCount);
            if (packetPositionCount <= 64 ||
                (packetPositionCount & (packetPositionCount - 1)) == 0)
            {
                var watchedRanges = producerAddress != 0 && producerLength != 0
                    ? GpuWaitRegistry.SnapshotInRange(
                        CanonicalMemory(ctx.Memory),
                        producerAddress,
                        producerLength).Count
                    : 0;
                Console.Error.WriteLine(
                    $"[V74.0.25][WRITE_DATA_PACKET_POSITION] count={packetPositionCount} " +
                    $"queue={state.QueueName} submission={state.ActiveSubmissionId} " +
                    $"addr=0x{producerAddress:X16} bytes={producerLength} " +
                    $"watched_ranges={watchedRanges} sequence={orderedSequence} " +
                    $"name='{debugName}'");
            }
        }
'@

    $resumeAnchor=@'
        var waitedMilliseconds = waiter.RegisteredTicks == 0
            ? 0.0
            : (System.Diagnostics.Stopwatch.GetTimestamp() - waiter.RegisteredTicks) *
              1000.0 / System.Diagnostics.Stopwatch.Frequency;
        TraceAgcShader(
'@
    $resumeReplacement=@'
        var waitedMilliseconds = waiter.RegisteredTicks == 0
            ? 0.0
            : (System.Diagnostics.Stopwatch.GetTimestamp() - waiter.RegisteredTicks) *
              1000.0 / System.Diagnostics.Stopwatch.Frequency;
        if (_writeDataPacketPositionV74025)
        {
            var resumeCount = Interlocked.Increment(ref _v74025WaitResumeTraceCount);
            if (resumeCount <= 256 || (resumeCount & (resumeCount - 1)) == 0)
            {
                Console.Error.WriteLine(
                    $"[V74.0.25][WAIT_RESUME] count={resumeCount} " +
                    $"queue={waiter.QueueName} submission={waiter.SubmissionId} " +
                    $"label=0x{waiter.WaitAddress:X16} waited_ms={waitedMilliseconds:F3} " +
                    $"remaining_dwords={remainingDwords}");
            }
        }
        TraceAgcShader(
'@

    foreach ($pair in @(@($fieldAnchor,$fieldReplacement),@($branchAnchor,$branchReplacement),@($resumeAnchor,$resumeReplacement))) {
        $anchor=$pair[0].Replace("`r`n","`n").TrimStart("`n".ToCharArray()).TrimEnd()
        $replacement=$pair[1].Replace("`r`n","`n").TrimStart("`n".ToCharArray()).TrimEnd()
        if (([regex]::Matches($normalized,[regex]::Escape($anchor))).Count -ne 1) {
            throw "[V74.0.25] AGC anchor missing or not unique."
        }
        $normalized=$normalized.Replace($anchor,$replacement)
    }
    if ((Get-V25StateV74025 -Text $normalized) -ne "Applied") { throw "[V74.0.25] In-memory post-transform verification failed." }
    if ($hadCrlf) { return $normalized.Replace("`n","`r`n") }
    return $normalized
}

function Invoke-DotNetCheckedV74025 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "[V74.0.25] dotnet failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV74025 {
    param([string]$Root)
    $debugRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $releaseRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins","pipeline_cache")) {
        $sourcePath=[System.IO.Path]::Combine($debugRoot,$assetName)
        $destinationPath=[System.IO.Path]::Combine($releaseRoot,$assetName)
        if ([System.IO.Directory]::Exists($sourcePath)) {
            if (-not [System.IO.Directory]::Exists($destinationPath)) { [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null }
            Copy-Item -Path ([System.IO.Path]::Combine($sourcePath,"*")) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74025 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attemptIndex=0;$attemptIndex -lt 5;$attemptIndex++) {
        try {
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $reader=[System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,65536,$false)
                try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    return ""
}

function Get-DescendantProcessIdsV74025 {
    param([int]$ParentId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    $queue=New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId=$queue.Dequeue()
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId=[int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) { $result.Add($childId); $queue.Enqueue($childId) }
        }
    }
    return @($result)
}
