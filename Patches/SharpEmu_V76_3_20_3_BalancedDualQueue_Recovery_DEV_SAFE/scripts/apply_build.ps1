param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$files=@($CliRel)
$backup=New-Backup 'V76_3_20_3' $files

try {
    $c=Read-Utf8Preserve $CliPath
    $t=$c.Text

    $block=@'
        // V76.3.20.3 - keep real dual queues/residency but recover the pressure
        // envelope that reached main loop much earlier than V20.2.
        Set("SHARPEMU_PENDING_GUEST_WORK_ITEMS", "192");
        Set("SHARPEMU_PENDING_GUEST_WORK_MB", "96");
        Set("SHARPEMU_KYTY_QUEUE_SUBMISSION_BURST", "4");
        Set("SHARPEMU_RESERVED_HOST_LANES", "6");
        Set("SHARPEMU_MAX_INFLIGHT_GUEST_SUBMISSIONS", "16");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS", "48");
        Set("SHARPEMU_WAIT_FULL_SCAN_MIN_MS", "16");
        Set("SHARPEMU_WAIT_MONITOR_MAX_MS", "4");
        Set("SHARPEMU_WAIT_SOFT_CAP_MS", "20");
        Set("SHARPEMU_DUAL_PHYSICAL_QUEUE", "1");
        Set("SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC", "1");
        Set("SHARPEMU_DUAL_QUEUE_SYNC_POLICY", "resource");
        Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");
        Set("SHARPEMU_AGC_ASYNC_CP_MAX_INGRESS", "1024");
        Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICES", "1");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_MAX_SLICES", "8");
        Set("SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SLICE_PAUSE_US", "1000");
        Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");
        Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");
        Set("SHARPEMU_SYNC_PRIORITY_REAL_WAIT_ONLY", "1");

        Console.Error.WriteLine(
            "[V76.3.20.3][BALANCED_DUAL_QUEUE_RECOVERY] " +
            "queue=192/96 burst=4 inflight=16 host_lanes=6 producer_scan=512 " +
            "dual_physical=1 resource_sync=1 wait_fullscan=16ms " +
            "V20.0_residency=preserved V20.1_100ms=reverted V20.2_deepfeed=reverted");
'@

    $t=Insert-FinalApplyBlock $t $block '[V76.3.20.3][BALANCED_DUAL_QUEUE_RECOVERY]'
    Write-Utf8Preserve $CliPath $t $c.HasBom

    $check=[IO.File]::ReadAllText($CliPath)
    if(-not$check.Contains('[V76.3.20.3][BALANCED_DUAL_QUEUE_RECOVERY]')){Fail 'novo marker ausente apos apply'}

    $buildLog=Build-Debug $backup.Stamp 'V76_3_20_3'
    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug"
    Write-Host "[$Tag] cli_sha256=$(Get-HashLower $CliPath)"
    Write-Host "[$Tag] backup=$($backup.Zip)"
    Write-Host "[$Tag] build_log=$buildLog"
}
catch {
    Restore-Backup $backup $files
    Write-Host "[$Tag] rollback=completed backup=$($backup.Zip)" -ForegroundColor Yellow
    throw
}
finally {
    if(Test-Path $backup.Root){Remove-Item $backup.Root -Recurse -Force -ErrorAction SilentlyContinue}
}
