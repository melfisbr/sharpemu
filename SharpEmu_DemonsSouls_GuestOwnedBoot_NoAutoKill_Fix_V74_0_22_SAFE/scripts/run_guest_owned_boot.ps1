param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

function Get-LiveTreeIdsV74022 {
    param([int]$RootId)
    $ids=New-Object 'System.Collections.Generic.List[int]'
    try{
        if(Get-Process -Id $RootId -ErrorAction SilentlyContinue){$ids.Add($RootId)}
    }catch{}
    foreach($childId in @(Get-DescendantProcessIdsV74022 -ParentId $RootId)){
        if(-not $ids.Contains([int]$childId)){$ids.Add([int]$childId)}
    }
    return @($ids)
}

function Get-TreeMemoryV74022 {
    param([int[]]$Ids)
    [double]$working=0
    [double]$private=0
    $live=0
    foreach($processIdValue in $Ids){
        try{
            $processInfo=Get-Process -Id $processIdValue -ErrorAction Stop
            $working += [double]$processInfo.WorkingSet64
            $private += [double]$processInfo.PrivateMemorySize64
            $live++
        }catch{}
    }
    return [pscustomobject]@{
        Live=$live
        WorkingMb=[Math]::Round($working/1MB,1)
        PrivateMb=[Math]::Round($private/1MB,1)
    }
}

$repoRoot=Resolve-RepoRootV74022 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot

$ebootPath=[System.IO.Path]::GetFullPath($Eboot)
if(-not [System.IO.File]::Exists($ebootPath)){throw "[V74.0.22] EBOOT missing: $ebootPath"}
$expectedEboot="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actualEboot=(Get-FileHash -LiteralPath $ebootPath -Algorithm SHA256).Hash.ToUpperInvariant()
if($actualEboot -ne $expectedEboot){throw "[V74.0.22] EBOOT SHA256 mismatch: $actualEboot"}

$runtimeDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($runtimeDll)){throw "[V74.0.22] Release runtime missing: $runtimeDll"}
$dotnetCommand=(Get-Command dotnet -ErrorAction Stop).Source

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$outputDirectory=[System.IO.Path]::Combine($repoRoot,"SharpEmu_V74_0_22_GUEST_OWNED_BOOT_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($outputDirectory)|Out-Null
$stdoutPath=[System.IO.Path]::Combine($outputDirectory,"stdout.log")
$stderrPath=[System.IO.Path]::Combine($outputDirectory,"stderr.log")
$profilePath=[System.IO.Path]::Combine($outputDirectory,"RUN_PROFILE.txt")
$summaryPath=[System.IO.Path]::Combine($outputDirectory,"SUMMARY.txt")
$milestonesPath=[System.IO.Path]::Combine($outputDirectory,"MILESTONES.txt")
$perfPath=[System.IO.Path]::Combine($outputDirectory,"PROCESS_TREE_PERF.csv")

$environmentProfile=[ordered]@{
    SHARPEMU_BINK_AUTO_BOOT="0"
    SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="1500"
    SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"
    SHARPEMU_LLE_INIT_ENV="1"
    SHARPEMU_LLE_LIBC_SAFE_ONLY="1"
    SHARPEMU_DISABLE_LLE_LIBC="0"
    SHARPEMU_LOG_PROC_PARAM="1"
    SHARPEMU_LOG_PROC_PARAM_PTRS="1"
    SHARPEMU_NATIVE_MEMCPY_INTRINSIC="1"
    SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC="1"
    SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"
    SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"
    SHARPEMU_RENDER_SCALE="1.0"
    SHARPEMU_VK_SAMPLED_GUEST_IMAGE_CACHE_MB="256"
    SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"
    SHARPEMU_VK_GUEST_BUFFER_CACHE_MB="192"
    SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB="384"
    SHARPEMU_DCC_ALIAS_HISTORY_MS="0"
    SHARPEMU_TRACE_DCC_ALIAS="0"
    SHARPEMU_PERF_MEM="0"
    SHARPEMU_PROFILE_RENDER="0"
    SHARPEMU_TRACE_DRAWS="0"
    SHARPEMU_LOG_ALL_IMPORTS="0"
    SHARPEMU_LOG_IMPORT_PERIODIC="0"
    SHARPEMU_LOG_GUEST_THREADS="0"
    SHARPEMU_LOG_PTHREADS="0"
    SHARPEMU_OVERLAY="0"
}
$previousEnvironment=@{}
foreach($environmentName in $environmentProfile.Keys){
    $previousEnvironment[$environmentName]=[Environment]::GetEnvironmentVariable($environmentName,"Process")
    [Environment]::SetEnvironmentVariable($environmentName,$environmentProfile[$environmentName],"Process")
}

$profileLines=New-Object 'System.Collections.Generic.List[string]'
$profileLines.Add("version=74.0.22")
$profileLines.Add("eboot=$ebootPath")
$profileLines.Add("eboot_sha256=$actualEboot")
$profileLines.Add("runtime=$runtimeDll")
$profileLines.Add("runner_auto_kill=False")
$profileLines.Add("exit_policy=user-closes-window-or-runtime-exits")
foreach($environmentName in $environmentProfile.Keys){$profileLines.Add("$environmentName=$($environmentProfile[$environmentName])")}
[System.IO.File]::WriteAllLines($profilePath,$profileLines)
[System.IO.File]::WriteAllText($perfPath,"elapsed_s,live_processes,working_mb,private_mb`r`n")

Write-Host "[V74.0.22] GUEST-OWNED BOOT starting."
Write-Host "[V74.0.22] Host direct/auto boot is OFF. Natural guest Bink requests own the sequence."
Write-Host "[V74.0.22] Natural startup completion shim is ON."
Write-Host "[V74.0.22] IMPORTANT: this runner does NOT close SharpEmu after ABI proof or after a timer."
Write-Host "[V74.0.22] Leave it running as long as needed; close the SharpEmu window yourself when you want the result ZIP."
Write-Host "[V74.0.22] EBOOT SHA256 OK: $actualEboot"

$runStopwatch=[System.Diagnostics.Stopwatch]::StartNew()
$processObject=$null
$lastStatus=-10.0
$seenFrame=$false
$seenMainLoop=$false
$seenAbi=$false
$seenNatural=0
$seenCompleted=0
$seenAutoBoot=$false
$seenDeviceLost=$false
$seenHeapCorruption=$false
$lastTextLength=0
$launcherExitCode="not-observed"

try{
    $dotnetArgumentLine='"{0}" "{1}"' -f $runtimeDll,$ebootPath
    $processObject=Start-Process -FilePath $dotnetCommand -ArgumentList $dotnetArgumentLine -WorkingDirectory (Split-Path -Parent $runtimeDll) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru

    while($true){
        Start-Sleep -Milliseconds 1000
        $elapsed=$runStopwatch.Elapsed.TotalSeconds
        try{$processObject.Refresh()}catch{}
        $treeIds=@(Get-LiveTreeIdsV74022 -RootId $processObject.Id)
        $tree=Get-TreeMemoryV74022 -Ids $treeIds
        Add-Content -LiteralPath $perfPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1},{1},{2:F1},{3:F1}",$elapsed,$tree.Live,$tree.WorkingMb,$tree.PrivateMb))

        $stderrText=Read-TextSharedV74022 -Path $stderrPath
        $stdoutText=Read-TextSharedV74022 -Path $stdoutPath
        $combinedText=$stderrText+"`n"+$stdoutText

        if(-not $seenAbi -and $combinedText.Contains("[V74.0.21][ENTRY_ABI] frame")){
            $seenAbi=$true
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s entry_abi_proved",$elapsed))
            Write-Host ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"[V74.0.22] t={0:F1}s Entry ABI proof observed.",$elapsed))
        }
        if(-not $seenMainLoop -and $combinedText -match 'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s'){
            $seenMainLoop=$true
            $mainLoopValue=$Matches[1]
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s main_loop guest_seconds={1}",$elapsed,$mainLoopValue))
            Write-Host "[V74.0.22] Main loop observed: guest_seconds=$mainLoopValue"
        }
        if(-not $seenFrame -and $combinedText -match 'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)'){
            $seenFrame=$true
            $frameSize=$Matches[1]
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s first_guest_frame size={1}",$elapsed,$frameSize))
            Write-Host "[V74.0.22] First guest frame observed: $frameSize"
        }

        $naturalCount=([regex]::Matches($combinedText,'bink2\.natural_guest_movie_observed')).Count
        if($naturalCount -gt $seenNatural){
            for($movieIndex=$seenNatural+1;$movieIndex -le $naturalCount;$movieIndex++){
                Write-Host "[V74.0.22] Natural guest movie observed: n=$movieIndex"
                Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s natural_guest_movie n={1}",$elapsed,$movieIndex))
            }
            $seenNatural=$naturalCount
        }
        $completedCount=([regex]::Matches($combinedText,'Bink (?:RAD|NIHAV) bridge completed: .*?\.bk2')).Count
        if($completedCount -gt $seenCompleted){
            for($completeIndex=$seenCompleted+1;$completeIndex -le $completedCount;$completeIndex++){
                Write-Host "[V74.0.22] Bink bridge completion observed: n=$completeIndex"
                Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s bink_completed n={1}",$elapsed,$completeIndex))
            }
            $seenCompleted=$completedCount
        }
        if(-not $seenAutoBoot -and ($combinedText -match 'bink2\.(?:auto_boot_order|direct_boot_started)')){
            $seenAutoBoot=$true
            Write-Host "[V74.0.22] WARNING: host auto/direct boot marker appeared even though SHARPEMU_BINK_AUTO_BOOT=0."
            Add-Content -LiteralPath $milestonesPath -Encoding UTF8 -Value ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"{0:F1}s unexpected_host_auto_boot_marker",$elapsed))
        }
        if(-not $seenDeviceLost -and $combinedText -match '(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException'){
            $seenDeviceLost=$true
            Write-Host "[V74.0.22] WARNING: Vulkan device-lost marker observed; process is left running for evidence."
        }
        if(-not $seenHeapCorruption -and $combinedText -match '(?i)HEAP_CORRUPTION|0xC0000374'){
            $seenHeapCorruption=$true
            Write-Host "[V74.0.22] WARNING: heap-corruption marker observed; process is left running for evidence."
        }

        if(($elapsed-$lastStatus) -ge 10.0){
            $lastStatus=$elapsed
            Write-Host ([string]::Format([Globalization.CultureInfo]::InvariantCulture,"[V74.0.22] t={0:F0}s procs={1} work={2:F0}MB private={3:F0}MB natural={4} completed={5}",$elapsed,$tree.Live,$tree.WorkingMb,$tree.PrivateMb,$seenNatural,$seenCompleted))
        }

        if($tree.Live -eq 0){
            try{
                $processObject.Refresh()
                if($processObject.HasExited){$launcherExitCode=$processObject.ExitCode}
            }catch{}
            break
        }
    }
}
finally{
    foreach($environmentName in $environmentProfile.Keys){
        [Environment]::SetEnvironmentVariable($environmentName,$previousEnvironment[$environmentName],"Process")
    }
}
$runStopwatch.Stop()
Start-Sleep -Milliseconds 500

$stderrFinal=Read-TextSharedV74022 -Path $stderrPath
$stdoutFinal=Read-TextSharedV74022 -Path $stdoutPath
$combinedFinal=$stderrFinal+"`n"+$stdoutFinal

$entryFrameCount=([regex]::Matches($combinedFinal,'\[V74\.0\.21\]\[ENTRY_ABI\] frame')).Count
$procCount=([regex]::Matches($combinedFinal,'proc_param: address=0x00000008027A7E80')).Count
$lleCount=([regex]::Matches($combinedFinal,'LLE redirect:.*bzQExy189ZI')).Count
$autoOrderReportCount=([regex]::Matches($combinedFinal,'bink2\.auto_boot_order')).Count
$autoBootCount=([regex]::Matches($combinedFinal,'bink2\.direct_boot_started|bink2\.boot_sequence_selected\s+source=auto-app0')).Count
$naturalMatches=[regex]::Matches($combinedFinal,'bink2\.natural_guest_movie_observed[^\r\n]*file=''([^'']+\.bk2)''')
$attachMatches=[regex]::Matches($combinedFinal,'(?:Bink RAD|Bink2 NIHAV) bridge attached:\s*([^\s'']+\.bk2)')
$completeMatches=[regex]::Matches($combinedFinal,'(?:Bink RAD|Bink2 NIHAV) bridge completed:\s*([^\s'']+\.bk2)')
$shimMatches=[regex]::Matches($combinedFinal,'bink2\.startup_completion_shim[^\r\n]*file=''([^'']+\.bk2)''')
$deviceLostCount=([regex]::Matches($combinedFinal,'(?i)Vulkan device lost|ErrorDeviceLost|VK_ERROR_DEVICE_LOST|DeviceLostException')).Count
$heapCorruptionCount=([regex]::Matches($combinedFinal,'(?i)HEAP_CORRUPTION|0xC0000374')).Count
$unhandledCount=([regex]::Matches($combinedFinal,'(?i)unhandled exception|fatal exception')).Count
$firstFrameMatches=[regex]::Matches($combinedFinal,'Vulkan VideoOut presented first frame:\s*([0-9]+x[0-9]+)')
$firstFrameSize=if($firstFrameMatches.Count -gt 0){$firstFrameMatches[0].Groups[1].Value}else{"none"}
$mainLoopMatches=[regex]::Matches($combinedFinal,'Starting main loop:\s*([0-9]+(?:[.,][0-9]+)?)s')
$mainLoopSeconds=if($mainLoopMatches.Count -gt 0){$mainLoopMatches[$mainLoopMatches.Count-1].Groups[1].Value}else{"not-observed"}
$naturalFiles=@($naturalMatches|ForEach-Object{$_.Groups[1].Value})
$attachedFiles=@($attachMatches|ForEach-Object{$_.Groups[1].Value})
$completedFiles=@($completeMatches|ForEach-Object{$_.Groups[1].Value})
$shimFiles=@($shimMatches|ForEach-Object{$_.Groups[1].Value})

$classification="guest-owned-no-natural-movie-before-close"
if($deviceLostCount -gt 0 -and $heapCorruptionCount -gt 0){$classification="vulkan-device-lost-heap-corruption"}
elseif($deviceLostCount -gt 0){$classification="vulkan-device-lost"}
elseif($autoBootCount -gt 0){$classification="unexpected-host-auto-boot-leak"}
elseif($naturalMatches.Count -ge 3 -and $completeMatches.Count -ge 3){$classification="guest-owned-three-movie-sequence-completed"}
elseif($naturalMatches.Count -ge 2){$classification="guest-owned-sequence-progressed"}
elseif($naturalMatches.Count -eq 1 -and $completeMatches.Count -ge 1){$classification="guest-owned-first-movie-completed"}
elseif($naturalMatches.Count -eq 1){$classification="guest-owned-first-movie-observed"}
elseif($firstFrameMatches.Count -gt 0){$classification="guest-frame-active-awaiting-natural-movie"}

$summaryLines=@(
    "VERSION=74.0.22",
    "WALL_SECONDS=$([Math]::Round($runStopwatch.Elapsed.TotalSeconds,2))",
    "EXIT_POLICY=user-closes-window-or-runtime-exits",
    "RUNNER_FORCED_STOP=False",
    "LAUNCHER_EXIT_CODE=$launcherExitCode",
    "CLASSIFICATION=$classification",
    "EBOOT_SHA256=$actualEboot",
    "ENTRY_FRAME_MARKERS=$entryFrameCount",
    "PROC_PARAM_TRACE_COUNT=$procCount",
    "INIT_ENV_LLE_REDIRECT_COUNT=$lleCount",
    "HOST_AUTO_BOOT_MARKERS=$autoBootCount",
    "AUTO_BOOT_ORDER_REPORTS=$autoOrderReportCount",
    "NATURAL_GUEST_MOVIE_COUNT=$($naturalMatches.Count)",
    "NATURAL_GUEST_MOVIES=$($naturalFiles -join ' -> ')",
    "BINK_ATTACH_COUNT=$($attachMatches.Count)",
    "BINK_ATTACH_FILES=$($attachedFiles -join ' -> ')",
    "BINK_COMPLETED_COUNT=$($completeMatches.Count)",
    "BINK_COMPLETED_FILES=$($completedFiles -join ' -> ')",
    "STARTUP_COMPLETION_SHIM_COUNT=$($shimMatches.Count)",
    "STARTUP_COMPLETION_SHIM_FILES=$($shimFiles -join ' -> ')",
    "FIRST_GUEST_FRAME=$firstFrameSize",
    "MAIN_LOOP_SECONDS=$mainLoopSeconds",
    "DEVICE_LOST_HITS=$deviceLostCount",
    "HEAP_CORRUPTION_HITS=$heapCorruptionCount",
    "UNHANDLED_EXCEPTIONS=$unhandledCount",
    "HOST_MOVIE_BRIDGE_CHANGED=False"
)
[System.IO.File]::WriteAllLines($summaryPath,$summaryLines)

$zipPath=$outputDirectory+".zip"
if([System.IO.File]::Exists($zipPath)){Remove-Item -LiteralPath $zipPath -Force}
Compress-Archive -Path ([System.IO.Path]::Combine($outputDirectory,"*")) -DestinationPath $zipPath -CompressionLevel Optimal -Force

Write-Host "[V74.0.22] RESULT: $classification"
Write-Host "[V74.0.22] Natural movies=$($naturalMatches.Count) completed=$($completeMatches.Count) auto_boot_markers=$autoBootCount first_frame=$firstFrameSize"
Write-Host "[V74.0.22] Result ZIP: $zipPath"
