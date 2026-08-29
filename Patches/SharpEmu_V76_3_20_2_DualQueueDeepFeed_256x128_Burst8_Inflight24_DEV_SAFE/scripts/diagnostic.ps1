param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$exe = Join-Path $Repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
$game = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Fail "EXE ausente: $exe" }
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { Fail "eboot ausente: $game" }

Get-Process SharpEmu -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$env:SHARPEMU_PROFILE_RENDER='1'
$env:SHARPEMU_PROFILE_ORDERED_ACTION='1'
$env:SHARPEMU_PROFILE_RENDER_REPORT_S='5'
$env:SHARPEMU_TRACE_FRAME_STATS='1'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout = Join-Path $Patches ("V76.3.20_2_STDOUT_$stamp.log")
$stderr = Join-Path $Patches ("V76.3.20_2_STDERR_$stamp.log")
$summary = Join-Path $Patches ("V76.3.20_2_SUMMARY_$stamp.txt")
$result = Join-Path $Patches ("V76.3.20_2_RESULT_$stamp.zip")

$start = Get-Date
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList @($game) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$main=$false
$first=$false
$deadline=$start.AddSeconds(220)
while(-not $p.HasExited -and (Get-Date)-lt $deadline) {
    Start-Sleep -Milliseconds 500
    if(Test-Path $stdout) {
        $main=Select-String -LiteralPath $stdout -Pattern 'Starting main loop:' -Quiet -ErrorAction SilentlyContinue
    }
    if(Test-Path $stderr) {
        $first=Select-String -LiteralPath $stderr -Pattern 'Vulkan VideoOut presented first frame' -Quiet -ErrorAction SilentlyContinue
    }
    if($main -and $first -and (Get-Date)-gt $start.AddSeconds(190)) { break }
}
if(-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

$out=if(Test-Path $stdout){@(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)}else{@()}
$err=if(Test-Path $stderr){@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)}else{@()}

$timeline=@($out|Where-Object{$_ -match 'Starting Initialization:|RecordResourceDependencies\(\) took|Finished Initialization:|Starting Script:|Starting main loop:|GatherResourceFileInfo\(\) took'})
$perf=@($err|Where-Object{$_ -match '\[PERF\]\[RENDER\]'})
$device=@($err|Where-Object{$_ -match 'VK_ERROR_DEVICE_LOST|Result\.ErrorDeviceLost|deviceLost=True|\[DEVICE_LOST\]'})
$av=@($err|Where-Object{$_ -match 'AccessViolationException|0xC0000005|ACCESS_VIOLATION'})
$fatal=@($err|Where-Object{$_ -match 'Fatal error\.|FailFast|Unhandled exception|SEHException'})

$dual=@($err|Where-Object{$_ -match '\[V74\.0\.113\.1\]\[DUAL_QUEUE_SUBMIT\]'})
$payload=@($err|Where-Object{$_ -match '\[V74\.0\.56\.20\]\[PAYLOAD_BATCH_SUBMIT\]'})
$starve=@($err|Where-Object{$_ -match 'QUEUE_STARVATION|guest_queue_starvation'})
$slow=@($err|Where-Object{$_ -match 'SLOW_WAIT_PRODUCER'})
$lastAvg=''
if($payload.Count-ne0){
 $m=[regex]::Match($payload[-1],'avg=([0-9]+(?:[.,][0-9]+)?)')
 if($m.Success){$lastAvg=$m.Groups[1].Value}
}
$gfx=0L;$cmp=0L
foreach($line in $dual){
 $lane=[regex]::Match($line,'lane=(graphics|compute)')
 $cnt=[regex]::Match($line,'lane_count=(\d+)')
 if($lane.Success-and$cnt.Success){
  $v=[long]$cnt.Groups[1].Value
  if($lane.Groups[1].Value-eq'graphics'){if($v-gt$gfx){$gfx=$v}}
  else{if($v-gt$cmp){$cmp=$v}}
 }
}
@(
 'tag=V76.3.20.2-DUAL-QUEUE-DEEP-FEED',
 "runtime_seconds=$([Math]::Round(((Get-Date)-$start).TotalSeconds,3))",
 "main_loop_detected=$main",
 "first_frame_detected=$first",
 "dual_graphics_submit_max=$gfx",
 "dual_compute_submit_max=$cmp",
 "payload_batch_last_avg=$lastAvg",
 "queue_starvation_lines=$($starve.Count)",
 "slow_wait_lines=$($slow.Count)",
 "device_lost_markers=$($device.Count)",
 "access_violation_markers=$($av.Count)",
 "fatal_markers=$($fatal.Count)",
 '',
 '--- BOOT ---',$timeline,
 '',
 '--- DUAL SUBMIT LAST ---',($dual|Select-Object -Last 48),
 '',
 '--- PAYLOAD LAST ---',($payload|Select-Object -Last 24),
 '',
 '--- STARVATION LAST ---',($starve|Select-Object -Last 24),
 '',
 '--- SLOW WAIT LAST ---',($slow|Select-Object -Last 24),
 '',
 '--- PERF LAST ---',($perf|Select-Object -Last 32)
)|Set-Content $summary -Encoding UTF8

Compress-Archive -LiteralPath @($stdout,$stderr,$summary) -DestinationPath $result -CompressionLevel Optimal -Force
Write-Host "[$Tag] DIAGNOSTIC COMPLETE main=$main first=$first device=$($device.Count) av=$($av.Count) fatal=$($fatal.Count)"
Write-Host "[$Tag] result=$result"
