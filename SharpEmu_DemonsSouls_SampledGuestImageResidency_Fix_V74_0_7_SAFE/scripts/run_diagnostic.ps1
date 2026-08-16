param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root

$text=[System.IO.File]::ReadAllText($presenter)
if(-not $text.Contains(
        "SHARPEMU_V74_0_7_SAMPLED_GUEST_IMAGE_RESIDENCY_BUDGET") -or
   -not $text.Contains(
        "SHARPEMU_V74_0_7_SWAPCHAIN_TEXTURE_STAGING_RETIRE")){
    throw "[V74.0.7] Diagnostic refused: V74.0.7 is not installed."
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.7] EBOOT missing: $Eboot"
}

$expected=
    "22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"

$actual=(
    Get-FileHash -LiteralPath $Eboot -Algorithm SHA256
).Hash.ToUpperInvariant()

if($actual-ne$expected){
    throw "[V74.0.7] Wrong EBOOT. expected=$expected actual=$actual"
}

$dll=[System.IO.Path]::Combine(
    $root,
    "artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")

if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.7] SharpEmu.dll missing: $dll"
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,
    "SharpEmu_V74_0_7_RESIDENCY_RESULT_$stamp")

[System.IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$memory=[System.IO.Path]::Combine($out,"PROCESS_TREE_MEMORY.csv")

"elapsed_s;process_count;working_set_mb;private_mb;cpu_seconds" |
    Set-Content -LiteralPath $memory -Encoding ASCII

$variables=@(
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT",
    "SHARPEMU_LOG_AGC_SHADER",
    "SHARPEMU_TRACE_DCC_ALIAS",
    "SHARPEMU_TRACE_SCANOUT_LINEAGE",
    "SHARPEMU_BINK_INTRO_HARNESS",
    "SHARPEMU_TRACE_MOVIE_IO",
    "SHARPEMU_RENDER_CHECKPOINTS",
    "SHARPEMU_DISABLE_NATIVE_GUEST_WORKERS",
    "SHARPEMU_VEH_HOST_MANAGED",
    "SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB"
)

$old=@{}
foreach($name in $variables){
    $old[$name]=[Environment]::GetEnvironmentVariable(
        $name,
        [EnvironmentVariableTarget]::Process)
}

function Get-SharpEmuSnapshot {
    param([int]$LauncherProcessId)

    $all=@(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    )

    $ids=New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$ids.Add($LauncherProcessId)

    $changed=$true
    while($changed){
        $changed=$false

        foreach($wp in $all){
            $processIdValue=[int]$wp.ProcessId
            $parentIdValue=[int]$wp.ParentProcessId

            if($ids.Contains($parentIdValue) -and
               -not $ids.Contains($processIdValue)){
                [void]$ids.Add($processIdValue)
                $changed=$true
            }
        }
    }

    foreach($wp in $all){
        if($null-ne$wp.CommandLine -and
           $wp.CommandLine.IndexOf(
               "SharpEmu.dll",
               [System.StringComparison]::OrdinalIgnoreCase)-ge 0){
            [void]$ids.Add([int]$wp.ProcessId)
        }
    }

    $working=0L
    $private=0L
    $cpu=0.0
    $alive=New-Object 'System.Collections.Generic.List[int]'

    foreach($processIdValue in $ids){
        try{
            $gp=Get-Process -Id $processIdValue -ErrorAction Stop
            $working += [int64]$gp.WorkingSet64
            $private += [int64]$gp.PrivateMemorySize64
            $cpu += [double]$gp.CPU
            $alive.Add($processIdValue)
        } catch {
        }
    }

    [pscustomobject]@{
        Count=$alive.Count
        ProcessIds=$alive.ToArray()
        Working=$working
        Private=$private
        Cpu=$cpu
    }
}

$started=[DateTime]::UtcNow
$maxWorking=0L
$maxPrivate=0L
$exitCode=""
$memoryPressureStop=$false

try{
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="600000"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="1"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="512"

    $env:SHARPEMU_LOG_AGC_SHADER="0"
    $env:SHARPEMU_TRACE_DCC_ALIAS="0"
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE="0"
    $env:SHARPEMU_BINK_INTRO_HARNESS="0"
    $env:SHARPEMU_TRACE_MOVIE_IO="0"

    Remove-Item Env:SHARPEMU_RENDER_CHECKPOINTS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_DISABLE_NATIVE_GUEST_WORKERS -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_VEH_HOST_MANAGED -ErrorAction SilentlyContinue

    Write-Host "[V74.0.7] Starting Demon's Souls sampled-image residency run."
    Write-Host "[V74.0.7] Compute texture restore from V74.0.6.3 remains active."
    Write-Host "[V74.0.7] Sampled-only GuestImage budget=512 MiB; trim target=384 MiB."
    Write-Host "[V74.0.7] Swapchain cached staging retires on frame fence."
    Write-Host "[V74.0.7] Safety stop: >8GiB working or >16GiB private for ~10s."
    Write-Host "[V74.0.7] ceiling=180s."

    $args='"{0}" "{1}"' -f $dll,$Eboot

    $launcher=Start-Process `
        -FilePath "dotnet" `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $deadline=$started.AddSeconds(180)
    $lastStatus=[DateTime]::MinValue
    $lastMemory=[DateTime]::MinValue
    $zeroProcessSamples=0
    $pressureSamples=0

    while([DateTime]::UtcNow-lt$deadline){
        Start-Sleep -Milliseconds 500
        $now=[DateTime]::UtcNow

        $snapshot=Get-SharpEmuSnapshot `
            -LauncherProcessId $launcher.Id

        if($snapshot.Count-eq 0){
            $zeroProcessSamples++
        } else {
            $zeroProcessSamples=0
        }

        if($now-ge$lastMemory.AddSeconds(2)){
            $lastMemory=$now

            $maxWorking=[Math]::Max(
                $maxWorking,
                [int64]$snapshot.Working)

            $maxPrivate=[Math]::Max(
                $maxPrivate,
                [int64]$snapshot.Private)

            ("{0:F1};{1};{2:F1};{3:F1};{4:F2}" -f
                (($now-$started).TotalSeconds),
                $snapshot.Count,
                ($snapshot.Working/1MB),
                ($snapshot.Private/1MB),
                $snapshot.Cpu) |
                Add-Content -LiteralPath $memory -Encoding ASCII

            if($snapshot.Working-gt 8GB -or
               $snapshot.Private-gt 16GB){
                $pressureSamples++
            } else {
                $pressureSamples=0
            }

            if($pressureSamples-ge 5){
                $memoryPressureStop=$true
                Write-Host "[V74.0.7] MEMORY SAFETY STOP: diagnostic is intentionally terminating SharpEmu."
                break
            }
        }

        if($now-ge$lastStatus.AddSeconds(20)){
            $lastStatus=$now

            Write-Host (
                "[V74.0.7] elapsed={0:F0}s processes={1} working={2:F0}MB private={3:F0}MB" -f
                (($now-$started).TotalSeconds),
                $snapshot.Count,
                ($snapshot.Working/1MB),
                ($snapshot.Private/1MB))
        }

        $textLog=""
        if([System.IO.File]::Exists($stderr)){
            try{
                $textLog=[System.IO.File]::ReadAllText($stderr)
            } catch {
            }
        }

        if($textLog.IndexOf(
                "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code",
                [System.StringComparison]::Ordinal)-ge 0 -or
           $textLog.IndexOf(
                "0x80131506",
                [System.StringComparison]::OrdinalIgnoreCase)-ge 0){
            Write-Host "[V74.0.7] CLR FailFast regression detected."
            break
        }

        if($zeroProcessSamples-ge 6 -and
           ($now-$started).TotalSeconds-gt 10){
            break
        }
    }

    try{
        $launcher.Refresh()

        if($launcher.HasExited){
            $exitCode=$launcher.ExitCode
        } else {
            $exitCode="diagnostic-stop"
        }
    } catch {
        $exitCode="unknown"
    }

    $snapshot=Get-SharpEmuSnapshot `
        -LauncherProcessId $launcher.Id

    foreach($processIdValue in $snapshot.ProcessIds){
        try{
            & taskkill.exe /PID $processIdValue /T /F 2>$null | Out-Null
        } catch {
        }
    }
} finally {
    foreach($name in $variables){
        if($null-eq$old[$name]){
            Remove-Item ("Env:"+$name) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $name,
                [string]$old[$name],
                [EnvironmentVariableTarget]::Process)
        }
    }
}

$all=New-Object System.Collections.Generic.List[string]
foreach($file in @($stdout,$stderr)){
    if([System.IO.File]::Exists($file)){
        foreach($line in @(
            Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)){
            $all.Add([string]$line)
        }
    }
}

function Hits([string]$Pattern){
    return @($all | Where-Object{$_ -match $Pattern})
}

$cacheAdd=@(Hits "\[V74\.0\.7\]\[GIMG_CACHE\] add")
$cacheTrim=@(Hits "\[V74\.0\.7\]\[GIMG_CACHE\] trim")
$cachePromote=@(Hits "\[V74\.0\.7\]\[GIMG_CACHE\] promote")
$computeFails=@(Hits "Vulkan compute dispatch failed")
$nullInvariant=@(Hits "compute texture resource remained null")
$events=@(Hits "\[V17\]\[EVENT_FASTPATH\]")
$fail=@(Hits "Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506")
$natural=@(Hits "bink2\.natural_guest_movie_observed")
$computeYuv=@(Hits "bink2\.compute_yuv_binding")
$dcc=@(Hits "\[V74\.0\.4\]\[DCC\]")
$large=@(Hits "\[V74\.0\.4\]\[ALLOC\]")
$reuse=@(Hits "\[V74\.0\.5\]\[CACHE\]")

$class="residency-run-inconclusive"

if($fail.Count-gt 0){
    $class="clr-failfast-regression"
} elseif($computeFails.Count-gt 0 -or $nullInvariant.Count-gt 0){
    $class="compute-regression"
} elseif($memoryPressureStop){
    $class="memory-pressure-after-residency-budget"
} elseif($natural.Count-gt 0 -and $computeYuv.Count-gt 0){
    $class="natural-bink-compute-yuv-active"
} elseif($cacheTrim.Count-gt 0 -and $events.Count-ge 8){
    $class="sampled-residency-budget-active"
} elseif($events.Count-ge 8){
    $class="compute-fixed-memory-window-survived"
}

$tail=[System.IO.Path]::Combine($out,"RUNTIME_TAIL.txt")
if([System.IO.File]::Exists($stderr)){
    $lines=@(
        Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
    )

    if($lines.Count-gt 0){
        $start=[Math]::Max(0,$lines.Count-700)
        @($lines[$start..($lines.Count-1)]) |
            Set-Content -LiteralPath $tail -Encoding UTF8
    }
}

@(
    $all |
    Where-Object{
        $_ -match "\[V74\.0\.7\]\[GIMG_CACHE\]|" +
                  "\[V74\.0\.[45]\]\[(?:DCC|ALLOC|CACHE)\]|" +
                  "Vulkan compute dispatch failed|" +
                  "compute texture resource remained null|" +
                  "\[V17\]\[EVENT_FASTPATH\]|" +
                  "bink2\.natural_guest_movie_observed|" +
                  "bink2\.compute_yuv_binding"
    }
) |
Set-Content `
    -LiteralPath (
        [System.IO.Path]::Combine(
            $out,
            "RESIDENCY_TIMELINE.txt")) `
    -Encoding UTF8

@(
    "version=74.0.7",
    "classification=$class",
    "exit_code=$exitCode",
    "memory_pressure_stop=$memoryPressureStop",
    "sampled_cache_add_logs=$($cacheAdd.Count)",
    "sampled_cache_trim_logs=$($cacheTrim.Count)",
    "sampled_cache_promote_logs=$($cachePromote.Count)",
    "compute_dispatch_fail_hits=$($computeFails.Count)",
    "compute_null_invariant_hits=$($nullInvariant.Count)",
    "event_fastpath_hits=$($events.Count)",
    "clr_failfast_hits=$($fail.Count)",
    "natural_guest_movie_hits=$($natural.Count)",
    "compute_yuv_binding_hits=$($computeYuv.Count)",
    "dcc_suppression_hits=$($dcc.Count)",
    "large_cpu_snapshot_hits=$($large.Count)",
    "source_snapshot_reuse_hits=$($reuse.Count)",
    ("peak_process_tree_working_set_mb={0:F1}" -f ($maxWorking/1MB)),
    ("peak_process_tree_private_mb={0:F1}" -f ($maxPrivate/1MB)),
    "",
    "V74.0.6.3 baseline proof:",
    "- compute_dispatch_fail_hits=0",
    "- compute_null_invariant_hits=0",
    "- clr_failfast_hits=0",
    "- raw EVENT_FASTPATH reached n=1024",
    "- only 6 >=8MiB CPU snapshot breadcrumbs remained",
    "- memory still reached ~11.8GiB working / ~17.1GiB private",
    "- DCC suppression cumulative log reached ~998MiB avoided"
) |
Set-Content `
    -LiteralPath (
        [System.IO.Path]::Combine(
            $out,
            "SUMMARY.txt")) `
    -Encoding UTF8

$srcDir=[System.IO.Path]::Combine($out,"sources")
[System.IO.Directory]::CreateDirectory($srcDir)|Out-Null

Copy-Item `
    -LiteralPath $presenter `
    -Destination (
        [System.IO.Path]::Combine(
            $srcDir,
            "VulkanVideoPresenter.cs")) `
    -Force

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive `
    -Path ([System.IO.Path]::Combine($out,"*")) `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[V74.0.7] RESULT ZIP: $zip"
Write-Host "[V74.0.7] classification=$class"
Write-Host "[V74.0.7] cache_add=$($cacheAdd.Count) cache_trim=$($cacheTrim.Count) promote=$($cachePromote.Count) compute_fails=$($computeFails.Count) events=$($events.Count) failfast=$($fail.Count) natural=$($natural.Count)"
