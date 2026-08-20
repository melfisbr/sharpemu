param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. "$PSScriptRoot\common.ps1"

$repo = Resolve-RepoV74056362 $RepositoryRoot
[void](Assert-EbootV74056362 $Eboot)
Assert-CumulativeV74056362 $repo

$agcState = Get-AgcStateV74056362 $repo
$presenterState = Get-PresenterStateV74056362 $repo

if ($agcState.State -ne 'Applied') {
    throw ('{0} run RUN_3 first: AGC state={1}' -f $script:Tag, $agcState.State)
}

if ($presenterState.State -ne 'Satisfied') {
    throw ('{0} run RUN_3 first: Presenter state={1}' -f $script:Tag, $presenterState.State)
}

$exe = Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$patches = Join-Path $repo 'Patches'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$captureDir = Join-Path $patches (
    'SharpEmu_V74_0_56_36_2_GBUFFER_LIGHTING_RESULT_' + $stamp
)

New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

$stdout = Join-Path $captureDir 'stdout.log'
$stderr = Join-Path $captureDir 'stderr.log'

[IO.File]::WriteAllText($stdout, '')
[IO.File]::WriteAllText($stderr, '')

$profile = [ordered]@{
    'SHARPEMU_DS_GBUFFER_LIGHTING_CONTRACT' = '1'
    'SHARPEMU_DCC_FASTCLEAR_IMMEDIATE_MATERIALIZE' = '1'
    'SHARPEMU_TRACE_GBUFFER_LIGHTING' = '1'

    'SHARPEMU_DEDICATED_WAIT_DRAIN' = '0'
    'SHARPEMU_AGC_GATE_OWNER_WAIT_DRAIN' = '0'
    'SHARPEMU_TRACE_RDNA2_SRD_COMPRESSION' = '0'

    'SHARPEMU_AGC_METADATA_FB_CLEAR' = '0'
    'SHARPEMU_SCENE_OFFSCREEN_METADATA_MATERIALIZATION' = '0'
    'SHARPEMU_TRACE_SCENE_PIPELINE_GAPS' = '0'

    'SHARPEMU_DCC_PRODUCER_HISTORY_MS' = '10000'
    'SHARPEMU_DCC_ALIAS_HISTORY_MS' = '10000'
    'SHARPEMU_TRACE_DCC_ALIAS' = '0'
    'SHARPEMU_SAMPLER_IMAGE_ALIAS' = '1'

    'SHARPEMU_PRODUCERLESS_TWO_STAGE_VISIBILITY' = '0'
    'SHARPEMU_GPU_WAIT_GLOBAL_VISIBILITY_PROBE' = '0'
    'SHARPEMU_DEMONS_DIRECT_SCANOUT_WRITER' = '0'
    'SHARPEMU_REPLAY_TARGETLESS_COMPOSITES' = '0'
    'SHARPEMU_APR_ASSET_READAHEAD' = '0'
    'SHARPEMU_DEMONS_PLAYGO_CHUNKS_24_31' = '0'
    'SHARPEMU_LOG_PLAYGO' = '0'

    'SHARPEMU_GPU_INDIRECT_DIMS_GLOBAL_VISIBILITY' = '1'
    'SHARPEMU_KYTY_ZERO_INDIRECT_NOOP' = '0'
    'SHARPEMU_GPU_DETILE' = '1'
    'SHARPEMU_LOG_GPU_DETILE' = '0'

    'SHARPEMU_APP0_METADATA_HOTPATH' = '1'
    'SHARPEMU_TRACE_APP0_METADATA_HOTPATH' = '0'
    'SHARPEMU_DEMON_BPE_INVALID_LIST_HEAD_RECOVERY' = '1'

    'SHARPEMU_GPU_MAINTENANCE_THROTTLE' = '1'
    'SHARPEMU_GPU_MAINTENANCE_INTERVAL_MS' = '16'
    'SHARPEMU_PRESERVE_PAYLOAD_BATCH' = '0'
    'SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE' = '0'
    'SHARPEMU_VK_MAX_INFLIGHT_SUBMISSIONS' = '8'
    'SHARPEMU_KYTY_EMERGENCY_INFLIGHT_SUBMISSIONS' = '8'
    'SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE' = '1'
    'SHARPEMU_ADAPTIVE_UNIFIED_COMPUTE_MAX_GROUPS' = '65536'
    'SHARPEMU_KYTY_CAPACITY_BACKOFF' = '1'
    'SHARPEMU_KYTY_CAPACITY_PROBE_US' = '100'
    'SHARPEMU_DEFERRED_FOLLOWUP_SPIN_BREAK' = '1'
    'SHARPEMU_COMPUTE_SHARED_BATCH' = '1'
    'SHARPEMU_DISABLED_ACQUIRE_NOFLUSH' = '1'
    'SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST' = '8'
    'SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION' = '1'
    'SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY' = '1'
    'SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY' = '1'
    'SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST' = '0'
    'SHARPEMU_WATCHED_WRITE_CONTROL_LANE' = '1'
    'SHARPEMU_KYTY_INLINE_WRITE_DATA' = '0'
    'SHARPEMU_KYTY_PM4_BLOCKED_SCHEDULER' = '0'
    'SHARPEMU_KYTY_NATIVE_WAIT_SUSPEND' = '0'
    'SHARPEMU_KYTY_COMPUTE_SUBMISSION_FAIRNESS' = '0'
    'SHARPEMU_KYTY_UNIFIED_COMPUTE_SUBMISSION' = '0'
    'SHARPEMU_KYTY_PRESENTATION_FIRST' = '0'
    'SHARPEMU_WRITE_DATA_PACKET_POSITION' = '0'
    'SHARPEMU_RENDER_SCALE' = '1.0'

    'DOTNET_GCConserveMemory' = '5'
    'COMPlus_GCConserveMemory' = '5'
    'DOTNET_gcServer' = '0'
    'COMPlus_gcServer' = '0'
    'DOTNET_GCRetainVM' = '0'
    'COMPlus_GCRetainVM' = '0'
    'SHARPEMU_GUEST_DATA_POOL_MB' = '96'
    'SHARPEMU_GUEST_DATA_POOL_MAX_ARRAY_MB' = '16'
    'SHARPEMU_GUEST_DATA_POOL_BUCKET' = '4'
    'SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS' = '10000'
    'SHARPEMU_PTHREAD_IMPORT_HOTPATH' = '1'
    'SHARPEMU_PTHREAD_IDENTITY_TLS_HOTPATH' = '1'
    'SHARPEMU_PTHREAD_MUTEX_IMPORT_HOTPATH' = '1'
    'SHARPEMU_ALIGNED_DWORD_BUFFER_FASTPATH' = '1'
    'SHARPEMU_ALIGNED_DWORD_BUFFER_FASTPATH_TARGET_ONLY' = '1'
    'SHARPEMU_NONBLOCKING_GLOBAL_REFRESH' = '1'

    'SHARPEMU_BINK_AUTO_BOOT' = '0'
    'SHARPEMU_BINK_MODE' = 'rad'
    'SHARPEMU_BINK_STARTUP_COMPLETION_SHIM' = '0'
    'SHARPEMU_BINK_RAD_GUEST_COMPLETION_HANDOFF' = '1'

    'SHARPEMU_PROFILE_RENDER' = '1'
    'SHARPEMU_PROFILE_ORDERED_ACTION' = '0'
    'SHARPEMU_PROFILE_RENDER_REPORT_S' = '5'

    'SHARPEMU_TRACE_APR_ASSET_READS' = '0'
    'SHARPEMU_TRACE_IMAGE_DIMENSIONS' = '0'
    'SHARPEMU_TRACE_TEXTURE_TYPES' = '0'
    'SHARPEMU_TRACE_PRIMITIVE_PIPELINE' = '0'
    'SHARPEMU_CONTENT_ROUTE_TRACE' = '0'
    'SHARPEMU_TRACE_SCANOUT_LINEAGE' = '0'
    'SHARPEMU_LOG_AJM_SUMMARY' = '0'
    'SHARPEMU_LOG_AJM' = '0'
    'SHARPEMU_LOG_AUDIO_OUT' = '0'

    'SHARPEMU_TRACE_DRAW_PHASES' = '0'
    'SHARPEMU_TRACE_DRAW_RESOURCE_PHASES' = '0'
    'SHARPEMU_TRACE_COMPUTE_PHASES' = '0'
    'SHARPEMU_TRACE_SHADER_PIPELINE_TIMING' = '0'
    'SHARPEMU_TRACE_SLOW_RENDER_WORK' = '0'
    'SHARPEMU_TRACE_PRESENT_CADENCE' = '0'
    'SHARPEMU_TRACE_GPU_SUBMISSION_LATENCY' = '0'

    'SHARPEMU_LOG_IO' = '0'
    'SHARPEMU_LOG_OPEN' = '0'
    'SHARPEMU_TRACE_MOVIE_IO' = '0'
    'SHARPEMU_LOG_ALL_IMPORTS' = '0'
    'SHARPEMU_LOG_IMPORT_PERIODIC' = '0'
    'SHARPEMU_LOG_GUEST_THREADS' = '0'
    'SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS' = '0'
    'SHARPEMU_LOG_EVENT_FLAG' = '0'
    'SHARPEMU_STALL_WATCHDOG_SECONDS' = '0'
    'SHARPEMU_PERIODIC_SNAPSHOT_SECONDS' = '0'
    'SHARPEMU_ENTRY_THREAD_SNAPSHOT_SECONDS' = '0'
    'SHARPEMU_TRACE_FRONTEND_EVENT_FLAG' = '0'
    'SHARPEMU_TRACE_PS5SYNC_EVENT' = '0'
    'SHARPEMU_PS5SYNC_SNAPSHOT_SECONDS' = '0'
    'SHARPEMU_PS5SYNC_NATIVE_SNAPSHOT_SECONDS' = '0'
    'SHARPEMU_TRACE_RWLOCK_UNLOCK_WAKE_GATE' = '0'
}

$old = @{}
$names = @($profile.Keys) + @(
    'SHARPEMU_BINK_BOOT_SEQUENCE',
    'SHARPEMU_LOG_DISASM'
)

foreach ($name in ($names | Select-Object -Unique)) {
    $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    foreach ($name in $profile.Keys) {
        [Environment]::SetEnvironmentVariable(
            $name,
            [string]$profile[$name],
            'Process'
        )
    }

    [Environment]::SetEnvironmentVariable(
        'SHARPEMU_BINK_BOOT_SEQUENCE',
        $null,
        'Process'
    )

    [Environment]::SetEnvironmentVariable(
        'SHARPEMU_LOG_DISASM',
        $null,
        'Process'
    )

    @(
        $profile.GetEnumerator() |
            ForEach-Object {
                '{0}={1}' -f $_.Key, $_.Value
            }
    ) | Set-Content `
        -LiteralPath (Join-Path $captureDir 'PROFILE.txt') `
        -Encoding UTF8

    Write-Host ('{0} Starting structural-adapt G-buffer / lighting test.' -f $script:Tag) -ForegroundColor Cyan
    Write-Host ('{0} Exact PS 0x448639500 MRT slot1 recovery: ON.' -f $script:Tag)
    Write-Host ('{0} V56.35 0x45D550000 fast-clear materialization: ON.' -f $script:Tag)
    Write-Host ('{0} Presenter initialized-image guard: satisfied.' -f $script:Tag)
    Write-Host ('{0} V71/V72 waiter-drain experiments: OFF.' -f $script:Tag)
    Write-Host ('{0} No automatic timeout/kill. Result/logs: {1}' -f $script:Tag, $patches)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $process = $null
    $exitCode = 'unknown'

    try {
        $process = Start-Process `
            -FilePath $exe `
            -ArgumentList ('"' + $Eboot + '"') `
            -WorkingDirectory (Split-Path -Parent $exe) `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru

        $process.WaitForExit()
        $process.Refresh()

        if ($process.HasExited) {
            $exitCode = [string]$process.ExitCode
        }
    }
    finally {
        $sw.Stop()

        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    try {
        & "$PSScriptRoot\analyze_capture.ps1" `
            -CaptureDirectory $captureDir `
            -WallSeconds $sw.Elapsed.TotalSeconds `
            -ExitCode $exitCode
    }
    catch {
        [IO.File]::WriteAllText(
            (Join-Path $captureDir 'ANALYZER_ERROR.txt'),
            ($_ | Out-String)
        )

        @(
            'SharpEmu V74.0.56.36.2 ANALYZER FALLBACK',
            ('wall_seconds={0}' -f [Math]::Round($sw.Elapsed.TotalSeconds, 3)),
            ('exit_code={0}' -f $exitCode),
            'analysis_failed=1',
            'stdout_stderr_preserved=1'
        ) | Set-Content `
            -LiteralPath (Join-Path $captureDir 'SUMMARY.txt') `
            -Encoding UTF8
    }

    $resultZip = Join-Path $patches (
        'SharpEmu_V74_0_56_36_2_GBUFFER_LIGHTING_RESULT_' +
        $stamp +
        '.zip'
    )

    if (Test-Path -LiteralPath $resultZip -PathType Leaf) {
        Remove-Item -LiteralPath $resultZip -Force
    }

    Compress-Archive `
        -Path (Join-Path $captureDir '*') `
        -DestinationPath $resultZip `
        -CompressionLevel Optimal

    Write-Host ('{0} RESULT ZIP: {1}' -f $script:Tag, $resultZip) -ForegroundColor Green
}
finally {
    foreach ($name in $old.Keys) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $old[$name],
            'Process'
        )
    }
}
