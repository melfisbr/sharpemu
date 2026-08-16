param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot
$presenter=Get-PresenterPath $root
$native=Get-NativeWorkerPathV74010 $root
$hostMovie=Get-HostMovieBridgePathV74012 $root

$nativeSemantic=Test-NativeLaneSemanticV740111 -Path $native -ThrowOnFailure
$hostState=Test-StartupBinkHandoffStateV74012 $hostMovie
if(-not $hostState.Installed){
    throw "[V74.0.12] Runtime refused: startup completion handoff is not installed."
}

$presenterText=[System.IO.File]::ReadAllText($presenter)
if(-not $presenterText.Contains("SHARPEMU_V74_0_12_BINK_COMPLETION_VISUAL_RELEASE")){
    throw "[V74.0.12] Runtime refused: presenter V74.0.12 is not installed."
}

if(-not [System.IO.File]::Exists($Eboot)){
    throw "[V74.0.12] EBOOT missing: $Eboot"
}

$expected="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actual=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash.ToUpperInvariant()
if($actual-ne$expected){
    throw "[V74.0.12] Wrong EBOOT. actual=$actual"
}

$dll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Debug","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($dll)){
    throw "[V74.0.12] SharpEmu.dll missing: $dll"
}

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out=[System.IO.Path]::Combine(
    $root,"SharpEmu_V74_0_12_FASTBOOT_HANDOFF_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($out)|Out-Null

$stdout=[System.IO.Path]::Combine($out,"stdout.log")
$stderr=[System.IO.Path]::Combine($out,"stderr.log")
$perfCsv=[System.IO.Path]::Combine($out,"FASTBOOT_PERF.csv")
$milestone=[System.IO.Path]::Combine($out,"MILESTONES.txt")

"elapsed_s;working_mb;private_mb;cpu_pct;stderr_mb" |
    Set-Content -LiteralPath $perfCsv -Encoding ASCII

$variables=@(
    "SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT",
    "SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT",
    "SHARPEMU_BINK_AUTO_BOOT",
    "SHARPEMU_BINK_AUTO_BOOT_GRACE_MS",
    "SHARPEMU_BINK_STARTUP_COMPLETION_SHIM",
    "SHARPEMU_LOG_GUEST_THREADS",
    "SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS",
    "SHARPEMU_PROFILE_GPU_WAIT",
    "SHARPEMU_LOG_DIRECT_MEMORY",
    "SHARPEMU_LOG_VMEM",
    "SHARPEMU_LOG_VIRTUAL_MEMORY",
    "SHARPEMU_LOG_LAZY_COMMIT",
    "SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT",
    "SHARPEMU_TRACE_RENDER_TARGET_ADDRESS",
    "SHARPEMU_LOG_AGC_SHADER",
    "SHARPEMU_TRACE_DCC_ALIAS",
    "SHARPEMU_TRACE_SCANOUT_LINEAGE",
    "SHARPEMU_TRACE_RESOURCE_DEPENDENCIES",
    "SHARPEMU_LOG_VK_RESOURCES",
    "SHARPEMU_LOG_VK_COMPUTE_RESOURCES",
    "SHARPEMU_TRACE_MOVIE_IO",
    "SHARPEMU_LOG_VIDEOOUT_FPS"
)

$old=@{}
foreach($name in $variables){
    $old[$name]=[Environment]::GetEnvironmentVariable(
        $name,[EnvironmentVariableTarget]::Process)
}

function Read-NewLogChunk {
    param(
        [string]$Path,
        [ref]$Offset
    )

    if(-not [System.IO.File]::Exists($Path)){
        return ""
    }

    $fs=$null
    $ms=$null
    try{
        $fs=[System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite)

        if($fs.Length-le$Offset.Value){
            return ""
        }

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
    }
    finally{
        if($null-ne$ms){$ms.Dispose()}
        if($null-ne$fs){$fs.Dispose()}
    }
}

$started=[DateTime]::UtcNow
$hardDeadline=$started.AddSeconds(360)
$deadline=$hardDeadline
$logOffset=[int64]0
$carry=""
$firstNaturalAt=$null
$firstCompleteAt=$null
$secondNaturalAt=$null
$secondCompleteAt=$null
$handoffHits=0
$fallbackStart=0
$fallbackEnd=0
$failfast=0
$computeFail=0
$deviceLost=0
$previousCpu=0.0
$previousCpuAt=$started
$peakWorking=[int64]0
$peakPrivate=[int64]0
$exitCode=""

try{
    # Functional settings.
    $env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    $env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"
    $env:SHARPEMU_BINK_AUTO_BOOT="0"
    $env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="900000"
    $env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"

    # SHARPEMU_V74_0_12_FASTBOOT_LOW_OVERHEAD_TRACE
    # The previous truth run emitted >1.1 million per-transition guest-thread
    # lines. Keep only bounded functional logs in the timed performance run.
    $env:SHARPEMU_LOG_GUEST_THREADS="0"
    $env:SHARPEMU_LOG_GUEST_THREAD_SNAPSHOTS="0"
    $env:SHARPEMU_PROFILE_GPU_WAIT="0"
    $env:SHARPEMU_LOG_DIRECT_MEMORY="0"
    $env:SHARPEMU_LOG_VMEM="0"
    $env:SHARPEMU_LOG_VIRTUAL_MEMORY="0"
    $env:SHARPEMU_LOG_LAZY_COMMIT="0"
    $env:SHARPEMU_TRACE_DEMONS_TEXTURE_CONTRACT="0"
    $env:SHARPEMU_TRACE_RENDER_TARGET_ADDRESS="0"
    $env:SHARPEMU_LOG_AGC_SHADER="0"
    $env:SHARPEMU_TRACE_DCC_ALIAS="0"
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE="0"
    $env:SHARPEMU_TRACE_RESOURCE_DEPENDENCIES="0"
    $env:SHARPEMU_LOG_VK_RESOURCES="0"
    $env:SHARPEMU_LOG_VK_COMPUTE_RESOURCES="0"
    $env:SHARPEMU_TRACE_MOVIE_IO="0"
    $env:SHARPEMU_LOG_VIDEOOUT_FPS="1"

    Write-Host "[V74.0.12] FASTBOOT/HANDOFF run starting."
    Write-Host "[V74.0.12] High-volume guest-thread/direct-memory/full-truth traces are OFF."
    Write-Host "[V74.0.12] Native lane remains 8; TBB remains 2."
    Write-Host "[V74.0.12] Startup completion shim: ps_studios_logo + logo_intro only."
    Write-Host "[V74.0.12] Result folder: $out"

    $args='"{0}" "{1}"' -f $dll,$Eboot
    $launcher=Start-Process `
        -FilePath "dotnet" `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $dll) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $zeroSamples=0
    while([DateTime]::UtcNow-lt$deadline){
        Start-Sleep -Seconds 2
        $now=[DateTime]::UtcNow
        $elapsed=($now-$started).TotalSeconds

        try{
            $p=Get-Process -Id $launcher.Id -ErrorAction Stop
            $working=[int64]$p.WorkingSet64
            $private=[int64]$p.PrivateMemorySize64
            $cpu=[double]$p.CPU
            $sampleSeconds=[Math]::Max(($now-$previousCpuAt).TotalSeconds,0.001)
            $cpuPct=
                ([Math]::Max(0.0,$cpu-$previousCpu)/$sampleSeconds) /
                [Math]::Max([Environment]::ProcessorCount,1) * 100.0
            $previousCpu=$cpu
            $previousCpuAt=$now
            $zeroSamples=0
        }
        catch{
            $working=[int64]0
            $private=[int64]0
            $cpuPct=0.0
            $zeroSamples++
        }

        $peakWorking=[Math]::Max($peakWorking,$working)
        $peakPrivate=[Math]::Max($peakPrivate,$private)

        $logMb=0.0
        if([System.IO.File]::Exists($stderr)){
            $logMb=(Get-Item -LiteralPath $stderr).Length/1MB
        }

        ("{0:F1};{1:F1};{2:F1};{3:F1};{4:F1}" -f
            $elapsed,($working/1MB),($private/1MB),$cpuPct,$logMb) |
            Add-Content -LiteralPath $perfCsv -Encoding ASCII

        $chunk=Read-NewLogChunk -Path $stderr -Offset ([ref]$logOffset)
        if(-not [string]::IsNullOrEmpty($chunk)){
            $scan=$carry+$chunk
            $carry=
                if($scan.Length-gt 2048){
                    $scan.Substring($scan.Length-2048)
                } else {
                    $scan
                }

            foreach($m in [regex]::Matches(
                    $scan,
                    "bink2\\.natural_guest_movie_observed[^\\r\\n]*file='([^']+)'")){
                $file=$m.Groups[1].Value
                if($null-eq$firstNaturalAt){
                    $firstNaturalAt=$now
                    Add-Content -LiteralPath $milestone -Encoding UTF8 `
                        -Value ("{0:F1}s natural_1 {1}" -f $elapsed,$file)
                    Write-Host "[V74.0.12] natural movie #1 at $([Math]::Round($elapsed,1))s: $file"
                }
                elseif($null-eq$secondNaturalAt -and
                       $file-ne"ps_studios_logo.bk2"){
                    $secondNaturalAt=$now
                    Add-Content -LiteralPath $milestone -Encoding UTF8 `
                        -Value ("{0:F1}s natural_2 {1}" -f $elapsed,$file)
                    Write-Host "[V74.0.12] natural movie #2 at $([Math]::Round($elapsed,1))s: $file"
                }
            }

            foreach($m in [regex]::Matches(
                    $scan,
                    "Bink2 bridge completed: ([^\\r\\n]+)")){
                $detail=$m.Groups[1].Value
                if($null-eq$firstCompleteAt){
                    $firstCompleteAt=$now
                    $candidate=$now.AddSeconds(120)
                    if($candidate-lt$deadline){$deadline=$candidate}
                    Add-Content -LiteralPath $milestone -Encoding UTF8 `
                        -Value ("{0:F1}s completed_1 {1}" -f $elapsed,$detail)
                    Write-Host "[V74.0.12] startup movie #1 completed at $([Math]::Round($elapsed,1))s."
                }
                elseif($null-ne$secondNaturalAt -and $null-eq$secondCompleteAt){
                    $secondCompleteAt=$now
                    $candidate=$now.AddSeconds(45)
                    if($candidate-lt$deadline){$deadline=$candidate}
                    Add-Content -LiteralPath $milestone -Encoding UTF8 `
                        -Value ("{0:F1}s completed_2 {1}" -f $elapsed,$detail)
                    Write-Host "[V74.0.12] startup movie #2 completed at $([Math]::Round($elapsed,1))s."
                }
            }

            $handoffHits += [regex]::Matches(
                $scan,
                'bink2\.startup_completion_shim').Count
            $fallbackStart += [regex]::Matches(
                $scan,
                'bink2\.descriptorless_direct_fallback_start').Count
            $fallbackEnd += [regex]::Matches(
                $scan,
                'bink2\.descriptorless_direct_fallback_end').Count
            $computeFail += [regex]::Matches(
                $scan,
                'Vulkan compute dispatch failed').Count
            $failfast += [regex]::Matches(
                $scan,
                'Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506').Count
            $deviceLost += [regex]::Matches(
                $scan,
                'VK_ERROR_DEVICE_LOST|DeviceLostException').Count
        }

        if(([int]$elapsed % 10)-lt 2){
            Write-Host (
                "[V74.0.12] t={0:F0}s work={1:F0}MB private={2:F0}MB cpu={3:F0}% log={4:F1}MB " +
                "natural={5}/{6} complete={7}/{8} handoff={9} fallback={10}/{11}" -f
                $elapsed,($working/1MB),($private/1MB),$cpuPct,$logMb,
                ($null-ne$firstNaturalAt),($null-ne$secondNaturalAt),
                ($null-ne$firstCompleteAt),($null-ne$secondCompleteAt),
                $handoffHits,$fallbackStart,$fallbackEnd)
        }

        if($failfast-gt 0 -or $deviceLost-gt 0 -or $computeFail-gt 0){
            break
        }
        if($zeroSamples-ge 3 -and $elapsed-gt 10){
            break
        }
    }

    try{
        $launcher.Refresh()
        if($launcher.HasExited){
            $exitCode=$launcher.ExitCode
        } else {
            $exitCode="diagnostic-stop"
            & taskkill.exe /PID $launcher.Id /T /F 2>$null | Out-Null
        }
    }catch{
        $exitCode="unknown"
    }
}
finally{
    foreach($name in $variables){
        if($null-eq$old[$name]){
            Remove-Item ("Env:"+$name) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $name,[string]$old[$name],[EnvironmentVariableTarget]::Process)
        }
    }
}

$finalText=""
if([System.IO.File]::Exists($stderr)){
    $finalText=[System.IO.File]::ReadAllText($stderr)
}

$naturalMatches=[regex]::Matches(
    $finalText,
    "bink2\\.natural_guest_movie_observed[^\\r\\n]*file='([^']+)'")
$naturalFiles=@($naturalMatches | ForEach-Object{$_.Groups[1].Value})
$completedMatches=[regex]::Matches(
    $finalText,
    'Bink2 bridge completed: ([^\r\n]+)')
$handoffTotal=[regex]::Matches(
    $finalText,
    'bink2\.startup_completion_shim').Count
$fallbackStartTotal=[regex]::Matches(
    $finalText,
    'bink2\.descriptorless_direct_fallback_start').Count
$fallbackEndTotal=[regex]::Matches(
    $finalText,
    'bink2\.descriptorless_direct_fallback_end').Count
$computeFailTotal=[regex]::Matches(
    $finalText,
    'Vulkan compute dispatch failed').Count
$failfastTotal=[regex]::Matches(
    $finalText,
    'Invalid Program: attempted to call a UnmanagedCallersOnly method from managed code|0x80131506').Count
$deviceLostTotal=[regex]::Matches(
    $finalText,
    'VK_ERROR_DEVICE_LOST|DeviceLostException').Count

$logBytes=
    if([System.IO.File]::Exists($stderr)){
        (Get-Item -LiteralPath $stderr).Length
    } else {
        0
    }

$class="fastboot-no-natural-movie"
if($failfastTotal-gt 0){
    $class="clr-failfast-regression"
}elseif($deviceLostTotal-gt 0){
    $class="device-lost"
}elseif($computeFailTotal-gt 0){
    $class="compute-regression"
}elseif($naturalMatches.Count-ge 2){
    $class="startup-handoff-advanced-to-next-movie"
}elseif($completedMatches.Count-ge 1 -and $fallbackEndTotal-ge 1){
    $class="startup-movie-completed-and-visual-released"
}elseif($naturalMatches.Count-ge 1){
    $class="fastboot-reached-first-natural-movie"
}

@(
    "version=74.0.12",
    "classification=$class",
    "exit_code=$exitCode",
    "",
    "[performance]",
    ("peak_working_mb={0:F1}" -f ($peakWorking/1MB)),
    ("peak_private_mb={0:F1}" -f ($peakPrivate/1MB)),
    ("stderr_mb={0:F1}" -f ($logBytes/1MB)),
    "v74011_reference_stderr_mb=130.7",
    "v74011_reference_total_lines=1323706",
    "v74011_reference_transition_lines=1108915",
    "",
    "[startup-bink]",
    "natural_movie_hits=$($naturalMatches.Count)",
    "natural_movie_files=$([string]::Join(',', $naturalFiles))",
    "bridge_completed_hits=$($completedMatches.Count)",
    "startup_completion_shim_hits=$handoffTotal",
    "fallback_start_hits=$fallbackStartTotal",
    "fallback_end_hits=$fallbackEndTotal",
    "",
    "[guards]",
    "compute_fail_hits=$computeFailTotal",
    "failfast_hits=$failfastTotal",
    "device_lost_hits=$deviceLostTotal",
    "",
    "[V74.0.11 evidence]",
    "Once reached, ps_studios_logo completed normally in 9.48s at frame 254.",
    "The previous timed run generated ~1.1M guest-thread transition log lines.",
    "No descriptorless fallback end was emitted after playback completion.",
    "The existing guest completion shim was present but TryTakeOverGuestMovie returned false unconditionally."
) | Set-Content -LiteralPath (
    [System.IO.Path]::Combine($out,"SUMMARY.txt")) -Encoding UTF8

$zip="$out.zip"
if([System.IO.File]::Exists($zip)){Remove-Item -LiteralPath $zip -Force}
Compress-Archive `
    -Path ([System.IO.Path]::Combine($out,"*")) `
    -DestinationPath $zip `
    -CompressionLevel Optimal

Write-Host "[V74.0.12] RESULT ZIP: $zip"
Write-Host "[V74.0.12] classification=$class natural=$($naturalMatches.Count) completed=$($completedMatches.Count) handoff=$handoffTotal fallback=$fallbackStartTotal/$fallbackEndTotal stderr=$([Math]::Round($logBytes/1MB,1))MB"
