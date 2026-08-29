param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe=Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game='F:\JOGOSPS5\PPSA01341\eboot.bin'
if(-not(Test-Path -LiteralPath $exe)){Fail "EXE ausente: $exe"}
if(-not(Test-Path -LiteralPath $game)){Fail "eboot ausente: $game"}

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='5'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $Patches ("V76.3.20.4_STDOUT_$stamp.log")
$stderr=Join-Path $Patches ("V76.3.20.4_STDERR_$stamp.log")
$summary=Join-Path $Patches ("V76.3.20.4_SUMMARY_$stamp.txt")
$result=Join-Path $Patches ("V76.3.20.4_RESULT_$stamp.zip")

$started=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main=$false
$first=$false
$deadline=$started.AddSeconds(220)
while(-not$p.HasExited -and (Get-Date)-lt$deadline) {
    Start-Sleep -Milliseconds 500
    if(Test-Path -LiteralPath $stdout) {
        $main=Select-String -LiteralPath $stdout -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue
    }
    if(Test-Path -LiteralPath $stderr) {
        $first=Select-String -LiteralPath $stderr -Pattern 'Vulkan VideoOut presented first frame' -Quiet -ErrorAction SilentlyContinue
    }
    if($main -and $first -and (Get-Date)-gt$started.AddSeconds(190)){break}
}
if(-not$p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out=if(Test-Path $stdout){@(Get-Content $stdout)}else{@()}
$err=if(Test-Path $stderr){@(Get-Content $stderr)}else{@()}

$timeline=@($out|Where-Object{$_ -match 'Starting Initialization:|RecordResourceDependencies\(\) took|Finished Initialization:|Starting Script:|Starting main loop:|GatherResourceFileInfo\(\) took'})
$profile=@($err|Where-Object{$_ -match '\[V76\.3\.20\.4\]\[WATCHED_WRITE_PRODUCER_FASTPATH\]'})
$dual=@($err|Where-Object{$_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]'})
$payload=@($err|Where-Object{$_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'})
$slow=@($err|Where-Object{$_ -match 'SLOW_WAIT_PRODUCER'})
$fast=@($err|Where-Object{$_ -match 'WAIT_REGISTRY_FAST_ONLY|WAIT_REGISTRY_FAST_DRAIN'})
$drain=@($err|Where-Object{$_ -match 'DEDICATED_WAIT_DRAIN'})
$packet=@($err|Where-Object{$_ -match 'WATCHED_WRITE_PACKET_POSITION|CROSS_QUEUE_WATCHED_INLINE_WRITE|KNOWN_PRODUCER_VISIBILITY_ELIDED'})
$residency=@($err|Where-Object{$_ -match '\[V74\.0\.117\.13\]\[SHADER_GLOBAL_RESIDENCY\]'})
$frontend=@($err|Where-Object{$_ -match '\[V74\.0\.117\.10\]\[SHADER_FRONTEND_RESOURCE_FASTPATH\]'})
$mem=@($err|Where-Object{$_ -match '\[V74\.0\.8\.1\]\[MEM\]'})
$perf=@($err|Where-Object{$_ -match '\[PERF\]\[RENDER\]'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})

$gfxMax=0L;$computeMax=0L
foreach($line in $dual) {
    $lm=[regex]::Match($line,'lane=(graphics|compute)')
    $cm=[regex]::Match($line,'lane_count=(\d+)')
    if($lm.Success -and $cm.Success) {
        $v=[long]$cm.Groups[1].Value
        if($lm.Groups[1].Value-eq'graphics') {
            if($v-gt$gfxMax){$gfxMax=$v}
        } else {
            if($v-gt$computeMax){$computeMax=$v}
        }
    }
}

$lastAvg=''
if($payload.Count-gt0) {
    $m=[regex]::Match($payload[-1],'avg=([0-9]+(?:[.,][0-9]+)?)')
    if($m.Success){$lastAvg=$m.Groups[1].Value}
}

$maxFull=0L
foreach($line in $fast) {
    $m=[regex]::Match($line,'full_collects=(\d+)')
    if($m.Success) {
        $v=[long]$m.Groups[1].Value
        if($v-gt$maxFull){$maxFull=$v}
    }
}

@(
 'tag=V76.3.20.4-WATCHED-WRITE-PACKET-POSITION',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$started).TotalSeconds,3))",
 "main_loop_detected=$main",
 "first_frame_detected=$first",
 "dual_graphics_submit_max=$gfxMax",
 "dual_compute_submit_max=$computeMax",
 "payload_batch_last_avg=$lastAvg",
 "wait_full_collects_max=$maxFull",
 "slow_wait_lines=$($slow.Count)",
 "wait_drain_trace_lines=$($drain.Count)",
 "watched_producer_fastpath_trace_lines=$($packet.Count)",
 "residency_trace_lines=$($residency.Count)",
 "frontend_trace_lines=$($frontend.Count)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '',
 '--- PROFILE ---',$profile,
 '',
 '--- BOOT ---',$timeline,
 '',
 '--- DUAL LAST ---',($dual|Select-Object -Last 24),
 '',
 '--- PAYLOAD LAST ---',($payload|Select-Object -Last 16),
 '',
 '--- WAIT FAST LAST ---',($fast|Select-Object -Last 24),
 '',
 '--- WAIT DRAIN LAST ---',($drain|Select-Object -Last 16),
 '',
 '--- SLOW WAIT LAST ---',($slow|Select-Object -Last 32),
 '',
 '--- WATCHED PRODUCER FASTPATH LAST ---',($packet|Select-Object -Last 32),
 '',
 '--- RESIDENCY LAST ---',($residency|Select-Object -Last 24),
 '',
 '--- FRONTEND LAST ---',($frontend|Select-Object -Last 16),
 '',
 '--- PERF LAST ---',($perf|Select-Object -Last 32),
 '',
 '--- MEM LAST ---',($mem|Select-Object -Last 8),
 '',
 '--- DEVICE LOST ---',$device,
 '',
 '--- ACCESS VIOLATION ---',$av,
 '',
 '--- FATAL ---',$fatal
)|Set-Content -LiteralPath $summary -Encoding UTF8

$files=@($stdout,$stderr,$summary)|Where-Object{Test-Path $_}
Compress-Archive -LiteralPath $files -DestinationPath $result -CompressionLevel Optimal -Force

Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first"
Write-Host "[$Tag] dual_gfx=$gfxMax dual_compute=$computeMax payload_avg=$lastAvg full_collects=$maxFull slow_wait=$($slow.Count)"
Write-Host "[$Tag] device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
