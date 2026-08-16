param(
    [string]$RepositoryRoot="",
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74021 -RepositoryRoot $RepositoryRoot
$cpuText=[System.IO.File]::ReadAllText((Get-CpuDispatcherPathV74021 -Root $repoRoot))
$directText=[System.IO.File]::ReadAllText((Get-DirectBackendPathV74021 -Root $repoRoot))
$kernelText=[System.IO.File]::ReadAllText((Get-KernelExportsPathV74021 -Root $repoRoot))
if((Get-EntryAbiStateV74021 -Text $cpuText) -ne "Applied" -or
   (Get-LleInitEnvStateV74021 -Text $directText) -ne "Applied" -or
   (Get-InitEnvStateV74021 -Text $kernelText) -ne "Applied"){
    throw "[V74.0.21] Source correction is not fully applied. Run RUN_3_APPLY_BUILD.cmd first."
}

$ebootPath=[System.IO.Path]::GetFullPath($Eboot)
if(-not [System.IO.File]::Exists($ebootPath)){throw "[V74.0.21] EBOOT missing: $ebootPath"}
$expectedEboot="22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
$actualEboot=(Get-FileHash -LiteralPath $ebootPath -Algorithm SHA256).Hash.ToUpperInvariant()
if($actualEboot -ne $expectedEboot){throw "[V74.0.21] EBOOT SHA256 mismatch: $actualEboot"}

$runtimeDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($runtimeDll)){throw "[V74.0.21] Release runtime missing: $runtimeDll"}
$dotnetCommand=(Get-Command dotnet -ErrorAction Stop).Source

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$outputDirectory=[System.IO.Path]::Combine($repoRoot,"SharpEmu_V74_0_21_ENTRY_ABI_RESULT_$stamp")
[System.IO.Directory]::CreateDirectory($outputDirectory)|Out-Null
$stdoutPath=[System.IO.Path]::Combine($outputDirectory,"stdout.log")
$stderrPath=[System.IO.Path]::Combine($outputDirectory,"stderr.log")
$profilePath=[System.IO.Path]::Combine($outputDirectory,"RUN_PROFILE.txt")
$summaryPath=[System.IO.Path]::Combine($outputDirectory,"SUMMARY.txt")

$environmentProfile=[ordered]@{
    SHARPEMU_BINK_AUTO_BOOT="0"
    SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="0"
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
$profileLines.Add("version=74.0.21")
$profileLines.Add("eboot=$ebootPath")
$profileLines.Add("eboot_sha256=$actualEboot")
$profileLines.Add("runtime=$runtimeDll")
foreach($environmentName in $environmentProfile.Keys){$profileLines.Add("$environmentName=$($environmentProfile[$environmentName])")}
[System.IO.File]::WriteAllLines($profilePath,$profileLines)

Write-Host "[V74.0.21] ENTRY ABI test starting."
Write-Host "[V74.0.21] Host Bink auto boot is OFF for this diagnostic."
Write-Host "[V74.0.21] LLE _init_env gate + ProcParam trace are ON."
Write-Host "[V74.0.21] EBOOT SHA256 OK: $actualEboot"

$runStopwatch=[System.Diagnostics.Stopwatch]::StartNew()
$processObject=$null
$proofSeenAt=$null
$absoluteDeadlineSeconds=240
$postProofSeconds=20
$stopReason="absolute-deadline"

try{
    $dotnetArgumentLine='"{0}" "{1}"' -f $runtimeDll,$ebootPath
    $processObject=Start-Process -FilePath $dotnetCommand -ArgumentList $dotnetArgumentLine -WorkingDirectory (Split-Path -Parent $runtimeDll) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    while($runStopwatch.Elapsed.TotalSeconds -lt $absoluteDeadlineSeconds){
        Start-Sleep -Milliseconds 500
        $processObject.Refresh()
        $stderrText=Read-TextSharedV74021 -Path $stderrPath
        $stdoutText=Read-TextSharedV74021 -Path $stdoutPath
        $combinedText=$stderrText+"`n"+$stdoutText

        $frameProof=$combinedText.Contains("[V74.0.21][ENTRY_ABI] frame")
        $procProof=$combinedText.Contains("proc_param: address=0x00000008027A7E80")
        $lleProof=($combinedText -match 'LLE redirect:.*bzQExy189ZI')
        $hleProof=$combinedText.Contains("[V74.0.21][ENTRY_ABI] init_env_hle_fallback")
        $initProof=($lleProof -or $hleProof)

        if($frameProof -and $procProof -and $initProof -and $null -eq $proofSeenAt){
            $proofSeenAt=$runStopwatch.Elapsed.TotalSeconds
            Write-Host ([string]::Format("[V74.0.21] ABI proof captured at t={0:F1}s; observing {1}s more.",$proofSeenAt,$postProofSeconds))
        }
        if($null -ne $proofSeenAt -and ($runStopwatch.Elapsed.TotalSeconds-$proofSeenAt) -ge $postProofSeconds){
            $stopReason="abi-proof-plus-observation"
            break
        }
        if($processObject.HasExited){$stopReason="process-exited";break}
    }
} finally {
    if($null -ne $processObject){
        try{$processObject.Refresh()}catch{}
        if(-not $processObject.HasExited){
            Stop-ProcessTreeV74021 -RootId $processObject.Id
            try{$processObject.WaitForExit(5000)}catch{}
        }
    }
    foreach($environmentName in $environmentProfile.Keys){
        [Environment]::SetEnvironmentVariable($environmentName,$previousEnvironment[$environmentName],"Process")
    }
}
$runStopwatch.Stop()
Start-Sleep -Milliseconds 500

$stderrFinal=Read-TextSharedV74021 -Path $stderrPath
$stdoutFinal=Read-TextSharedV74021 -Path $stdoutPath
$combinedFinal=$stderrFinal+"`n"+$stdoutFinal
$frameCount=([regex]::Matches($combinedFinal,'\[V74\.0\.21\]\[ENTRY_ABI\] frame')).Count
$procCount=([regex]::Matches($combinedFinal,'proc_param: address=0x00000008027A7E80')).Count
$lleCount=([regex]::Matches($combinedFinal,'LLE redirect:.*bzQExy189ZI')).Count
$hleCount=([regex]::Matches($combinedFinal,'\[V74\.0\.21\]\[ENTRY_ABI\] init_env_hle_fallback')).Count
$hostAutoBootCount=([regex]::Matches($combinedFinal,'bink2\.auto_boot_order')).Count
$naturalMovieCount=([regex]::Matches($combinedFinal,'bink2\.(?:natural_movie|host_open_request|open_request).*\.bk2')).Count
$unhandledCount=([regex]::Matches($combinedFinal,'(?i)unhandled exception|fatal exception')).Count
$entryPointObserved=($combinedFinal -match 'ExecuteEntry starting at 0x0000000800000070')
$fullLayoutObserved=($combinedFinal -match '\[V74\.0\.21\]\[ENTRY_ABI\] frame .*size=0x118 .*entry=0x0000000800000070')
$procParamObserved=($procCount -gt 0)
$initEnvPath=if($lleCount -gt 0){"LLE"}elseif($hleCount -gt 0){"HLE_FALLBACK"}else{"NOT_OBSERVED"}
$classification=if($frameCount -gt 0 -and $procParamObserved -and ($lleCount -gt 0 -or $hleCount -gt 0) -and $hostAutoBootCount -eq 0){
    "entry-abi-proof-captured"
}elseif($frameCount -gt 0 -and $procParamObserved){
    "entry-and-procparam-captured-initenv-unresolved"
}else{
    "entry-abi-proof-incomplete"
}

$summaryLines=@(
    "VERSION=74.0.21",
    "WALL_SECONDS=$([Math]::Round($runStopwatch.Elapsed.TotalSeconds,2))",
    "STOP_REASON=$stopReason",
    "CLASSIFICATION=$classification",
    "EBOOT_SHA256=$actualEboot",
    "ENTRY_POINT_800000070_OBSERVED=$entryPointObserved",
    "ENTRY_FRAME_MARKERS=$frameCount",
    "FULL_0X118_LAYOUT_OBSERVED=$fullLayoutObserved",
    "PROC_PARAM_8027A7E80_OBSERVED=$procParamObserved",
    "PROC_PARAM_TRACE_COUNT=$procCount",
    "INIT_ENV_PATH=$initEnvPath",
    "INIT_ENV_LLE_REDIRECT_COUNT=$lleCount",
    "INIT_ENV_HLE_FALLBACK_COUNT=$hleCount",
    "HOST_AUTO_BOOT_MARKERS=$hostAutoBootCount",
    "NATURAL_MOVIE_MARKERS=$naturalMovieCount",
    "UNHANDLED_EXCEPTIONS=$unhandledCount",
    "NATIVE_ENTRY_TRAMPOLINE_CHANGED=False",
    "HOST_MOVIE_BRIDGE_CHANGED=False"
)
[System.IO.File]::WriteAllLines($summaryPath,$summaryLines)

$sourceStatePath=[System.IO.Path]::Combine($outputDirectory,"SOURCE_STATE.txt")
$finalCpuSource=[System.IO.File]::ReadAllText((Get-CpuDispatcherPathV74021 -Root $repoRoot))
$finalDirectSource=[System.IO.File]::ReadAllText((Get-DirectBackendPathV74021 -Root $repoRoot))
$finalKernelSource=[System.IO.File]::ReadAllText((Get-KernelExportsPathV74021 -Root $repoRoot))
$finalCpuState=Get-EntryAbiStateV74021 -Text $finalCpuSource
$finalDirectState=Get-LleInitEnvStateV74021 -Text $finalDirectSource
$finalKernelState=Get-InitEnvStateV74021 -Text $finalKernelSource
$sourceStateLines=@(
    "CpuDispatcher.EntryParams=$finalCpuState",
    "DirectExecutionBackend.InitEnv=$finalDirectState",
    "KernelExports.InitEnv=$finalKernelState"
)
[System.IO.File]::WriteAllLines($sourceStatePath,$sourceStateLines)

$zipPath=$outputDirectory+".zip"
if([System.IO.File]::Exists($zipPath)){Remove-Item -LiteralPath $zipPath -Force}
Compress-Archive -Path ([System.IO.Path]::Combine($outputDirectory,"*")) -DestinationPath $zipPath -CompressionLevel Optimal -Force

Write-Host "[V74.0.21] RESULT: $classification"
Write-Host "[V74.0.21] EntryFrame=$frameCount ProcParam=$procCount InitEnv=$initEnvPath HostAutoBoot=$hostAutoBootCount Unhandled=$unhandledCount"
Write-Host "[V74.0.21] Result ZIP: $zipPath"
