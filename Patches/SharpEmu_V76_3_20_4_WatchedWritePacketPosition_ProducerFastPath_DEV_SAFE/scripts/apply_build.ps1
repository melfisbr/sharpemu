param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$files=@($CliRel)
$backup=New-Backup 'V76_3_20_4' $files

try {
    $c=Read-Utf8Preserve $CliPath
    $t=$c.Text

    $block=@'
        // V76.3.20.4 - use existing narrow producer fast paths only.
        // WRITE_DATA must be CPU-resident, exact watched range and cross-queue.
        // Same-queue ordering, RELEASE_MEM, DMA and GPU readback remain unchanged.
        Set("SHARPEMU_WATCHED_WRITE_DATA_PACKET_POSITION", "1");
        Set("SHARPEMU_CROSS_QUEUE_WATCHED_INLINE_WRITE", "1");
        Set("SHARPEMU_SKIP_KNOWN_PRODUCER_WAIT_VISIBILITY", "1");
        Set("SHARPEMU_UPSTREAM003_DIRECT_DRAIN", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_ASSIST", "1");
        Set("SHARPEMU_FIFO_WATCHED_PRODUCER_SCAN_DEPTH", "512");
        Set("SHARPEMU_WATCHED_WRITE_CONTROL_LANE", "0");

        Console.Error.WriteLine(
            "[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH] " +
            "packet_position=1 cross_queue_inline=1 known_producer_visibility_elide=1 " +
            "direct_drain=1 same_queue_fifo=preserved release_mem=unchanged dma=unchanged " +
            "queue=192/96 burst=4 inflight=16 dual_physical=1");
'@

    $t=Insert-FinalApplyBlock $t $block '[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH]'
    Write-Utf8Preserve $CliPath $t $c.HasBom

    $check=[IO.File]::ReadAllText($CliPath)
    if(-not$check.Contains('[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH]')){Fail 'novo marker ausente apos apply'}

    $buildLog=Build-Debug $backup.Stamp 'V76_3_20_4'
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
