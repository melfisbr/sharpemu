param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin",
    [switch]$ForceNewRun
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$text=[System.IO.File]::ReadAllText($presenter)

foreach($marker in @(
    "SHARPEMU_V74_0_8_STANDALONE_TEXTURE_CACHE_BUDGET",
    "SHARPEMU_V74_0_8_TEXTURE_RESOURCE_RESIDENCY",
    "SHARPEMU_V74_0_8_1_FULL_RUNTIME_MEMORY_TRUTH",
    "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET",
    "SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE"
)){
    if(-not $text.Contains($marker)){
        throw "[V74.0.8.2] Diagnostic refused; missing marker: $marker"
    }
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.8.2] EBOOT missing: $Eboot"
}

$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){
    throw "[V74.0.8.2] Wrong EBOOT. expected=$expected actual=$actual"
}

function Get-MaxCsvMetric {
    param(
        [string]$Path,
        [string]$Column
    )

    if(-not [System.IO.File]::Exists($Path)){
        return 0.0
    }

    $rows=@(Import-Csv -LiteralPath $Path -Delimiter ';')
    $max=0.0

    foreach($row in $rows){
        $property=$row.PSObject.Properties[$Column]
        if($null-eq$property){continue}

        $raw=[string]$property.Value
        $value=0.0

        if([double]::TryParse(
                $raw,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$value) -or
           [double]::TryParse(
                $raw,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::CurrentCulture,
                [ref]$value)){
            if($value-gt$max){$max=$value}
        }
    }

    return $max
}

function Resolve-LatestIncompleteTruthFolder {
    param([string]$Root)

    $folders=@(
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object{
            $_.Name -like "SharpEmu_V74_0_8_1_FULL_RUNTIME_TRUTH_RESULT_*"
        } |
        Sort-Object LastWriteTime -Descending
    )

    foreach($folder in $folders){
        $stderrPath=[System.IO.Path]::Combine($folder.FullName,"stderr.log")
        $processPath=[System.IO.Path]::Combine($folder.FullName,"PROCESS_OS_TRUTH.csv")
        $summaryPath=[System.IO.Path]::Combine($folder.FullName,"SUMMARY.txt")

        if([System.IO.File]::Exists($stderrPath) -and
           [System.IO.File]::Exists($processPath)){
            if(-not [System.IO.File]::Exists($summaryPath)){
                return $folder.FullName
            }

            $summary=[System.IO.File]::ReadAllText($summaryPath)
            if($summary.IndexOf(
                    "version=74.0.8.1",
                    [System.StringComparison]::Ordinal)-lt 0){
                return $folder.FullName
            }
        }
    }

    return $null
}

function Finalize-ExistingTruthFolder {
    param(
        [string]$ExistingOut,
        [string]$PresenterPath,
        [string]$EbootSha
    )

    $out=$ExistingOut
    $stdout=[System.IO.Path]::Combine($out,"stdout.log")
    $stderr=[System.IO.Path]::Combine($out,"stderr.log")
    $processCsv=[System.IO.Path]::Combine($out,"PROCESS_OS_TRUTH.csv")
    $gpuCsv=[System.IO.Path]::Combine($out,"GPU_OS_TRUTH.csv")
    $systemCsv=[System.IO.Path]::Combine($out,"SYSTEM_MEMORY_TRUTH.csv")
    $nvidiaCsv=[System.IO.Path]::Combine($out,"NVIDIA_GPU_TRUTH.csv")

    $maxWorking=[int64]([Math]::Round((Get-MaxCsvMetric $processCsv "working_mb")*1MB))
    $maxPrivate=[int64]([Math]::Round((Get-MaxCsvMetric $processCsv "private_mb")*1MB))
    $maxGpuDedicated=[int64]([Math]::Round((Get-MaxCsvMetric $gpuCsv "dedicated_mb")*1MB))
    $maxGpuShared=[int64]([Math]::Round((Get-MaxCsvMetric $gpuCsv "shared_mb")*1MB))
    $maxSystemCommit=[int64]([Math]::Round((Get-MaxCsvMetric $systemCsv "commit_mb")*1MB))

    $memoryPressureStop=$false
    $exitCode="completed-before-finalizer-repair"

$all=New-Object System.Collections.Generic.List[string]
foreach($file in @($stdout,$stderr)){
    if([System.IO.File]::Exists($file)){
        foreach($line in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)){
            $all.Add([string]$line)
        }
    }
}

function Hits([string]$Pattern){
    return @($all|Where-Object{$_ -match $Pattern})
}

function MaxMetric([string[]]$Lines,[string]$Name){
    $max=[int64]0
    foreach($line in $Lines){
        if($line -match ([regex]::Escape($Name)+'=(\d+)')){
            $value=[int64]$Matches[1]
            if($value-gt$max){$max=$value}
        }
    }
    return $max
}

$mem=@(Hits "\[V74\.0\.8\.1\]\[MEM\]")
$texAdd=@(Hits "\[V74\.0\.8\]\[TEX_CACHE\] add")
$texTrim=@(Hits "\[V74\.0\.8\]\[TEX_CACHE\] trim")
$gimg=@(Hits "\[V74\.0\.7\]\[GIMG_CACHE\]")
$computeFails=@(Hits "Vulkan compute dispatch failed")
$computeNull=@(Hits "compute texture resource remained null")
$events=@(Hits "\[V17\]\[EVENT_FASTPATH\]")
$failfast=@(Hits "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506")
$natural=@(Hits "bink2\.natural_guest_movie_observed")
$computeYuv=@(Hits "bink2\.compute_yuv_binding")
$dcc=@(Hits "\[V74\.0\.4\]\[DCC\]")
$large=@(Hits "\[V74\.0\.4\]\[ALLOC\]")
$direct=@(Hits "\[LOADER\]\[TRACE\] allocate_(?:main_)?direct")
$vmem=@(Hits "Allocated .*0x|Mapped segment:|Backed fixed range gap:")
$lazy=@(Hits "lazy|Lazy")
$gpuWait=@(Hits "\[GPU-WAIT-PROFILE\]|gpu_wait_profile|wait.*suspension")
$threadSnapshots=@(Hits "guest_thread\.snapshot")
$fps=@(Hits "fps|FPS")
$deviceLost=@(Hits "VK_ERROR_DEVICE_LOST|DeviceLostException|deviceLost=True")
$shaderError=@(Hits "shader.*failed|Unsupported.*opcode|unsupported.*opcode|SPIR-V.*fail")
$mainLoop=@(Hits "Starting main loop:")
$firstFrame=@(Hits "Vulkan VideoOut presented first frame")
$uiRead=@(Hits "uistartmenu|uifrontend|subscreen_overlay_backing")
$movie=@(Hits "ps_studios_logo|attract_movie|natural_guest_movie|first_frame_primed")

# Direct memory total requested bytes.
$directRequested=[uint64]0
foreach($line in $direct){
    if($line -match 'len=0x([0-9A-Fa-f]+)'){
        try{
            $directRequested += [Convert]::ToUInt64($Matches[1],16)
        }catch{}
    }
}

# Max raw EVENT_FASTPATH n.
$maxEvent=0
foreach($line in $events){
    if($line -match '\bn=(\d+)'){
        $n=[int]$Matches[1]
        if($n-gt$maxEvent){$maxEvent=$n}
    }
}

$maxGc=MaxMetric $mem "gc_mb"
$maxHeap=MaxMetric $mem "heap_mb"
$maxFrag=MaxMetric $mem "frag_mb"
$maxAlloc=MaxMetric $mem "alloc2s_mb"
$maxTex=MaxMetric $mem "tex_cache_mb"
$maxDeferred=MaxMetric $mem "tex_deferred_mb"
$maxSampled=MaxMetric $mem "sampled_mb"
$maxGuestBuffer=MaxMetric $mem "guest_buffer_mb"
$maxPendingImg=MaxMetric $mem "pending_img_mb"
$maxPending=MaxMetric $mem "pending"
$maxAbandoned=MaxMetric $mem "abandoned"
$maxBatch=MaxMetric $mem "batch_resources"
$maxVirtual=MaxMetric $mem "virtual_mb"

$class="full-runtime-truth-captured"
if($failfast.Count-gt 0){
    $class="clr-failfast-regression"
}elseif($deviceLost.Count-gt 0){
    $class="device-lost"
}elseif($computeFails.Count-gt 0 -or $computeNull.Count-gt 0){
    $class="compute-regression"
}elseif($memoryPressureStop){
    $class="memory-pressure-with-full-truth"
}elseif($natural.Count-gt 0 -and $computeYuv.Count-gt 0){
    $class="natural-bink-compute-yuv-active"
}

@(
    $all |
    Where-Object{
        $_ -match "\[V74\.0\.8\.1\]\[MEM\]|" +
                  "\[V74\.0\.8\]\[TEX_CACHE\]|" +
                  "\[V74\.0\.7\]\[GIMG_CACHE\]|" +
                  "\[V74\.0\.4\]\[(?:DCC|ALLOC)\]|" +
                  "\[GPU-WAIT-PROFILE\]|" +
                  "guest_thread\.snapshot|" +
                  "allocate_(?:main_)?direct|" +
                  "Vulkan compute dispatch failed|" +
                  "compute texture resource remained null|" +
                  "\[V17\]\[EVENT_FASTPATH\]|" +
                  "Vulkan VideoOut presented first frame|" +
                  "Starting main loop:|" +
                  "bink2\.natural_guest_movie_observed|" +
                  "bink2\.compute_yuv_binding|" +
                  "uistartmenu|uifrontend|subscreen_overlay_backing"
    }
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"FULL_RUNTIME_TIMELINE.txt")) `
    -Encoding UTF8

@(
    "version=74.0.8.2",
    "classification=$class",
    "exit_code=$exitCode",
    "memory_pressure_stop=$memoryPressureStop",
    "",
    "[functional]",
    "main_loop_hits=$($mainLoop.Count)",
    "first_frame_hits=$($firstFrame.Count)",
    "max_event_fastpath_n=$maxEvent",
    "compute_dispatch_fail_hits=$($computeFails.Count)",
    "compute_null_invariant_hits=$($computeNull.Count)",
    "clr_failfast_hits=$($failfast.Count)",
    "device_lost_hits=$($deviceLost.Count)",
    "shader_error_hits=$($shaderError.Count)",
    "natural_guest_movie_hits=$($natural.Count)",
    "compute_yuv_binding_hits=$($computeYuv.Count)",
    "ui_resource_log_hits=$($uiRead.Count)",
    "movie_lifecycle_log_hits=$($movie.Count)",
    "",
    "[memory-internal]",
    "mem_telemetry_lines=$($mem.Count)",
    "max_gc_mb=$maxGc",
    "max_gc_heap_mb=$maxHeap",
    "max_gc_fragmented_mb=$maxFrag",
    "max_alloc_per_2s_mb=$maxAlloc",
    "max_texture_cache_mb=$maxTex",
    "max_texture_deferred_mb=$maxDeferred",
    "texture_cache_add_logs=$($texAdd.Count)",
    "texture_cache_trim_logs=$($texTrim.Count)",
    "max_sampled_guest_image_mb=$maxSampled",
    "guest_image_cache_logs=$($gimg.Count)",
    "max_guest_buffer_mb=$maxGuestBuffer",
    "max_pending_guest_image_data_mb=$maxPendingImg",
    "max_pending_submissions=$maxPending",
    "max_abandoned_submissions=$maxAbandoned",
    "max_batch_resources=$maxBatch",
    "max_process_virtual_mb_internal=$maxVirtual",
    "",
    "[guest-memory]",
    "direct_memory_allocation_calls=$($direct.Count)",
    "direct_memory_requested_mb=$([Math]::Round($directRequested/1MB,1))",
    "vmem_mapping_log_hits=$($vmem.Count)",
    "lazy_commit_log_hits=$($lazy.Count)",
    "",
    "[scheduler-gpu]",
    "guest_thread_snapshot_lines=$($threadSnapshots.Count)",
    "gpu_wait_profile_lines=$($gpuWait.Count)",
    "video_fps_log_hits=$($fps.Count)",
    "",
    "[texture-provenance]",
    "dcc_suppression_hits=$($dcc.Count)",
    "large_cpu_snapshot_hits=$($large.Count)",
    "",
    "[os-peak]",
    ("peak_process_tree_working_mb={0:F1}" -f ($maxWorking/1MB)),
    ("peak_process_tree_private_mb={0:F1}" -f ($maxPrivate/1MB)),
    ("peak_gpu_dedicated_mb={0:F1}" -f ($maxGpuDedicated/1MB)),
    ("peak_gpu_shared_mb={0:F1}" -f ($maxGpuShared/1MB)),
    ("peak_system_commit_mb={0:F1}" -f ($maxSystemCommit/1MB)),
    "",
    "CSV_FILES:",
    "PROCESS_OS_TRUTH.csv",
    "GPU_OS_TRUTH.csv",
    "SYSTEM_MEMORY_TRUTH.csv",
    "NVIDIA_GPU_TRUTH.csv",
    "",
    "Interpretation rule:",
    "- GC high -> managed allocation producer.",
    "- tex_cache/deferred high -> Vulkan image lifetime/fence.",
    "- GPU dedicated/shared high with low internal caches -> other Vulkan/native allocation.",
    "- process private high with GC/GPU caches low -> guest direct-memory/native commit.",
    "- pending/batch/timeline divergence -> GPU submission/back-pressure.",
    "- all memory stable but black -> functional render/provenance/UI blocker."
) |
Set-Content `
    -LiteralPath ([System.IO.Path]::Combine($out,"SUMMARY.txt")) `
    -Encoding UTF8

# Source + environment truth.
$srcDir=[System.IO.Path]::Combine($out,"sources")
[System.IO.Directory]::CreateDirectory($srcDir)|Out-Null
Copy-Item -LiteralPath $PresenterPath `
    -Destination ([System.IO.Path]::Combine($srcDir,"VulkanVideoPresenter.cs")) -Force

@(
    "V74.0.8.2 finalized an existing V74.0.8.1 collection.",
    "The original run configuration is documented by the package and console output.",
    "Current process environment is intentionally not substituted for historical run state."
) | Set-Content -LiteralPath (
    [System.IO.Path]::Combine($out,"SHARPEMU_ENV_EFFECTIVE.txt")) -Encoding UTF8

$tail=[System.IO.Path]::Combine($out,"RUNTIME_TAIL.txt")
if([System.IO.File]::Exists($stderr)){
    $lines=@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)
    if($lines.Count-gt 0){
        $start=[Math]::Max(0,$lines.Count-1200)
        @($lines[$start..($lines.Count-1)]) |
            Set-Content -LiteralPath $tail -Encoding UTF8
    }
}

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive `
    -Path ([System.IO.Path]::Combine($out,"*")) `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[V74.0.8.2] RESULT ZIP: $zip"
Write-Host "[V74.0.8.2] classification=$class"
Write-Host "[V74.0.8.2] gc_max=${maxGc}MB tex_max=${maxTex}MB deferred_max=${maxDeferred}MB guestbuf_max=${maxGuestBuffer}MB pending_img_max=${maxPendingImg}MB gpu_ded_peak=$([Math]::Round($maxGpuDedicated/1MB))MB direct_requested=$([Math]::Round($directRequested/1MB))MB event_n=$maxEvent compute_fail=$($computeFails.Count) failfast=$($failfast.Count) natural=$($natural.Count)"

}

$existing=$null
if(-not $ForceNewRun){
    $existing=Resolve-LatestIncompleteTruthFolder $root
}

if($null-ne$existing){
    Write-Host "[V74.0.8.2] Found existing completed V74.0.8.1 collection:"
    Write-Host "[V74.0.8.2] $existing"
    Write-Host "[V74.0.8.2] No 120-second rerun is needed. Finalizing existing telemetry."
    Finalize-ExistingTruthFolder `
        -ExistingOut $existing `
        -PresenterPath $presenter `
        -EbootSha $actual
    exit 0
}

Write-Host "[V74.0.8.2] No incomplete V74.0.8.1 collection found; starting one fresh comprehensive run."

& (Join-Path $PSScriptRoot "run_fresh_truth.ps1") `
    -RepositoryRoot $root `
    -Eboot $Eboot

exit $LASTEXITCODE
