param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\demons_souls_agc_v241_final.txt",

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = ".",

    [Parameter(Mandatory = $false)]
    [int]$SlowWaitThresholdMs = 500
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$CollectorVersion = "2.0-empty-safe"

function Write-Step([string]$Message) {
    Write-Host "[V241-FULL] $Message"
}

function Resolve-FromRepo([string]$PathValue) {
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $PathValue))
}

function Save-Lines {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        $Lines = @(),

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    # PowerShell may collapse an empty pipeline/array to $null during
    # parameter binding. Diagnostic categories with zero matches are valid,
    # so create an empty report instead of aborting the whole collection.
    if ($null -eq $Lines) {
        "" | Set-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $items = @($Lines)
    if ($items.Count -eq 0) {
        "" | Set-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $items | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Matches {
    param(
        [Parameter(Mandatory = $true)] [string[]]$Lines,
        [Parameter(Mandatory = $true)] [string]$Pattern
    )

    return @($Lines | Select-String -Pattern $Pattern -CaseSensitive:$false | ForEach-Object { $_.Line })
}

function Convert-LogNumber([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [double]0
    }

    $normalized = $Value.Trim().Replace(".", "").Replace(",", ".")
    $result = 0.0
    [void][double]::TryParse(
        $normalized,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$result
    )
    return $result
}

$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)

if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
    throw "RepositoryRoot not found: $RepositoryRoot"
}

$resolvedLog = Resolve-FromRepo $LogPath
if (-not (Test-Path -LiteralPath $resolvedLog -PathType Leaf)) {
    throw "Log file not found: $resolvedLog"
}

$resolvedOutputRoot = Resolve-FromRepo $OutputRoot
if (-not (Test-Path -LiteralPath $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Force -Path $resolvedOutputRoot | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bundleName = "SharpEmu_V241_FullDiagnostic_$stamp"
$outDir = Join-Path $resolvedOutputRoot $bundleName
$zipPath = Join-Path $resolvedOutputRoot ($bundleName + ".zip")

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $outDir "reports") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $outDir "sources") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $outDir "repo_state") | Out-Null

Write-Step "Collector version: $CollectorVersion"
Write-Step "Repository: $RepositoryRoot"
Write-Step "Log:        $resolvedLog"
Write-Step "Reading full log once..."

$lines = @(Get-Content -LiteralPath $resolvedLog)
$totalLines = $lines.Count
$logInfo = Get-Item -LiteralPath $resolvedLog

Copy-Item -LiteralPath $resolvedLog -Destination (Join-Path $outDir "demons_souls_agc_v241_final.txt") -Force

# ---------------------------------------------------------------------------
# 1) Global event counts
# ---------------------------------------------------------------------------
Write-Step "Collecting global counters..."

$counterPatterns = [ordered]@{
    "wait_suspended"                   = "agc\.wait_suspended"
    "producer_none"                    = "producer=none-observed"
    "producer_queued"                  = "producer_state=queued"
    "producer_completed_state"         = "producer_state=completed"
    "wait_producer_scheduled"          = "agc\.wait_producer_scheduled"
    "wait_producer_completed"          = "agc\.wait_producer_completed"
    "queue_resumed"                    = "agc\.queue_resumed"
    "indirect_wait"                    = "agc\.dispatch_indirect_wait"
    "indirect_visible"                 = "agc\.dispatch_indirect_visible"
    "indirect_confirmed_empty"         = "agc\.dispatch_indirect_confirmed_empty"
    "indirect_visibility_zero"         = "agc\.dispatch_indirect_visibility_zero"
    "indirect_retry_expired"           = "agc\.dispatch_indirect_retry_expired"
    "indirect_noop"                    = "agc\.dispatch_indirect_noop"
    "zero_dimension_reject"            = "reason=zero-dimension"
    "compute_dispatch"                 = "vk\.compute_dispatch"
    "global_writeback"                 = "vk\.global_writeback"
    "queue_visibility"                 = "vk\.queue_visibility"
    "rt_writer"                        = "agc\.rt_writer"
    "rt_sampled"                       = "agc\.rt_sampled"
    "texture_source"                   = "agc\.texture_source"
    "shader_draw"                      = "agc\.shader_draw"
    "offscreen_draw"                   = "vk\.offscreen_draw"
    "flip_capture"                     = "vk\.flip_capture"
    "flip_retired"                     = "vk\.flip_retired"
    "guest_frame_presented"            = "Vulkan VideoOut presented guest frame"
    "first_frame_presented"            = "Vulkan VideoOut presented first frame"
    "unknown_ds"                       = "unknown-ds"
    "unknown_sopc"                     = "unknown-sopc"
    "shader_translate_miss"            = "shader_translate_miss"
    "device_lost"                      = "device.?lost"
    "write_data"                       = "dcb\.write_data"
    "release_mem"                      = "dcb\.release_mem"
    "gpuwait_perf"                     = "\[PERF\]\[GPUWAIT\]"
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("SharpEmu V2.4.1 full diagnostic")
$summary.Add("Collector version: $CollectorVersion")
$summary.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
$summary.Add("Repository: $RepositoryRoot")
$summary.Add("Log: $resolvedLog")
$summary.Add("Log lines: $totalLines")
$summary.Add("Log bytes: $($logInfo.Length)")
$summary.Add("")
$summary.Add("EVENT COUNTS")

foreach ($entry in $counterPatterns.GetEnumerator()) {
    $count = @($lines | Select-String -Pattern $entry.Value -CaseSensitive:$false).Count
    $summary.Add(("{0,-34} {1,10}" -f $entry.Key, $count))
}

# ---------------------------------------------------------------------------
# 2) Parse all resumed waits and build per-label statistics
# ---------------------------------------------------------------------------
Write-Step "Parsing wait durations and per-label statistics..."

$waitRows = New-Object System.Collections.Generic.List[object]

foreach ($line in $lines) {
    if ($line -notmatch "agc\.queue_resumed") {
        continue
    }

    $label = ""
    $queue = ""
    $submission = ""
    $waitText = ""

    if ($line -match "label=0x([0-9A-Fa-f]+)") { $label = $matches[1].ToUpperInvariant() }
    if ($line -match "queue=([^\s]+)") { $queue = $matches[1] }
    if ($line -match "submission=([^\s]+)") { $submission = $matches[1] }
    if ($line -match "waited_ms=([0-9\.,]+)") { $waitText = $matches[1] }

    if (-not [string]::IsNullOrWhiteSpace($waitText)) {
        $waitMs = Convert-LogNumber $waitText

        $waitRows.Add([pscustomobject]@{
            Label      = if ($label) { "0x$label" } else { "" }
            Queue      = $queue
            Submission = $submission
            WaitMs     = [math]::Round($waitMs, 3)
            Raw        = $line
        })
    }
}

$slowWaits = @($waitRows | Where-Object { $_.WaitMs -ge $SlowWaitThresholdMs } | Sort-Object WaitMs -Descending)
$slowWaits | Export-Csv -LiteralPath (Join-Path $outDir "reports\slow_waits.csv") -NoTypeInformation -Encoding UTF8
Save-Lines -Lines ($slowWaits | ForEach-Object { $_.Raw }) -Path (Join-Path $outDir "reports\slow_waits.txt")

$labelStats = @(
    $waitRows |
    Where-Object { $_.Label } |
    Group-Object Label |
    ForEach-Object {
        $vals = @($_.Group | Select-Object -ExpandProperty WaitMs)
        [pscustomobject]@{
            Label       = $_.Name
            ResumeCount = $_.Count
            TotalWaitMs = [math]::Round((($vals | Measure-Object -Sum).Sum), 3)
            AverageMs   = [math]::Round((($vals | Measure-Object -Average).Average), 3)
            MaxWaitMs   = [math]::Round((($vals | Measure-Object -Maximum).Maximum), 3)
        }
    } |
    Sort-Object TotalWaitMs -Descending
)

$labelStats | Export-Csv -LiteralPath (Join-Path $outDir "reports\waits_by_label.csv") -NoTypeInformation -Encoding UTF8

$summary.Add("")
$summary.Add("WAIT LATENCY")
$summary.Add(("resume_samples                     {0,10}" -f $waitRows.Count))
$summary.Add(("slow_waits_ge_{0}ms              {1,10}" -f $SlowWaitThresholdMs, $slowWaits.Count))

if ($waitRows.Count -gt 0) {
    $vals = @($waitRows | Select-Object -ExpandProperty WaitMs)
    $summary.Add(("wait_total_ms                     {0,10:N3}" -f (($vals | Measure-Object -Sum).Sum)))
    $summary.Add(("wait_average_ms                   {0,10:N3}" -f (($vals | Measure-Object -Average).Average)))
    $summary.Add(("wait_max_ms                       {0,10:N3}" -f (($vals | Measure-Object -Maximum).Maximum)))
}

$summary.Add("")
$summary.Add("TOP 25 LABELS BY TOTAL BLOCKED TIME")
foreach ($row in ($labelStats | Select-Object -First 25)) {
    $summary.Add(("{0,-20} count={1,-5} total_ms={2,-12} avg_ms={3,-10} max_ms={4}" -f `
        $row.Label, $row.ResumeCount, $row.TotalWaitMs, $row.AverageMs, $row.MaxWaitMs))
}

# ---------------------------------------------------------------------------
# 3) Synchronization / generation traces
# ---------------------------------------------------------------------------
Write-Step "Extracting producer/generation timelines..."

$syncPattern = "agc\.wait_suspended|agc\.queue_resumed|agc\.wait_producer_scheduled|agc\.wait_producer_completed|agc\.dcb\.wait_reg_mem|agc\.dcb\.write_data|agc\.dcb\.release_mem|vk\.ordered_action.*(write_data|release_mem)"
Save-Lines -Lines (Get-Matches $lines $syncPattern) -Path (Join-Path $outDir "reports\sync_all.txt")

Save-Lines -Lines (Get-Matches $lines "producer=none-observed") -Path (Join-Path $outDir "reports\producer_none_waits.txt")
Save-Lines -Lines (Get-Matches $lines "producer_state=queued") -Path (Join-Path $outDir "reports\producer_queued_waits.txt")
Save-Lines -Lines (Get-Matches $lines "producer_state=completed") -Path (Join-Path $outDir "reports\producer_completed_waits.txt")
Save-Lines -Lines (Get-Matches $lines "wait_producer_scheduled|wait_producer_completed") -Path (Join-Path $outDir "reports\producer_lifecycle.txt")
Save-Lines -Lines (Get-Matches $lines "dcb\.write_data|dcb\.release_mem|write_data dst=|release_mem dst=") -Path (Join-Path $outDir "reports\all_writes.txt")

$knownLabels = @(
    "400257E00",
    "400257E20",
    "456CFF140",
    "456CFF760",
    "456CFF0E0",
    "456CFF440",
    "456CFF580",
    "456CFF4C0",
    "456CFF700",
    "456CFF7A0",
    "4430FF4E0",
    "4430FEEC0",
    "4430FF7A0",
    "4430FF300",
    "4430FF200",
    "4430FF1C0",
    "4430FF0E0",
    "4430FF060",
    "4430FF480",
    "4430FEE60"
)

$knownPattern = ($knownLabels -join "|")
Save-Lines -Lines (Get-Matches $lines $knownPattern) -Path (Join-Path $outDir "reports\known_label_timeline.txt")
Save-Lines -Lines (Get-Matches $lines "400257E00|400257E20") -Path (Join-Path $outDir "reports\global_barriers_E00_E20.txt")

# Extract all suspended-wait metadata in CSV form.
$waitSuspendedRows = New-Object System.Collections.Generic.List[object]

foreach ($line in $lines) {
    if ($line -notmatch "agc\.wait_suspended") {
        continue
    }

    $row = [ordered]@{
        Label              = ""
        Queue              = ""
        Submission         = ""
        CurrentValue       = ""
        ReferenceValue     = ""
        Compare            = ""
        ProducerSeq        = ""
        ProducerState      = ""
        ProducerQueue      = ""
        ProducerSubmission = ""
        ProducerNone       = $false
        Raw                = $line
    }

    if ($line -match "label=0x([0-9A-Fa-f]+)") { $row.Label = "0x" + $matches[1].ToUpperInvariant() }
    if ($line -match "queue=([^\s]+)") { $row.Queue = $matches[1] }
    if ($line -match "submission=([^\s]+)") { $row.Submission = $matches[1] }
    if ($line -match "value=0x([0-9A-Fa-f]+)") { $row.CurrentValue = "0x" + $matches[1].ToUpperInvariant() }
    if ($line -match "ref=0x([0-9A-Fa-f]+)") { $row.ReferenceValue = "0x" + $matches[1].ToUpperInvariant() }
    if ($line -match "cmp=([0-9]+)") { $row.Compare = $matches[1] }
    if ($line -match "producer_seq=([0-9]+)") { $row.ProducerSeq = $matches[1] }
    if ($line -match "producer_state=([^\s]+)") { $row.ProducerState = $matches[1] }
    if ($line -match "producer_queue=([^\s]+)") { $row.ProducerQueue = $matches[1] }
    if ($line -match "producer_submission=([^\s]+)") { $row.ProducerSubmission = $matches[1] }
    if ($line -match "producer=none-observed") { $row.ProducerNone = $true }

    $waitSuspendedRows.Add([pscustomobject]$row)
}

$waitSuspendedRows | Export-Csv -LiteralPath (Join-Path $outDir "reports\wait_suspended_all.csv") -NoTypeInformation -Encoding UTF8

$producerStateStats = @(
    $waitSuspendedRows |
    Group-Object ProducerState |
    ForEach-Object {
        [pscustomobject]@{
            ProducerState = if ([string]::IsNullOrWhiteSpace($_.Name)) { "(none)" } else { $_.Name }
            Count = $_.Count
        }
    } |
    Sort-Object Count -Descending
)
$producerStateStats | Export-Csv -LiteralPath (Join-Path $outDir "reports\producer_state_counts.csv") -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------------
# 4) DISPATCH_INDIRECT
# ---------------------------------------------------------------------------
Write-Step "Extracting indirect-dispatch diagnostics..."
Save-Lines -Lines (Get-Matches $lines "dispatch_indirect|dispatch_reject.*zero-dimension") -Path (Join-Path $outDir "reports\dispatch_indirect.txt")

# ---------------------------------------------------------------------------
# 5) GPU writeback / visibility
# ---------------------------------------------------------------------------
Write-Step "Extracting GPU visibility/writeback diagnostics..."
Save-Lines -Lines (Get-Matches $lines "vk\.global_writeback|vk\.queue_visibility|acquire_mem|release_mem|write_data") -Path (Join-Path $outDir "reports\gpu_visibility_writeback.txt")

# ---------------------------------------------------------------------------
# 6) Render / texture / framebuffer pipeline
# ---------------------------------------------------------------------------
Write-Step "Extracting render/texture/framebuffer diagnostics..."

$renderPattern = "agc\.rt_writer|agc\.rt_sampled|agc\.texture_source|agc\.texture_binding|agc\.shader_draw|vk\.offscreen_draw|agc\.display_buffer|vk\.flip_capture|Vulkan VideoOut presented guest frame"
Save-Lines -Lines (Get-Matches $lines $renderPattern) -Path (Join-Path $outDir "reports\render_pipeline.txt")

$zeroPattern = "nonzero64=0|probe_nonzero=0|writer=none|texels=0{4,}|changed_bytes=0|written_pages=0"
Save-Lines -Lines (Get-Matches $lines $zeroPattern) -Path (Join-Path $outDir "reports\zero_or_empty_gpu_resources.txt")

Save-Lines -Lines (Get-Matches $lines "agc\.rt_writer|agc\.rt_sampled") -Path (Join-Path $outDir "reports\render_targets.txt")
Save-Lines -Lines (Get-Matches $lines "agc\.texture_source|agc\.texture_binding") -Path (Join-Path $outDir "reports\textures.txt")

# ---------------------------------------------------------------------------
# 7) VideoOut
# ---------------------------------------------------------------------------
Write-Step "Extracting VideoOut/flip diagnostics..."
$videoPattern = "display_buffer|flip_capture|flip_retired|flip complete|presented guest frame|presented first frame|Vulkan VideoOut|swapchain|deviceLost|device lost"
Save-Lines -Lines (Get-Matches $lines $videoPattern) -Path (Join-Path $outDir "reports\videoout.txt")

# ---------------------------------------------------------------------------
# 8) Shader decoder/compiler errors
# ---------------------------------------------------------------------------
Write-Step "Extracting shader diagnostics..."
$shaderPattern = "unknown-ds|unknown-sopc|shader.*error|shader.*fail|shader_translate_miss|COMPAT\]\[SHADER|SPIR-V|spirv="
Save-Lines -Lines (Get-Matches $lines $shaderPattern) -Path (Join-Path $outDir "reports\shader_errors_and_compiles.txt")

# ---------------------------------------------------------------------------
# 9) PERF / warnings / fatal conditions / end-of-log
# ---------------------------------------------------------------------------
Write-Step "Extracting PERF and error diagnostics..."
Save-Lines -Lines (Get-Matches $lines "\[PERF\]\[GPUWAIT\]") -Path (Join-Path $outDir "reports\gpuwait_perf.txt")
Save-Lines -Lines (Get-Matches $lines "\[WARN\]|\[ERROR|FATAL|Exception|device.?lost") -Path (Join-Path $outDir "reports\warnings_errors.txt")
Save-Lines -Lines ($lines | Select-Object -Last 2500) -Path (Join-Path $outDir "reports\log_tail_2500.txt")

# Chronological compact trace containing all major synchronization + rendering events.
$chronologyPattern = "agc\.wait_suspended|agc\.queue_resumed|agc\.wait_producer_|agc\.dispatch_indirect|vk\.compute_dispatch|agc\.rt_writer|vk\.offscreen_draw|vk\.flip_capture|vk\.flip_retired|Vulkan VideoOut presented guest frame|vk\.global_writeback|device.?lost"
Save-Lines -Lines (Get-Matches $lines $chronologyPattern) -Path (Join-Path $outDir "reports\chronology_important.txt")

# ---------------------------------------------------------------------------
# 10) Repository/source snapshot relevant to the next patch
# ---------------------------------------------------------------------------
Write-Step "Collecting current source state..."

$targetSourceFiles = @(
    "src\SharpEmu.Libs\Agc\AgcExports.cs",
    "src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs"
)

$sourceManifest = New-Object System.Collections.Generic.List[string]

foreach ($rel in $targetSourceFiles) {
    $src = Join-Path $RepositoryRoot $rel
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path $outDir ("sources\" + $rel)
        $destParent = Split-Path -Parent $dest
        New-Item -ItemType Directory -Force -Path $destParent | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Force

        $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        $sourceManifest.Add("$hash  $rel")
    } else {
        $sourceManifest.Add("MISSING  $rel")
    }
}

# Discover all C# files that reference the synchronization/presentation symbols.
$srcRoot = Join-Path $RepositoryRoot "src"
$symbolMatches = New-Object System.Collections.Generic.List[string]
$discoveredFiles = @()

if (Test-Path -LiteralPath $srcRoot -PathType Container) {
    $csFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Filter "*.cs" -ErrorAction SilentlyContinue)

    if ($csFiles.Count -gt 0) {
        $found = @(
            $csFiles |
            Select-String -Pattern "GpuWaitRegistry|RecordProduced|SubmitOrderedGuestAction|wait_producer|WAIT_REG_MEM|dispatch_indirect|flip_capture|global_writeback" -CaseSensitive:$false -ErrorAction SilentlyContinue
        )

        foreach ($m in $found) {
            $relative = $m.Path.Substring($RepositoryRoot.Length).TrimStart('\','/')
            $symbolMatches.Add(("{0}:{1}: {2}" -f $relative, $m.LineNumber, $m.Line.Trim()))
        }

        $discoveredFiles = @($found | Select-Object -ExpandProperty Path -Unique)
    }
}

Save-Lines -Lines $symbolMatches -Path (Join-Path $outDir "repo_state\source_symbol_matches.txt")

# Include discovered source files too, capped to avoid pathological packages.
$maxDiscoveredSourceFiles = 40
$included = 0

foreach ($src in $discoveredFiles) {
    if ($included -ge $maxDiscoveredSourceFiles) {
        break
    }

    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        continue
    }

    $relative = $src.Substring($RepositoryRoot.Length).TrimStart('\','/')
    $dest = Join-Path $outDir ("sources\discovered\" + $relative)
    $destParent = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest -Force
    $included++
}

$sourceManifest.Add("")
$sourceManifest.Add("Discovered source files included: $included / $($discoveredFiles.Count)")
Save-Lines -Lines $sourceManifest -Path (Join-Path $outDir "repo_state\source_sha256.txt")

# ---------------------------------------------------------------------------
# 11) Git / .NET / machine state
# ---------------------------------------------------------------------------
Write-Step "Collecting repository/tool state..."

Push-Location $RepositoryRoot
try {
    try {
        (& git status --short 2>&1) | Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_status.txt") -Encoding UTF8
    } catch {
        "git status failed: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_status.txt") -Encoding UTF8
    }

    try {
        (& git diff -- "src/SharpEmu.Libs/Agc/AgcExports.cs" "src/SharpEmu.Libs/Agc/GpuWaitRegistry.cs" 2>&1) |
            Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_diff_agc.patch") -Encoding UTF8
    } catch {
        "git diff failed: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_diff_agc.patch") -Encoding UTF8
    }

    try {
        (& git rev-parse HEAD 2>&1) | Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_head.txt") -Encoding UTF8
    } catch {
        "git rev-parse failed: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $outDir "repo_state\git_head.txt") -Encoding UTF8
    }

    try {
        (& dotnet --info 2>&1) | Set-Content -LiteralPath (Join-Path $outDir "repo_state\dotnet_info.txt") -Encoding UTF8
    } catch {
        "dotnet --info failed: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $outDir "repo_state\dotnet_info.txt") -Encoding UTF8
    }
}
finally {
    Pop-Location
}

$envReport = @(
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
    "ComputerName: $env:COMPUTERNAME",
    "OS: $([Environment]::OSVersion.VersionString)",
    "ProcessArchitecture: $([Environment]::Is64BitProcess)",
    "PowerShell: $($PSVersionTable.PSVersion)",
    "RepositoryRoot: $RepositoryRoot",
    "LogPath: $resolvedLog",
    "SlowWaitThresholdMs: $SlowWaitThresholdMs"
)
Save-Lines -Lines $envReport -Path (Join-Path $outDir "repo_state\environment.txt")

# ---------------------------------------------------------------------------
# 12) Final summary and package manifest
# ---------------------------------------------------------------------------
$summary.Add("")
$summary.Add("TOP 25 SLOW WAITS")
foreach ($row in ($slowWaits | Select-Object -First 25)) {
    $summary.Add(("{0,12:N3} ms  {1,-20} {2,-18} sub={3}" -f $row.WaitMs, $row.Label, $row.Queue, $row.Submission))
}

$summary.Add("")
$summary.Add("NEXT-PATCH INPUTS INCLUDED")
$summary.Add("- full original runtime log")
$summary.Add("- all suspended waits + parsed CSV")
$summary.Add("- all queue resume durations + per-label statistics")
$summary.Add("- producer none/queued/completed traces")
$summary.Add("- producer scheduled/completed lifecycle")
$summary.Add("- WRITE_DATA / RELEASE_MEM timeline")
$summary.Add("- E00/E20 barrier timeline")
$summary.Add("- known problematic label timeline")
$summary.Add("- DISPATCH_INDIRECT trace")
$summary.Add("- GPU writeback / visibility")
$summary.Add("- render target / texture / zero-resource trace")
$summary.Add("- VideoOut / flip trace")
$summary.Add("- shader decoder/compiler errors")
$summary.Add("- GPUWAIT PERF lines")
$summary.Add("- current AgcExports.cs and GpuWaitRegistry.cs")
$summary.Add("- discovered source files referencing synchronization/presentation symbols")
$summary.Add("- git status/diff/HEAD and dotnet info")

Save-Lines -Lines $summary -Path (Join-Path $outDir "SUMMARY.txt")

$readme = @"
SharpEmu V2.4.1 Full Diagnostic Bundle
======================================

This bundle is designed to contain the complete input needed for the next
synchronization/render diagnosis without requiring multiple manual extraction rounds.

Primary file to send back:
    $([System.IO.Path]::GetFileName($zipPath))

Start with:
    SUMMARY.txt

Detailed reports are under:
    reports\

Current relevant source snapshot is under:
    sources\

Repository/tool state is under:
    repo_state\
"@
$readme | Set-Content -LiteralPath (Join-Path $outDir "README.txt") -Encoding UTF8

Write-Step "Creating ZIP..."

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash

Write-Host ""
Write-Host "============================================================"
Write-Host "[V241-FULL] SUCCESS"
Write-Host "Folder: $outDir"
Write-Host "ZIP:    $zipPath"
Write-Host "SHA256: $zipHash"
Write-Host "============================================================"
Write-Host ""
Write-Host "Envie apenas este ZIP para a analise:"
Write-Host $zipPath
