param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=Join-Path $Patches ("V76_3_18_1_PRE_SOURCE_$stamp")
$backupZip=Join-Path $Patches ("V76_3_18_1_PRE_SOURCE_$stamp.zip")
$buildLog=Join-Path $Patches ("V76_3_18_1_DEV_BUILD_$stamp.log")
$restoreLog=Join-Path $Patches ("V76_3_18_1_DEV_RESTORE_$stamp.log")

$bc=Join-Path $backupRoot $CliRel
New-Item -ItemType Directory -Force -Path (Split-Path $bc -Parent)|Out-Null
Copy-Item $CliPath $bc -Force
Compress-Archive -Path (Join-Path $backupRoot '*') -DestinationPath $backupZip -CompressionLevel Optimal -Force

function Restore-Source { Copy-Item $bc $CliPath -Force }

try {
    $c=Read-Utf8Preserve $CliPath
    $t=$c.Text

    if(-not$t.Contains('[V76.3.18.1][FAST_GPU_RESIDENT_PROFILE]')) {
        $needle='"[V76.3.18.0][RPCS3_QUEUE_MERGE] " +'
        $pos=$t.IndexOf($needle,[StringComparison]::Ordinal)
        if($pos-lt0){Fail 'V18 marker anchor ausente'}

        $start=$t.LastIndexOf('        Console.Error.WriteLine(',$pos,[StringComparison]::Ordinal)
        if($start-lt0){Fail 'V18 Console anchor ausente'}
        $nl=if($t.Contains("`r`n")){"`r`n"}else{"`n"}

        $block=@(
'        // V76.3.18.1 - FAST-GPU consolidated policy.',
'        // SAFE=1 restores conservative cache/feed limits while preserving the',
'        // V18 dual-queue architecture and all correctness contracts.',
'        var safeGpuProfileV763181 = string.Equals(',
'            Environment.GetEnvironmentVariable("SHARPEMU_V763181_SAFE"),',
'            "1",',
'            StringComparison.Ordinal);',
'',
'        // Physical queue architecture / async frontend.',
'        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
'        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");',
'        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");',
'        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
'        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");',
'',
'        // Queue/feed depth. Windows uses a dedicated render thread, so allow it',
'        // to consume a deeper ready-work window without a wall-clock cap.',
'        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");',
'        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");',
'        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");',
'        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");',
'        Set("SHARPEMU_RESERVED_HOST_LANES", "6");',
'        Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", safeGpuProfileV763181 ? "1024" : "4096");',
'        Set("SHARPEMU_RENDER_WORK_BUDGET_MS", "0");',
'        Set("SHARPEMU_RENDER_FOLLOWUP_WAIT_MS", safeGpuProfileV763181 ? "2" : "0");',
'        Set("SHARPEMU_RENDER_FOLLOWUP_BUDGET_MS", safeGpuProfileV763181 ? "24" : "48");',
'        Set("SHARPEMU_SUBMISSION_CAPACITY_WAIT_MS", safeGpuProfileV763181 ? "100" : "2");',
'',
'        // Resident pipeline/module working set. This reduces pipeline recreation',
'        // and keeps the hot shader/layout variants resident in driver/GPU state.',
'        Set("SHARPEMU_VK_PIPELINE_CACHE", "1");',
'        Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "512" : "1024");',
'        Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "256" : "1024");',
'        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_V11716", "1");',
'        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", safeGpuProfileV763181 ? "512" : "2048");',
'',
'        // VRAM/device-local residency. These are caches with existing eviction',
'        // and unsupported-device fallback; they do not pin all guest memory.',
'        Set("SHARPEMU_VK_DEVICE_LOCAL_GLOBALS", "1");',
'        Set("SHARPEMU_REBAR_GLOBAL_DIRECT_V1190", "1");',
'        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_V7633", "1");',
'        Set("SHARPEMU_RUNTIME_SCALAR_DIRECT_MAX_KB_V7633", "8");',
'        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");',
'        Set("SHARPEMU_VK_GUEST_BUFFER_CACHE_MB", safeGpuProfileV763181 ? "256" : "512");',
'        Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");',
'        Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeGpuProfileV763181 ? "3072" : "4096");',
'',
'        // Existing scheduler improvements remain authoritative.',
'        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
'        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");',
'        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");',
'        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");',
'        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");',
'        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");',
'        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");',
'        Set("SHARPEMU_NONBLOCKING_ORDERED_VISIBILITY", "1");',
'        Set("SHARPEMU_DEFERRED_FOLLOWUP_SPIN_BREAK", "1");',
'        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
'        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
'        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");',
'        Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");',
'',
'        Console.Error.WriteLine(',
'            "[V76.3.18.1][FAST_GPU_RESIDENT_PROFILE] " +',
'            $"mode={(safeGpuProfileV763181 ? "SAFE" : "FAST")} " +',
'            "dual_queue=capability async_agc=1 chain4=1 cb_pool=256 " +',
'            $"work_per_render={(safeGpuProfileV763181 ? 1024 : 4096)} " +',
'            $"capacity_wait_ms={(safeGpuProfileV763181 ? 100 : 2)} " +',
'            $"gfx_pipeline_cache={(safeGpuProfileV763181 ? 512 : 1024)} " +',
'            $"compute_pipeline_cache={(safeGpuProfileV763181 ? 256 : 1024)} " +',
'            $"descriptor_sets={(safeGpuProfileV763181 ? 512 : 2048)} " +',
'            $"device_buffer_mb={(safeGpuProfileV763181 ? 512 : 1024)} " +',
'            $"guest_buffer_mb={(safeGpuProfileV763181 ? 256 : 512)} " +',
'            $"sampled_image_mb={(safeGpuProfileV763181 ? 512 : 1024)} " +',
'            $"texture_cache_mb={(safeGpuProfileV763181 ? 3072 : 4096)}");',
''
        ) -join $nl

        $t=$t.Insert($start,$block)
        Write-Utf8Preserve $CliPath $t $c.HasBom
    }

    $check=[IO.File]::ReadAllText($CliPath)
    foreach($m in @(
        '[V76.3.18.1][FAST_GPU_RESIDENT_PROFILE]',
        'SHARPEMU_V763181_SAFE',
        'Set("SHARPEMU_MAX_GUEST_WORK_PER_RENDER", safeGpuProfileV763181 ? "1024" : "4096");',
        'Set("SHARPEMU_SUBMISSION_CAPACITY_WAIT_MS", safeGpuProfileV763181 ? "100" : "2");',
        'Set("SHARPEMU_VK_GRAPHICS_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "512" : "1024");',
        'Set("SHARPEMU_VK_COMPUTE_PIPELINE_CACHE_MAX", safeGpuProfileV763181 ? "256" : "1024");',
        'Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", safeGpuProfileV763181 ? "512" : "2048");',
        'Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");',
        'Set("SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB", safeGpuProfileV763181 ? "512" : "1024");',
        'Set("SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB", safeGpuProfileV763181 ? "3072" : "4096");',
        'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
        'Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");',
        'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
        'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");'
    )){
        if(-not$check.Contains($m)){Fail "post-apply contract ausente: $m"}
    }

    Push-Location $Repo
    try {
        & dotnet restore $Project -r win-x64 *>&1|Tee-Object -FilePath $restoreLog
        if($LASTEXITCODE-ne0){throw "restore falhou exit=$LASTEXITCODE"}
        & dotnet build $Project -c Debug -r win-x64 --no-restore *>&1|Tee-Object -FilePath $buildLog
        if($LASTEXITCODE-ne0){throw "build Debug falhou exit=$LASTEXITCODE"}
    } finally { Pop-Location }

    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug"
    Write-Host "[$Tag] cli_sha256=$(Get-HashLower $CliPath)"
    Write-Host "[$Tag] presenter_sha256=$(Get-HashLower $PresenterPath)"
    Write-Host "[$Tag] agc_sha256=$(Get-HashLower $AgcPath)"
    Write-Host "[$Tag] backup=$backupZip"
    Write-Host "[$Tag] build_log=$buildLog"
}
catch {
    Restore-Source
    Write-Host "[$Tag] rollback=completed backup=$backupZip" -ForegroundColor Yellow
    throw
}
finally {
    if(Test-Path $backupRoot){Remove-Item $backupRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
