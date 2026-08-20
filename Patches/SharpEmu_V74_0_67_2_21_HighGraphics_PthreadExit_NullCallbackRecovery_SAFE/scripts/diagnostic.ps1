. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$exceptions=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$kernel=Join-Path $repo 'src\SharpEmu.Libs\Kernel\KernelExports.cs'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$e=Normalize-Lf ([IO.File]::ReadAllText($exceptions))
$k=Normalize-Lf ([IO.File]::ReadAllText($kernel))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$c=Normalize-Lf ([IO.File]::ReadAllText($csproj))

$methodStart=$e.IndexOf(
    'private unsafe bool TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(',
    [StringComparison]::Ordinal)
$methodEnd=if($methodStart-ge 0){
    $e.IndexOf(
        '	private unsafe bool TryRecoverAuxiliaryThreadExecuteFault(',
        $methodStart,
        [StringComparison]::Ordinal)
}else{-1}
$method=if($methodStart-ge 0 -and $methodEnd-gt $methodStart){
    $e.Substring($methodStart,$methodEnd-$methodStart)
}else{''}

$newCall=$e.IndexOf(
    'TryRecoverHighGraphicsPthreadExitNullCallbackV74067221(',
    [StringComparison]::Ordinal)
$auxCall=$e.IndexOf(
    'TryRecoverAuxiliaryThreadExecuteFault(exceptionRecord, contextRecord, rip)',
    [StringComparison]::Ordinal)

$checks=[ordered]@{
    marker=$e.Contains('V74.0.67.2.21 HighGraphics pthread-exit null-callback recovery')
    method_present=$method.Length-gt 0
    exact_av_code=$method.Contains('exceptionRecord->ExceptionCode != 3221225477u')
    exact_execute_kind=$method.Contains('ExceptionInformation[0] != 8')
    exact_target_zero=$method.Contains('ExceptionInformation[1] != 0')
    exact_rip_zero=$method.Contains('rip != 0')
    exact_thread=$method.Contains('"HighGraphics"')
    exact_nid=$method.Contains('"3kg7rT0NQIs"')
    import_in_progress=$method.Contains('LastImportResultValid) != 0')
    exact_exit_value=$method.Contains('activeThread.LastImportRdi != 0')
    host_exit_gate=$method.Contains('ActiveEntryReturnSentinelRip')
    return_slot_gate=$method.Contains('TryPatchActiveGuestReturnSlot(hostExit)')
    neutral_rax=$method.Contains('WriteCtxU64(contextRecord, 120, 0);')
    redirect_rip=$method.Contains('WriteCtxU64(contextRecord, 248, hostExit);')
    telemetry=$method.Contains('[V74.0.67.2.21][PTHREAD_EXIT_NULL_CALLBACK]')
    ordered_before_aux=$newCall-ge 0 -and $auxCall-ge 0 -and $newCall-lt $auxCall
    sce_pthread_exit_unchanged=$k.Contains('GuestThreadExecution.RequestCurrentEntryExit("scePthreadExit", value);')
    v218_preserved=$e.Contains('V74.0.67.2.18 BPE head2 end-sentinel recovery')
    v219_quality=$b.Contains('var effectiveQuality = requestedQuality;')
    v220_deployment=$c.Contains('V74.0.67.2.20 DLSS dual-config runtime deployment')
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.21] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

foreach($config in @('Debug','Release')){
    $provider=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll"
    $ngx=Join-Path $repo "artifacts\bin\$config\net10.0\win-x64\nvngx_dlss.dll"
    $providerOk=Test-Path -LiteralPath $provider -PathType Leaf
    $ngxOk=Test-Path -LiteralPath $ngx -PathType Leaf
    $line="[V74.0.67.2.21] $($config.ToLowerInvariant())_dlss_runtime=$($providerOk -and $ngxOk)"
    Write-Host $line
    $result.Add($line)
    if(!$providerOk -or !$ngxOk){$failed=$true}
}

$result.Add('[V74.0.67.2.21] RECOVERY_SCOPE=HighGraphics+scePthreadExit+result-invalid+RDI0+execute-null')
$result.Add('[V74.0.67.2.21] RECOVERY_ACTION=nested-callback->active-host-exit;no-worker-abort')
$result.Add('[V74.0.67.2.21] PTHREAD_EXIT_OWNER=preserved')
$result.Add('[V74.0.67.2.21] DLSS_PROVIDER_CHANGE=false')
$result.Add('[V74.0.67.2.21] EXPECTED_RUNTIME=PTHREAD_EXIT_NULL_CALLBACK then normal thread completion')

if($failed){throw '[V74.0.67.2.21] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.21] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.21] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_21_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_21_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.21] ResultZip=$zip"
