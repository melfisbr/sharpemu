param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")
$root=Resolve-RepoRoot $RepositoryRoot
$hostMovieBridgePath=Get-HostMovieBridgePathV74013 $root
$presenter=Get-PresenterPathV74013 $root
$native=Get-NativeWorkerPathV74013 $root
$state=Test-V74013State -HostMovie $hostMovieBridgePath -Presenter $presenter -Native $native
if(-not $state.V13){throw "[V74.0.13.2] Runtime refused: V74.0.13.2 handoff is not installed."}
if(-not $state.Presenter -or -not $state.Native){throw "[V74.0.13.2] Runtime source prerequisites are incomplete."}
if(-not [System.IO.File]::Exists($Eboot)){throw "[V74.0.13.2] EBOOT missing: $Eboot"}
$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){throw "[V74.0.13.2] Wrong EBOOT. actual=$actual"}

$releaseDll=[System.IO.Path]::Combine($root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
$debugDll=[System.IO.Path]::Combine($root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")
$dll=$releaseDll
$runtimeConfig="Release"
if(-not [System.IO.File]::Exists($dll)){
    $dll=$debugDll
    $runtimeConfig="Debug-fallback"
}
if(-not [System.IO.File]::Exists($dll)){throw "[V74.0.13.2] SharpEmu.dll missing in Release and Debug outputs."}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine($root,"SharpEmu_V74_0_13_2_FASTBOOT_PERF_HANDOFF_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null
$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$perfCsv=[System.IO.Path]::Combine($out,"FASTBOOT_PERF.csv")
$milestone=[System.IO.Path]::Combine($out,"MILESTONES.txt")
"elapsed_s;working_mb;private_mb;cpu_pct;stderr_mb" | Set-Content -LiteralPath $perfCsv -Encoding ASCII

function Read-NewLogChunk {
    param([string]$Path,[ref]$Offset)
    if(-not [System.IO.File]::Exists($Path)){return ""}
    $fs=$null;$ms=$null
    try{
        $share=[System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
        $fs=[System.IO.FileStream]::new($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$share)
        if($fs.Length-le$Offset.Value){return ""}
        [void]$fs.Seek($Offset.Value,[System.IO.SeekOrigin]::Begin)
        $ms=[System.IO.MemoryStream]::new()
        $buffer=New-Object byte[] 65536
        while($fs.Position-lt$fs.Length){
            $read=$fs.Read($buffer,0,$buffer.Length)
            if($read-le 0){break}
            $ms.Write($buffer,0,$read)
        }
        $Offset.Value=$fs.Position
        return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally {
        if($null-ne$ms){$ms.Dispose()}
        if($null-ne$fs){$fs.Dispose()}
    }
}

function Read-AllTextShared {
    param([string]$Path)
    if(-not [System.IO.File]::Exists($Path)){return ""}
    $last=$null
    for($attempt=0;$attempt-lt 12;$attempt++){
        $fs=$null;$reader=$null
        try{
            $share=[System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
            $fs=[System.IO.FileStream]::new($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$share)
            $reader=[System.IO.StreamReader]::new($fs,[System.Text.Encoding]::UTF8,$true,65536,$false)
            return $reader.ReadToEnd()
        } catch {
            $last=$_
            Start-Sleep -Milliseconds 250
        } finally {
            if($null-ne$reader){$reader.Dispose();$reader=$null;$fs=$null}
            if($null-ne$fs){$fs.Dispose()}
        }
    }
    Write-Host "[V74.0.13.2] WARN: final shared log read failed after retries: $($last.Exception.Message)"
    return ""
}

function Bound-Deadline {
    param([DateTime]$Candidate,[DateTime]$Absolute)
    if($Candidate-gt$Absolute){return $Absolute}
    return $Candidate
}

function Get-DescendantProcessIdsV74013 {
    param([int]$RootPid)
    $result=New-Object System.Collections.Generic.List[int]
    try{
        $all=@(Get-CimInstance Win32_Process -ErrorAction Stop |
            Select-Object ProcessId,ParentProcessId)
        $frontier=New-Object System.Collections.Generic.Queue[int]
        $frontier.Enqueue($RootPid)
        while($frontier.Count-gt 0){
            $parent=$frontier.Dequeue()
            foreach($row in $all){
                if([int]$row.ParentProcessId-eq$parent){
                    $child=[int]$row.ProcessId
                    if(-not $result.Contains($child)){
                        $result.Add($child)
                        $frontier.Enqueue($child)
                    }
                }
            }
        }
    } catch { }
    return @($result)
}

function Stop-ProcessTreeV74013 {
    param([int]$RootPid)
    # A mitigated child can retain the redirected stderr handle after the
    # original dotnet launcher has exited.  Win32_Process keeps the creator PID,
    # so collect descendants first and stop leaves before the root.
    $desc=@(Get-DescendantProcessIdsV74013 -RootPid $RootPid)
    [array]::Reverse($desc)
    foreach($pidValue in $desc){
        try{Stop-Process -Id $pidValue -Force -ErrorAction Stop}catch{}
    }
    try{Stop-Process -Id $RootPid -Force -ErrorAction Stop}catch{}
}

$variables=@(
    "SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT","SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT",
    "SHARPEMU_BINK_AUTO_BOOT","SHARPEMU_BINK_AUTO_BOOT_GRACE_MS","SHARPEMU_BINK_STARTUP_COMPLETION_SHIM",
    "SHARPEMU_RENDER_SCALE","SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB","SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB",
    "SHARPEMU_VK_GUEST_BUFFER_CACHE_MB","SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB",
    "SHARPEMU_LOG_GUEST_THREADS","SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS","SHARPEMU_PROFILE_GPU_WAIT",
    "SHARPEMU_LOG_DIRECT_MEMORY","SHARPEMU_LOG_VMEM","SHARPEMU_LOG_VIRTUAL_MEMORY","SHARPEMU_LOG_LAZY_COMMIT",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT","SHARPEMU_TRACE_RENDER_TARGET_ADDRESS","SHARPEMU_LOG_AGC_SHADER",
    "SHARPEMU_TRACE_DCC_ALIAS","SHARPEMU_TRACE_SCANOUT_LINEAGE","SHARPEMU_TRACE_RESOURCE_DEPENDENCIES",
    "SHARPEMU_LOG_VK_RESOURCES","SHARPEMU_LOG_VK_COMPUTE_RESOURCES","SHARPEMU_TRACE_MOVIE_IO","SHARPEMU_LOG_VIDEOOUT_FPS",
    "SHARPEMU_OVERLAY","SHARPEMU_PERF_MEM","SHARPEMU_PROFILE_RENDER","SHARPEMU_TRACE_DRAWS",
    "SHARPEMU_TRACE_GUEST_IMAGES","SHARPEMU_TRACE_GUEST_IMAGE_EVENTS","SHARPEMU_TRACE_GUEST_WORK_COMPLETION",
    "SHARPEMU_TRACE_ORDERED_ACTION_LATENCY","SHARPEMU_TRACE_RENDER_WORK","SHARPEMU_LOG_AGC",
    "SHARPEMU_LOG_PTHREADS","SHARPEMU_LOG_PTHREAD_CALLSITES","SHARPEMU_LOG_PTHREAD_FASTPATH",
    "SHARPEMU_LOG_ALL_IMPORTS","SHARPEMU_LOG_IMPORT_PERIODIC","SHARPEMU_LOG_EXPECTED_IMPORT_RESULTS"
)
$old=@{}
foreach($name in $variables){$old[$name]=[Environment]::GetEnvironmentVariable($name,[EnvironmentVariableTarget]::Process)}

$started=[DateTime]::UtcNow
$absoluteDeadline=$started.AddSeconds(720)
$deadline=$started.AddSeconds(480)
$nextStatus=$started
$logOffset=[int64]0;$carry=""
$firstNaturalAt=$null;$firstCompleteAt=$null;$secondNaturalAt=$null;$secondCompleteAt=$null
$handoffHits=0;$fallbackStart=0;$fallbackEnd=0;$failfast=0;$computeFail=0;$deviceLost=0
$previousCpu=0.0;$previousCpuAt=$started;$peakWorking=[int64]0;$peakPrivate=[int64]0
$exitCode="";$launcher=$null;$zeroSamples=0

try{
    $env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    $env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"
    $env:SHARPEMU_BINK_AUTO_BOOT="0"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="900000"
    $env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"

    # V74.0.13.2 performance profile. The captured pre-video target is 3840x2160
    # at ~0.2 FPS / ~4.94 s per frame. Render-scale 0.5 preserves draw/compute
    # ordering but creates non-storage color/depth images at 1920x1080, reducing
    # raster/image bandwidth to roughly one quarter. Storage/UAV dimensions stay
    # native by VulkanVideoPresenter design.
    $env:SHARPEMU_RENDER_SCALE="0.5"
    $env:SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="256"
    $env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="384"
    $env:SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="192"
    $env:SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB="384"

    $env:SHARPEMU_LOG_GUEST_THREADS="0";$env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS="0"
    $env:SHARPEMU_PROFILE_GPU_WAIT="0";$env:SHARPEMU_LOG_DIRECT_MEMORY="0"
    $env:SHARPEMU_LOG_VMEM="0";$env:SHARPEMU_LOG_VIRTUAL_MEMORY="0";$env:SHARPEMU_LOG_LAZY_COMMIT="0"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="0";$env:SHARPEMU_TRACE_RENDER_TARGET_ADDRESS="0"
    $env:SHARPEMU_LOG_AGC_SHADER="0";$env:SHARPEMU_TRACE_DCC_ALIAS="0";$env:SHARPEMU_TRACE_SCANOUT_LINEAGE="0"
    $env:SHARPEMU_TRACE_RESOURCE_DEPENDENCIES="0";$env:SHARPEMU_LOG_VK_RESOURCES="0"
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES="0";$env:SHARPEMU_TRACE_MOVIE_IO="0"
    $env:SHARPEMU_LOG_VIDEOOUT_FPS="1"

    # Explicitly neutralize every high-volume/per-frame diagnostic family that
    # may have been left in the caller environment by prior truth packages.
    $env:SHARPEMU_OVERLAY="0";$env:SHARPEMU_PERF_MEM="0";$env:SHARPEMU_PROFILE_RENDER="0"
    $env:SHARPEMU_TRACE_DRAWS="0";$env:SHARPEMU_TRACE_GUEST_IMAGES="0";$env:SHARPEMU_TRACE_GUEST_IMAGE_EVENTS="0"
    $env:SHARPEMU_TRACE_GUEST_WORK_COMPLETION="0";$env:SHARPEMU_TRACE_ORDERED_ACTION_LATENCY="0";$env:SHARPEMU_TRACE_RENDER_WORK="0"
    $env:SHARPEMU_LOG_AGC="0";$env:SHARPEMU_LOG_PTHREADS="0";$env:SHARPEMU_LOG_PTHREAD_CALLSITES="0";$env:SHARPEMU_LOG_PTHREAD_FASTPATH="0"
    $env:SHARPEMU_LOG_ALL_IMPORTS="0";$env:SHARPEMU_LOG_IMPORT_PERIODIC="0";$env:SHARPEMU_LOG_EXPECTED_IMPORT_RESULTS="0"

    Write-Host "[V74.0.13.2] FASTBOOT PERFORMANCE/HANDOFF run starting."
    Write-Host "[V74.0.13.2] Runtime=$runtimeConfig render_scale=0.5 cache_mb=sampled256/texture384/guest192/device384"
    Write-Host "[V74.0.13.2] High-volume traces, PERF_MEM/profile render and overlay are OFF."
    Write-Host "[V74.0.13.2] Initial no-video deadline=480s; absolute deadline=720s; first movie extends the phase deadline."
    Write-Host "[V74.0.13.2] Result folder: $out"

    $dotnetArgumentLine='"{0}" "{1}"' -f $dll,$Eboot
    $launcher=Start-Process -FilePath "dotnet" -ArgumentList $dotnetArgumentLine -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

    while([DateTime]::UtcNow-lt$deadline){
        Start-Sleep -Seconds 2
        $now=[DateTime]::UtcNow;$elapsed=($now-$started).TotalSeconds
        try{
            $p=Get-Process -Id $launcher.Id -ErrorAction Stop
            $working=[int64]$p.WorkingSet64;$private=[int64]$p.PrivateMemorySize64;$cpu=[double]$p.CPU
            $sampleSeconds=[Math]::Max(($now-$previousCpuAt).TotalSeconds,0.001)
            $cpuPct=([Math]::Max(0.0,$cpu-$previousCpu)/$sampleSeconds)/[Math]::Max([Environment]::ProcessorCount,1)*100.0
            $previousCpu=$cpu;$previousCpuAt=$now;$zeroSamples=0
        } catch {$working=[int64]0;$private=[int64]0;$cpuPct=0.0;$zeroSamples++}
        $peakWorking=[Math]::Max($peakWorking,$working);$peakPrivate=[Math]::Max($peakPrivate,$private)
        $logMb=0.0;if([System.IO.File]::Exists($stderr)){$logMb=(Get-Item -LiteralPath $stderr).Length/1MB}
        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1}" -f $elapsed,($working/1MB),($private/1MB),$cpuPct,$logMb) | Add-Content -LiteralPath $perfCsv -Encoding ASCII

        $chunk=Read-NewLogChunk -Path $stderr -Offset ([ref]$logOffset)
        if(-not [string]::IsNullOrEmpty($chunk)){
            $scan=$carry+$chunk
            if($scan.Length-gt 4096){$carry=$scan.Substring($scan.Length-4096)}else{$carry=$scan}
            foreach($m in [regex]::Matches($scan,"bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'")){
                $file=$m.Groups[1].Value
                if($null-eq$firstNaturalAt){
                    $firstNaturalAt=$now;$deadline=Bound-Deadline -Candidate $now.AddSeconds(240) -Absolute $absoluteDeadline
                    Add-Content -LiteralPath $milestone -Encoding UTF8 -Value ("{0:F1}s natural_1 {1}" -f $elapsed,$file)
                    Write-Host "[V74.0.13.2] natural movie #1 at $([Math]::Round($elapsed,1))s: $file; deadline extended."
                } elseif($null-eq$secondNaturalAt -and [System.IO.Path]::GetFileName($file)-ne"ps_studios_logo.bk2"){
                    $secondNaturalAt=$now;$deadline=Bound-Deadline -Candidate $now.AddSeconds(180) -Absolute $absoluteDeadline
                    Add-Content -LiteralPath $milestone -Encoding UTF8 -Value ("{0:F1}s natural_2 {1}" -f $elapsed,$file)
                    Write-Host "[V74.0.13.2] natural movie #2 at $([Math]::Round($elapsed,1))s: $file"
                }
            }
            foreach($m in [regex]::Matches($scan,"Bink2 bridge completed: ([^\r\n]+)")){
                $detail=$m.Groups[1].Value
                if($null-eq$firstCompleteAt){
                    $firstCompleteAt=$now
                    $candidate=Bound-Deadline -Candidate $now.AddSeconds(240) -Absolute $absoluteDeadline
                    if($candidate-gt$deadline){$deadline=$candidate}
                    Add-Content -LiteralPath $milestone -Encoding UTF8 -Value ("{0:F1}s completed_1 {1}" -f $elapsed,$detail)
                    Write-Host "[V74.0.13.2] startup movie #1 completed at $([Math]::Round($elapsed,1))s; post-video window preserved."
                } elseif($null-ne$secondNaturalAt -and $null-eq$secondCompleteAt){
                    $secondCompleteAt=$now;$deadline=Bound-Deadline -Candidate $now.AddSeconds(45) -Absolute $absoluteDeadline
                    Add-Content -LiteralPath $milestone -Encoding UTF8 -Value ("{0:F1}s completed_2 {1}" -f $elapsed,$detail)
                    Write-Host "[V74.0.13.2] startup movie #2 completed at $([Math]::Round($elapsed,1))s."
                }
            }
            $handoffHits += [regex]::Matches($scan,'bink2\.startup_completion_shim').Count
            $fallbackStart += [regex]::Matches($scan,'bink2\.descriptorless_direct_fallback_start').Count
            $fallbackEnd += [regex]::Matches($scan,'bink2\.descriptorless_direct_fallback_end').Count
            $computeFail += [regex]::Matches($scan,'Vulkan compute dispatch failed').Count
            $failfast += [regex]::Matches($scan,'Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506').Count
            $deviceLost += [regex]::Matches($scan,'VK_ERROR_DEVICE_LOST|DeviceLostException').Count
        }

        if($now-ge$nextStatus){
            $status=("[V74.0.13.2] t={0:F0}s work={1:F0}MB private={2:F0}MB cpu={3:F0}% log={4:F1}MB natural={5}/{6} complete={7}/{8} handoff={9} fallback={10}/{11}" -f `
                $elapsed,($working/1MB),($private/1MB),$cpuPct,$logMb,($null-ne$firstNaturalAt),($null-ne$secondNaturalAt),($null-ne$firstCompleteAt),($null-ne$secondCompleteAt),$handoffHits,$fallbackStart,$fallbackEnd)
            Write-Host $status
            $nextStatus=$now.AddSeconds(10)
        }
        if($failfast-gt 0 -or $deviceLost-gt 0 -or $computeFail-gt 0){break}
        if($zeroSamples-ge 3 -and $elapsed-gt 10){break}
    }

    try{
        $launcher.Refresh()
        if($launcher.HasExited){$exitCode=$launcher.ExitCode}
        else{
            $exitCode="diagnostic-stop"
            Stop-ProcessTreeV74013 -RootPid $launcher.Id
            try{[void]$launcher.WaitForExit(15000)}catch{}
        }
    } catch {$exitCode="unknown"}
}
finally{
    if($null-ne$launcher){
        try{Stop-ProcessTreeV74013 -RootPid $launcher.Id;try{[void]$launcher.WaitForExit(10000)}catch{}}catch{}
    }
    foreach($name in $variables){
        if($null-eq$old[$name]){Remove-Item ("Env:"+$name) -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($name,[string]$old[$name],[EnvironmentVariableTarget]::Process)}
    }
}

# Give inherited redirect handles a short close/flush window after the entire
# launcher/mitigated-child tree has been stopped.  The shared reader below is
# still used, so a slow close cannot reproduce V74.0.12's IOException.
Start-Sleep -Milliseconds 500
$finalText=Read-AllTextShared -Path $stderr
$naturalMatches=[regex]::Matches($finalText,"bink2\.natural_guest_movie_observed[^\r\n]*file='([^']+)'")
$naturalFiles=@($naturalMatches|ForEach-Object{$_.Groups[1].Value})
$completedMatches=[regex]::Matches($finalText,'Bink2 bridge completed: ([^\r\n]+)')
$handoffTotal=[regex]::Matches($finalText,'bink2\.startup_completion_shim').Count
$headerFallbackTotal=[regex]::Matches($finalText,'startup_completion_shim_header_fallback').Count
$fallbackStartTotal=[regex]::Matches($finalText,'bink2\.descriptorless_direct_fallback_start').Count
$fallbackEndTotal=[regex]::Matches($finalText,'bink2\.descriptorless_direct_fallback_end').Count
$computeFailTotal=[regex]::Matches($finalText,'Vulkan compute dispatch failed').Count
$failfastTotal=[regex]::Matches($finalText,'Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506').Count
$deviceLostTotal=[regex]::Matches($finalText,'VK_ERROR_DEVICE_LOST|DeviceLostException').Count
$logBytes=0;if([System.IO.File]::Exists($stderr)){$logBytes=(Get-Item -LiteralPath $stderr).Length}
$class="fastboot-no-natural-movie"
if($failfastTotal-gt 0){$class="clr-failfast-regression"}
elseif($deviceLostTotal-gt 0){$class="device-lost"}
elseif($computeFailTotal-gt 0){$class="compute-regression"}
elseif($naturalMatches.Count-ge 2){$class="startup-handoff-advanced-to-next-movie"}
elseif($completedMatches.Count-ge 1 -and $handoffTotal-ge 1){$class="first-startup-movie-completed-with-guest-handoff"}
elseif($completedMatches.Count-ge 1){$class="first-startup-movie-completed-no-handoff"}
elseif($naturalMatches.Count-ge 1){$class="fastboot-reached-first-natural-movie"}

@(
    "version=74.0.13.2","classification=$class","exit_code=$exitCode","runtime=$runtimeConfig","render_scale=0.5","",
    "[performance]",("peak_working_mb={0:F1}" -f ($peakWorking/1MB)),("peak_private_mb={0:F1}" -f ($peakPrivate/1MB)),("stderr_mb={0:F1}" -f ($logBytes/1MB)),
    "cache_sampled_mb=256","cache_texture_mb=384","cache_guest_buffer_mb=192","cache_device_buffer_mb=384","",
    "[startup-bink]","natural_movie_hits=$($naturalMatches.Count)","natural_movie_files=$([string]::Join(',', $naturalFiles))","bridge_completed_hits=$($completedMatches.Count)",
    "startup_completion_shim_hits=$handoffTotal","header_fallback_hits=$headerFallbackTotal","fallback_start_hits=$fallbackStartTotal","fallback_end_hits=$fallbackEndTotal","",
    "[guards]","compute_fail_hits=$computeFailTotal","failfast_hits=$failfastTotal","device_lost_hits=$deviceLostTotal","",
    "[runner-repair]","status_format_fixed=True","regex_escape_fixed=True","stderr_shared_read=True","mitigated_child_tree_stop=True","post_first_movie_deadline_can_extend=True","result_zip_on_normal_diagnostic_stop=True",
    "diagnostic_overlay_off=True","ambient_truth_traces_forced_off=True"
) | Set-Content -LiteralPath ([System.IO.Path]::Combine($out,"SUMMARY.txt")) -Encoding UTF8

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){Remove-Item -LiteralPath $zip -Force}
try{
    Compress-Archive -Path ([System.IO.Path]::Combine($out,"*")) -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "[V74.0.13.2] RESULT ZIP: $zip"
} catch {
    Write-Host "[V74.0.13.2] WARN: result folder preserved but ZIP creation failed: $($_.Exception.Message)"
}
Write-Host "[V74.0.13.2] classification=$class natural=$($naturalMatches.Count) completed=$($completedMatches.Count) handoff=$handoffTotal headerFallback=$headerFallbackTotal fallback=$fallbackStartTotal/$fallbackEndTotal stderr=$([Math]::Round($logBytes/1MB,1))MB"
